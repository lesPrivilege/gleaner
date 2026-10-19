#!/usr/bin/env python3
"""Synthetic retrieval evaluation through the shipped shared core executables.

No implementation of extraction, matching or ranking lives here. Gold describes
the intended task, including deliberate unsupported/ambiguous cases. A subprocess
argv is always an array; log text is never executed. Existing E0 is unchanged.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import time
from datetime import datetime, timezone, timedelta


def digest(data):
    return hashlib.sha256(data).hexdigest()


def stamp(value):
    return value.isoformat(timespec="milliseconds").replace("+00:00", "Z")


class World:
    def __init__(self, home, variant="original"):
        self.home = home
        self.variant = variant
        self.clock = datetime.now(timezone.utc) + timedelta(seconds=2)
        self.files = {}
        self.delivered = set()
        self.tasks = []
        self.logs = {}

    def project(self, name):
        # Renaming changes context words and physical roots, not relevance labels.
        if self.variant == "renamed":
            name = {"SilverMarsh": "TideRadio", "GlassStudio": "CopperAtelier",
                    "Harbor": "Quay", "RelayForge": "CircuitWorks",
                    "FieldLab": "RiverSurvey", "TwinLab": "SecondSurvey"}.get(name, name)
        return self.home / "Projects" / name

    def put(self, project, relative, body):
        path = self.project(project) / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        data = body.encode() if isinstance(body, str) else body
        path.write_bytes(data)
        t = (self.clock - timedelta(seconds=20)).timestamp()
        os.utime(path, (t, t))
        key = str(path.relative_to(self.home))
        self.files[key] = digest(data)
        return key

    def log(self, project, request, reply, provider="claude", suffix="main"):
        cwd = str(self.project(project))
        sid = self.project(project).name + "-" + suffix
        at = stamp(self.clock)
        start = stamp(self.clock - timedelta(minutes=2))
        if provider == "claude":
            path = self.home / ".claude/projects" / sid / "session.jsonl"
            records = [
                {"type": "user", "origin": {"kind": "human"}, "message": {"role": "user", "content": request}, "timestamp": start, "cwd": cwd, "sessionId": sid},
                {"type": "assistant", "message": {"role": "assistant", "model": "synthetic", "content": [{"type": "text", "text": reply}]}, "timestamp": at, "cwd": cwd, "sessionId": sid},
            ]
        else:
            path = self.home / ".codex/sessions/2026/10/19" / ("rollout-" + sid + ".jsonl")
            records = [
                {"type": "session_meta", "timestamp": start, "payload": {"id": sid, "cwd": cwd, "thread_source": "user", "model_provider": "synthetic"}},
                {"type": "turn_context", "timestamp": start, "payload": {"turn_id": sid, "cwd": cwd, "model": "synthetic"}},
                {"type": "response_item", "timestamp": start, "payload": {"type": "message", "role": "user", "content": [{"type": "input_text", "text": request}], "internal_chat_message_metadata_passthrough": {"content_item_kinds": ["user.text"]}}},
                {"type": "response_item", "timestamp": at, "payload": {"type": "message", "role": "assistant", "phase": "final_answer", "content": [{"type": "output_text", "text": reply}]}},
            ]
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a") as stream:
            for record in records:
                stream.write(json.dumps(record) + "\n")
        self.logs[sid] = path
        return path

    def task(self, name, terms, wanted, project=None, note=""):
        self.tasks.append({"id": name, "terms": terms, "wanted": wanted,
                           "project": self.project(project).name if project else None,
                           "note": note})

    def prepare(self, scale):
        media = [self.put("SilverMarsh", f"season-two/episode-{i:02d}.mp4", f"synthetic media payload {i}\n") for i in range(1, 25)]
        self.log("SilverMarsh", "Prepare the second season episodes", "Finished files: `season-two/episode-{01..24}.mp4`.")
        self.delivered.update(media)
        self.task("numeric-series", ["episode"], media, "SilverMarsh")

        boards = [self.put("GlassStudio", f"exports/moodboard-{color}.svg", f"<svg><title>{color}</title></svg>") for color in ("dusk", "sand", "lake")]
        self.put("GlassStudio", "exports/node_modules/vendor.js", "dependency, not a delivered member")
        self.put("GlassStudio", "exports/.cache/thumb.svg", "cache, not a delivered member")
        self.log("GlassStudio", "Prepare the collection", "Review the collection in `exports/`.", provider="codex")
        self.delivered.update(boards)
        self.task("relative-folder", ["moodboard"], boards, "GlassStudio")

        cover = self.put("Harbor", "CedarVault/artwork/cover-square.svg", "<svg><title>Cover</title></svg>")
        self.log("Harbor", "Draw the artwork", "[Cover](CedarVault/artwork/cover-square.svg)")
        self.delivered.add(cover)
        self.task("parent-context", ["CedarVault", "cover"], [cover], "Harbor")
        self.task("vocabulary-mismatch", ["shipping", "illustration"], [cover], "Harbor", "Intended cover; terms absent from indexed evidence. No inferred synonym authority.")

        spec = self.put("RelayForge", "docs/spec.md", "# Connection design\n\n## R1 Retry safety\nDo not repeat committed writes.\n\n## R3 Cancellation\nAbort before the commit.\n")
        intermediates = [self.put("RelayForge", f"tools/check-{i}.py", f"# validation helper {i}\n") for i in range(8)]
        reply = "Design: [spec](docs/spec.md).\n" + "\n".join(f"Helper: [code](tools/check-{i}.py)." for i in range(8))
        self.log("RelayForge", "Review the connection spec and its checks", reply)
        self.delivered.update([spec] + intermediates)
        self.task("same-request-noise", ["spec"], [spec], "RelayForge", "Helpers are useful evidence, but not answers to the requested spec.")

        body = "# Estuary observations\n\n## R1 Sampling bias\nThe north inlet was sampled twice.\n\n## R3 Recheck\nNo later ruling was communicated.\n"
        report = self.put("FieldLab", "reports/round-one.md", body)
        twin = self.put("TwinLab", "reports/round-one.md", body)
        self.log("FieldLab", "Review the estuary sampling", "[Review](reports/round-one.md)", provider="codex")
        self.log("TwinLab", "Review a separate control survey", "[Review](reports/round-one.md)")
        self.delivered.update([report, twin])
        self.task("equal-bytes-separate-context", ["round-one"], [report], "FieldLab")
        self.task("report-finding", ["R1"], [report], "FieldLab", "Body-only section; global file metadata search is not section search. Scoped outline evaluated separately.")

        missing = str((self.project("FieldLab") / "reports/unavailable.pdf").relative_to(self.home))
        self.log("FieldLab", "Return the archived appendix", "[Appendix](reports/unavailable.pdf)", suffix="missing")
        self.delivered.add(missing)
        self.task("missing-original", ["unavailable"], [missing], "FieldLab", "Retrievable evidence, no bytes; task success must stay false.")
        self.log("GlassStudio", "Describe a future export command", "Potential filename pattern: `exports/*.svg`.", suffix="pattern")

        # An explicit folder lets the real core discover scale files. No fake
        # direct database inserts and no effect on the task-specific project scopes.
        for i in range(scale):
            self.put("ScaleDepot", f"deliverables/batch-{i:05d}.txt", f"Synthetic workload item {i}\n")
        if scale:
            folder = self.project("ScaleDepot") / "deliverables"
            self.log("ScaleDepot", "Return the generated batch", f"[Batch]({folder})")

        if self.variant == "irrelevant":
            for i in range(75):
                self.put("Unrelated", f"scratch/cache-{i}.log", "unobserved construction debris")
            self.log("Unrelated", "Summarize progress", "No output was delivered.")
        if self.variant == "duplicated":
            # The same target twice in one reply must not double its logical row.
            self.log("Harbor", "Draw the artwork", "[Cover](CedarVault/artwork/cover-square.svg) [Again](CedarVault/artwork/cover-square.svg)", suffix="duplicate")
        return report


class Runner:
    def __init__(self, args):
        self.args = args
        self.prefix = shlex.split(args.runner)
        self.calls = []

    def call(self, executable, argv):
        started = time.perf_counter()
        run = subprocess.run(self.prefix + [executable] + argv, text=True, capture_output=True, timeout=240)
        elapsed = time.perf_counter() - started
        try:
            value = json.loads(run.stdout)
        except json.JSONDecodeError:
            value = {"invalid_json": run.stdout[:500], "stderr": run.stderr[:500]}
        self.calls.append({"command": Path(executable).name, "arguments": argv,
                           "seconds": elapsed, "stdout_bytes": len(run.stdout.encode()), "status": run.returncode})
        return value, elapsed

    def query(self, home, argv):
        return self.call(self.args.cli, argv + ["--home", str(home)])


def evaluate(args):
    home = Path(args.home).absolute()
    if home.exists():
        raise SystemExit("Use a fresh synthetic --home; refusing to overwrite an existing directory")
    home.mkdir(parents=True)
    world = World(home, args.variant)
    report_path = world.prepare(args.scale)
    runner = Runner(args)
    index, index_seconds = runner.call(args.indexer, ["--home", str(home), "--now", stamp(world.clock + timedelta(seconds=10))])
    if "error" in index or "invalid_json" in index:
        raise SystemExit(json.dumps(index))
    # The existing CLI requires a positional term; an explicit empty term
    # reaches the existing Catalog empty-token enumeration contract.
    all_results, _ = runner.query(home, ["find", "", "--limit", "1000"])
    if "results" not in all_results:
        raise RuntimeError("Enumeration failed: " + json.dumps(all_results))
    rows = all_results.get("results", [])
    paths = {str(Path(r["reference"]["path"]).relative_to(home)) for r in rows}
    capture = world.delivered & paths
    tasks = []
    for task in world.tasks:
        argv = ["find"] + task["terms"] + ["--limit", "1000"]
        if task["project"]:
            argv += ["--project", task["project"]]
        answer, seconds = runner.query(home, argv)
        if "results" not in answer:
            raise RuntimeError("Query failed: " + json.dumps(answer))
        hits = answer.get("results", [])
        found = [str(Path(h["reference"]["path"]).relative_to(home)) for h in hits]
        wanted = set(task["wanted"])
        first = found[:5]
        relevant = set(found) & wanted
        usable_originals = 0
        usable_versions = 0
        expansions = 0
        scope_correct = True
        for hit, path in zip(hits, found):
            if path not in wanted:
                continue
            scope_correct &= hit["project"]["name"] == task["project"] if task["project"] else True
            ref = hit["reference"]
            # Physical resolvability is measured independently of hash-backed availability.
            if Path(ref["path"]).is_file():
                usable_originals += 1
            if ref["availability"]["state"] in ("original", "saved_copy"):
                resolved, _ = runner.query(home, ["resolve", ref["delivery"]])
                expansions += 1
                if resolved.get("reference", {}).get("sha256") == world.files.get(path):
                    usable_versions += 1
        tasks.append({**task, "returned": found, "total": answer.get("total"),
                      "recall": len(relevant) / len(wanted),
                      "first_5_precision": len(set(first) & wanted) / len(first) if first else 0,
                      "first_5_noise": len([p for p in first if p not in wanted]),
                      "duplicate_rows": len(found) - len(set(found)),
                      "scope_correct": scope_correct if relevant else None,
                      "originals_resolvable": usable_originals,
                      "exact_versions_usable": usable_versions,
                      "expansions_to_verify": expansions,
                      "task_success": relevant == wanted and usable_versions == len(wanted) and scope_correct,
                      "query_seconds": seconds, "index_generation": answer.get("index", {}).get("generation")})

    # Existing API may refuse outline: record unsupported, do not replace it with
    # a benchmark-only parser. Baseline and candidate use their real command.
    report_hit = next((r for r in rows if str(Path(r["reference"]["path"]).relative_to(home)) == report_path), None)
    outline = {"supported": False}
    if report_hit:
        answer, seconds = runner.query(home, ["outline", report_hit["reference"]["delivery"]])
        outline = {"supported": "error" not in answer and "invalid_json" not in answer,
                   "answer": answer, "seconds": seconds}

    # Freshness is evidence of the last scan, not a positive claim about an
    # unindexed new source. Then index a malformed log and inspect negative scope.
    late = world.put("FieldLab", "reports/late-note.md", "# New observation\n")
    world.log("FieldLab", "Deliver the late note", "[Note](reports/late-note.md)", suffix="late")
    stale, _ = runner.query(home, ["find", "late-note"])
    malformed = home / ".claude/projects/broken/session.jsonl"
    malformed.parent.mkdir(parents=True)
    malformed.write_text('{"type":')
    reindex, reindex_seconds = runner.call(args.indexer, ["--home", str(home), "--now", stamp(world.clock + timedelta(seconds=20))])
    negative, _ = runner.query(home, ["find", "a-term-not-in-this-corpus"])
    latest, _ = runner.query(home, ["find", "late-note"])

    output = {
        "schema": 1, "label": args.label, "revision": args.revision, "variant": args.variant,
        "executables": {"gleaner_sha256": digest(Path(args.cli).read_bytes()),
                        "gleaner_index_sha256": digest(Path(args.indexer).read_bytes())},
        "method": "Actual gleaner-index and Catalog-backed gleaner commands; no alternative retriever",
        "corpus": {"files": len(world.files), "logs": len(world.logs) + 1, "scale_members": args.scale,
                   "ground_truth": "Task-specific wanted paths; helpers are relevant evidence but not requested outputs",
                   "ambiguities": [t["id"] for t in world.tasks if t["note"]]},
        "capture": {"wanted": len(world.delivered), "found": len(capture),
                    "coverage": len(capture) / len(world.delivered), "missing": sorted(world.delivered - capture),
                    "enumeration_truncated": all_results.get("truncated"),
                    "unsupported_pattern_rows": sorted(p for p in paths if "*" in p or "{" in p)},
        "tasks": tasks, "outline": outline,
        "freshness": {"stale_query_total": stale.get("total"), "stale_index": stale.get("index"),
                      "partial_negative_index": negative.get("index"), "partial_negative_total": negative.get("total"),
                      "new_log_found_after_reindex": any(Path(r["reference"]["path"]) == home / late for r in latest.get("results", []))},
        "resources": {"index_seconds": index_seconds, "reindex_seconds": reindex_seconds,
                      "query_seconds": [t["query_seconds"] for t in tasks],
                      "peak_rss": None, "peak_rss_note": "Not measured in this convergence checkpoint; requires a separate workload/resource experiment"},
        "index": index, "reindex": reindex, "commands": runner.calls,
        "limits": ["No Finder/user comparison", "No semantic authority/supersession inference",
                   "First 5 precision differs from exhaustive recall", "Folder members may be listed but lack captured bytes in read-only Catalog",
                   "Synthetic workloads only; native Mac validation separate"],
    }
    encoded = json.dumps(output, indent=2).replace(str(home), "{synthetic_home}")
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    Path(args.output).write_text(encoded + "\n")
    print(json.dumps({"output": args.output, "capture": output["capture"],
                      "tasks_succeeded": sum(t["task_success"] for t in tasks), "tasks": len(tasks),
                      "index_seconds": index_seconds}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", required=True)
    parser.add_argument("--indexer", required=True)
    parser.add_argument("--runner", default="", help="Trusted argv prefix, e.g. docker exec gleaner-swift")
    parser.add_argument("--home", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--variant", choices=["original", "renamed", "irrelevant", "duplicated"], default="original")
    parser.add_argument("--scale", type=int, default=0)
    evaluate(parser.parse_args())
