#!/usr/bin/env python3
"""Equal-input synthetic directory/direct-query comparison, not a Finder trial.

Both arms receive the same known project root and literal task terms. Directory
search uses actual ripgrep path/body matches and a bounded folder fallback;
Gleaner uses actual CLI/shared core and a project overview fallback. Both open all
first-five candidates, without consulting relevance labels. Labels score afterward.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[3]
module_spec = importlib.util.spec_from_file_location("retrieval_fixture", ROOT / "eval/retrieval/run.py")
fixture = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(fixture)


def evaluate(home):
    world = fixture.World(home)
    tasks = []

    report = world.put("BaySurvey", "deliveries/Q-17.md", "# Riparian proposal\nRestore the east-bank planting zone.\n")
    inputs = world.put("BaySurvey", "analysis/inputs.csv", "reach,depth\neast,2\n")
    generator = world.put("BaySurvey", "tools/reduce.py", "# Compute the sampling table. Synthetic text; never executed.\n")
    world.log("BaySurvey", "Prepare the riparian proposal and supporting calculations",
              "[Proposal](deliveries/Q-17.md) [Inputs](analysis/inputs.csv) [Generator](tools/reduce.py)")
    tasks.append({"id": "body_names_the_wanted_proposal", "project": "BaySurvey", "terms": ["riparian", "proposal"],
                  "wanted": [report], "task": "Read the proposal; supporting computations are secondary evidence."})

    review = world.put("Spectra", "notes.md", "# Boron review\nReview the calibration and run the reproduction.\n")
    reproduction = world.put("Spectra", "reproduce.py", "# Boron review reproduction. Synthetic text; never executed.\n")
    raw = world.put("Spectra", "raw.csv", "boron,review,uncorrected\n2,1,true\n")
    world.log("Spectra", "Return the boron review and reproduction with raw measurements",
              "[Review](notes.md) [Reproduction](reproduce.py) [Raw](raw.csv)", provider="codex")
    tasks.append({"id": "two_complementary_objects", "project": "Spectra", "terms": ["boron", "review"],
                  "wanted": [review, reproduction], "task": "Inspect the review and its runnable reproduction; raw measurements are optional."})

    panel = world.put("CedarGraphics", "panel.svg", "<svg><title>Panel variants</title><text>Interchange</text></svg>\n")
    world.log("CedarGraphics", "Draw the copper transit diagram", "[Diagram](panel.svg)")
    tasks.append({"id": "context_terms_need_folder_fallback", "project": "CedarGraphics", "terms": ["copper", "transit"],
                  "wanted": [panel], "task": "Open the diagram; task words exist in the native request, not the original text."})

    world.put("MarshAccess", "background.md", "# Flood background\nSurvey context.\n")
    world.log("MarshAccess", "Record flood background", "[Background](background.md)")
    runner = fixture.Runner(SimpleNamespace(
        runner="docker exec gleaner-swift runuser -u gleaner --",
        cli=str(ROOT / ".build/debug/gleaner"), indexer=str(ROOT / ".build/debug/gleaner-index")))
    index, index_seconds = runner.call(runner.args.indexer, ["--home", str(home), "--now", fixture.stamp(world.clock)])
    if "error" in index or "invalid_json" in index:
        raise RuntimeError("Actual indexer failed: " + json.dumps(index))
    current = world.put("MarshAccess", "estuary-access.md", "# Estuary access\nA new current survey that no agent delivered.\n")
    tasks.append({"id": "current_file_outside_index_admission", "project": "MarshAccess", "terms": ["estuary", "access"],
                  "wanted": [current], "task": "Open the new current survey. Created after indexing, with no delivery log; this is a discovery/admission difference."})

    outcomes = []
    for task in tasks:
        project = world.project(task["project"])
        def relative(path):
            return str(Path(path).relative_to(home))

        # Real recursive discovery, explicitly bounded before body searching. Ripgrep does not
        # follow symlinks here. These fixtures contain no ignored/dependency trees or binary files.
        enumeration = subprocess.run(["rg", "--files", "--hidden", "--no-ignore", "-0", str(project)], check=True, capture_output=True)
        paths = sorted(Path(p.decode()) for p in enumeration.stdout.split(b"\0") if p)
        if len(paths) > 100 or any(p.is_symlink() or p.stat().st_size > 32768 for p in paths):
            raise RuntimeError("Comparator fixture exceeds its bounded corpus contract")
        candidates = set(paths)
        subprocess_bytes = len(enumeration.stdout)
        for term in task["terms"]:
            matched = subprocess.run(["rg", "--files-with-matches", "--fixed-strings", "--ignore-case",
                                      "--hidden", "--no-ignore", "--null", "--", term, str(project)], capture_output=True)
            if matched.returncode not in (0, 1):
                raise RuntimeError("ripgrep body search failed")
            content = {Path(p.decode()) for p in matched.stdout.split(b"\0") if p}
            named = {p for p in paths if term.casefold() in str(p.relative_to(project)).casefold()}
            candidates &= content | named
            subprocess_bytes += len(matched.stdout)
        filtered = sorted(candidates)
        folder_fallback = not filtered
        shown = (filtered or paths)[:5]
        opened = [{"path": relative(p), "bytes": len(data := p.read_bytes()), "sha256": hashlib.sha256(data).hexdigest()} for p in shown]
        directory = {"mode": "path_and_body_then_folder_fallback", "filtered_matches": [relative(p) for p in filtered],
                     "folder_fallback": folder_fallback, "first_layer": [relative(p) for p in shown],
                     "opened": opened, "discovered_file_count": len(paths), "enumerations": 1,
                     "literal_body_searches": len(task["terms"]), "view_changes": int(folder_fallback),
                     "open_operations": len(opened), "tool_stdout_bytes": subprocess_bytes,
                     "body_scan_bytes_upper_bound": len(task["terms"]) * sum(p.stat().st_size for p in paths)}

        before = len(runner.calls)
        answer, _ = runner.query(home, ["find", *task["terms"], "--project", task["project"], "--limit", "1000"])
        if "results" not in answer:
            raise RuntimeError("Actual shared query failed: " + json.dumps(answer))
        filtered_core = answer["results"]
        project_fallback = not filtered_core
        if project_fallback:
            answer, _ = runner.query(home, ["find", "", "--project", task["project"], "--limit", "1000"])
        shown_core = answer["results"][:5]
        reads = []
        for row in shown_core:
            reference = row["reference"]
            data, _ = runner.query(home, ["read", reference["delivery"], "--max", "4096"])
            reads.append({"path": relative(reference["path"]), "exact_version_readable": "text" in data,
                          "returned_text_bytes": len(data.get("text", "").encode())})
        core = {"mode": "shared_query_then_project_fallback", "filtered_matches": [relative(r["reference"]["path"]) for r in filtered_core],
                "project_fallback": project_fallback, "first_layer": [relative(r["reference"]["path"]) for r in shown_core],
                "opened": reads, "query_operations": 1 + int(project_fallback), "open_operations": len(reads),
                "tool_stdout_bytes": sum(call["stdout_bytes"] for call in runner.calls[before:])}

        # Ground-truth labels enter only here, after both query and open plans executed.
        wanted = set(task["wanted"])
        for arm in [directory, core]:
            relevant = wanted & set(arm["first_layer"])
            arm["relevant_first_layer"] = sorted(relevant)
            arm["precision_at_first_layer"] = len(relevant) / len(arm["first_layer"]) if arm["first_layer"] else 0
            arm["wanted_recall_at_first_layer"] = len(relevant) / len(wanted)
        outcomes.append({**task, "directory": directory, "shared_core": core})
    return {"schema": 1, "kind": "equal_input_development_comparator", "tasks": outcomes,
            "input_contract": "Same known authorized project root and task terms; no target basename or relevance label used to select/open candidates. Both arms open every first-five result; empty literal search gets one broad overview fallback.",
            "limits": "Small synthetic text corpus; no human/Finder UI trial, semantic file understanding, history equivalence, cold-cache or end-to-end latency comparison. Directory reads current bytes; CLI reads exact captured bytes. CLI subprocesses cross Docker boundary while rg runs on host; stdout sizes are actual different response schemas, not relevance metrics.",
            "index_seconds_including_process_boundary": index_seconds, "index_report": index,
            "tools": {"rg": subprocess.check_output(["rg", "--version"], text=True).splitlines()[0],
                      "gleaner_sha256": hashlib.sha256((ROOT / ".build/debug/gleaner").read_bytes()).hexdigest(),
                      "gleaner_index_sha256": hashlib.sha256((ROOT / ".build/debug/gleaner-index").read_bytes()).hexdigest()}}


parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
workspace = Path("/workspace/gleaner-evaluation/cycle3")
workspace.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="directory-comparison-", dir=workspace) as directory:
    home = Path(directory)
    home.chmod(0o777)  # Disposable synthetic home shared with the unprivileged container UID.
    report = evaluate(home)
    # Keep no host temporary locator in the public report.
    text = json.dumps(report, indent=2, sort_keys=True).replace(str(home), "$SYNTHETIC_HOME")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(text + "\n")
print(args.output)
