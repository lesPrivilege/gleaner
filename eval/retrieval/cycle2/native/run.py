#!/usr/bin/env python3
"""Link a synthetic diagnostic to existing SwiftPM core objects; never edit/build the package.

Example: python3 eval/retrieval/cycle2/native/run.py --repository /workspace/gleaner-baseline \
    --output docs/retrieval-core/cycle2/native-probe-baseline.json
The existing gleaner-swift container must mount the repository and gleaner-evaluation.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--repository", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--local", action="store_true", help="Run using an already built local Swift core, including on an authorized Mac")
args = parser.parse_args()
repository = args.repository.resolve()
build = (repository / ".build/debug").resolve()
source = Path(__file__).resolve().with_name("NativeProbe.swift")
local_temp = tempfile.TemporaryDirectory(prefix="gleaner-native-diagnostic-") if args.local else None
out = Path(local_temp.name if local_temp else "/workspace/gleaner-evaluation/cycle2/native") / (repository.name + "-probe")
out.parent.mkdir(parents=True, exist_ok=True)
objects = []
portable_crypto = not (args.local and sys.platform == "darwin")
targets = ["GleanerCore"] + (["Crypto", "CryptoBoringWrapper", "CCryptoBoringSSLShims", "CCryptoBoringSSL"] if portable_crypto else [])
for target in targets:
    objects.extend(sorted((build / (target + ".build")).rglob("*.o")))
if not objects:
    raise SystemExit("Build the real core first; no substitute implementation is provided.")
command = [] if args.local else ["docker", "exec", "gleaner-swift", "runuser", "-u", "gleaner", "--"]
flags = ["-I", str(build / "Modules")]
if portable_crypto:
    flags += ["-Xcc", "-fmodule-map-file=" + str(repository / "Sources/CSQLite/module.modulemap")]
    for name in ["CCryptoBoringSSLShims", "CCryptoBoringSSL"]:
        inc = repository / ".build/checkouts/swift-crypto/Sources" / name / "include"
        flags += ["-Xcc", "-fmodule-map-file=" + str(inc / "module.modulemap"), "-Xcc", "-I" + str(inc)]
link = ["-lsqlite3"] + (["-lstdc++"] if portable_crypto else [])
compiled = subprocess.run(command + ["swiftc", str(source), *flags, *map(str, objects), *link, "-o", str(out)])
if compiled.returncode:
    raise SystemExit(compiled.returncode)
result = subprocess.run(command + [str(out)], check=True, capture_output=True, text=True)
data = json.loads(result.stdout)
data["repository_revision"] = subprocess.check_output(["git", "-C", str(repository), "rev-parse", "HEAD"], text=True).strip()
data["probe_source"] = "eval/retrieval/cycle2/native/NativeProbe.swift"
data["probe_sha256"] = hashlib.sha256(source.read_bytes()).hexdigest()
data["execution_mode"] = "local" if args.local else "container"
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
print(args.output)
if local_temp:
    local_temp.cleanup()
