#!/usr/bin/env python3
"""Independent synthetic retrieval assessment, frozen before implementation review.

No model, network, shell expansion, real home, or private corpus. Every command calls
the shipping shared core through its real CLI. Labels name logical artifacts, not
the number of files the index happens to return. Finder superiority is not tested.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import subprocess
import tempfile
import time

STAMP = "2030-09-21T12:00:00Z"
LATER = "2030-09-21T13:00:00Z"


class Corpus:
    def __init__(self, root, binaries):
        self.root = root
        self.bin = binaries
        self.project = root / "Workspaces" / "Estuary"
        self.project.mkdir(parents=True)
        self.elapsed = []

    def file(self, name, text="synthetic exhibit\n", project=None):
        path = (project or self.project) / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        os.utime(path, (1789988340, 1789988340))
        return path

    def log(self, request, reply, *, project=None, session="s1", append=False,
            stamp=STAMP, interrupted=False, provider="claude"):
        cwd = str(project or self.project)
        if provider == "claude":
            log = self.root / ".claude/projects/synthetic" / (session + ".jsonl")
            records = [
                {"type": "user", "sessionId": session, "cwd": cwd,
                 "timestamp": stamp, "origin": {"kind": "human"},
                 "message": {"role": "user", "content": request}},
                {"type": "assistant", "sessionId": session, "cwd": cwd,
                 "timestamp": stamp, "message": {"role": "assistant", "model": "synthetic",
                 "content": [{"type": "text", "text": reply}]}},
            ]
            if interrupted:
                records.append({"type": "user", "sessionId": session, "cwd": cwd,
                    "timestamp": stamp, "message": {"role": "user",
                    "content": "[Request interrupted by user]"}})
        else:
            log = self.root / ".codex/sessions/2026/09/21" / ("rollout-" + session + ".jsonl")
            records = [
                {"timestamp": stamp, "type": "session_meta", "payload": {
                    "id": session, "cwd": cwd, "thread_source": "user"}},
                {"timestamp": stamp, "type": "turn_context", "payload": {
                    "turn_id": session, "cwd": cwd, "model": "synthetic"}},
                {"timestamp": stamp, "type": "response_item", "payload": {
                    "type": "message", "role": "user", "content": [{"type": "input_text", "text": request}],
                    "internal_chat_message_metadata_passthrough": {"content_item_kinds": ["user.text"]}}},
                {"timestamp": stamp, "type": "response_item", "payload": {
                    "type": "message", "role": "assistant", "phase": "final_answer",
                    "content": [{"type": "output_text", "text": reply}]}},
            ]
        log.parent.mkdir(parents=True, exist_ok=True)
        with log.open("a" if append else "w") as handle:
            for record in records:
                handle.write(json.dumps(record) + "\n")
        return log

    def command(self, executable, *args, okay=(0,)):
        started = time.perf_counter()
        result = subprocess.run([str(self.bin / executable), *map(str, args), "--home", str(self.root)],
                                capture_output=True, text=True, timeout=60)
        self.elapsed.append((time.perf_counter() - started) * 1000)
        if result.returncode not in okay:
            raise RuntimeError(f"{executable} {args}: {result.returncode}: {result.stderr}")
        return json.loads(result.stdout)

    def index(self, stamp=STAMP):
        return self.command("gleaner-index", "--now", stamp)

    def find(self, terms=(), limit=1000, project=None):
        args = ["find", *(terms or [""]), "--limit", str(limit)]
        if project is not None:
            args += ["--project", str(project)]
        return self.command("gleaner", *args)

    def assess(self, name, wanted, terms, *, project=None, limit=5, all_wanted=None):
        """Capture and task metrics have deliberately separate denominators."""
        wanted = {str(path) for path in wanted}
        all_wanted = {str(path) for path in (all_wanted or wanted)}
        exhaustive = self.find()
        first = self.find(terms, limit=limit, project=project)
        broad = self.find(terms, project=project)
        indexed = {hit["reference"]["path"] for hit in exhaustive["results"]}
        hits = first["results"]
        paths = [hit["reference"]["path"] for hit in hits]
        relevant = [p for p in paths if p in wanted]
        broad_paths = [hit["reference"]["path"] for hit in broad["results"]]
        originals = sum(h["reference"]["availability"]["state"] == "original"
                        for h in hits if h["reference"]["path"] in wanted)
        # Expanded hits are a deterministic analyst effort proxy, not measured human behavior.
        first_rank = next((i + 1 for i, p in enumerate(broad_paths) if p in wanted), None)
        return {
            "name": name,
            "labels": {"wanted_logical_objects": len(wanted), "capture_targets": len(all_wanted),
                       "wanted_paths": sorted(str(Path(p).relative_to(self.root)) for p in wanted),
                       "query": terms, "first_limit": limit, "ambiguous": []},
            "capture_coverage": len(indexed & all_wanted) / len(all_wanted) if all_wanted else None,
            "task_relevant_recall": len(set(broad_paths) & wanted) / len(wanted) if wanted else None,
            "first_actionable_recall": len(set(relevant)) / len(wanted) if wanted else None,
            "first_precision": len(relevant) / len(paths) if paths else 0,
            "noise_count": len(paths) - len(relevant),
            "duplicate_path_count": len(paths) - len(set(paths)),
            "relevant_original_count": originals,
            "wanted_object_on_first_page": bool(relevant),
            "wanted_original_files_on_disk": sum(Path(p).is_file() for p in wanted),
            "task_all_wanted_usable_first_page": wanted.issubset({h["reference"]["path"] for h in hits if h["reference"]["availability"]["state"] in ("original", "saved_copy")}),
            "rank_of_first_wanted_object": first_rank,
            "first_usable_reference_rank": next((i + 1 for i, h in enumerate(hits) if h["reference"]["path"] in wanted and h["reference"]["availability"]["state"] in ("original", "saved_copy")), None),
            "first_paths": [str(Path(p).relative_to(self.root)) for p in paths],
            "query_total": broad["total"],
        }


def run_case(c, kind):
    if kind == "same-reply-selection":
        wanted = c.file("deliveries/salinity-report.md", "# Salinity report\nUse revised sampling interval.\n")
        reply = "Read [the report](deliveries/salinity-report.md).\nSupporting calculation files:\n"
        for i in range(18):
            relative = f"calculation/probe-{i:02}.csv"
            c.file(relative, "station,reading\nA,7\n")
            reply += f"[probe {i}]({relative})\n"
        c.log("Prepare the salinity report and the supporting calculations", reply)
        c.index()
        return c.assess(kind, [wanted], ["Estuary", "salinity", "report"])

    if kind == "directory-not-every-file-is-a-result":
        wanted = [c.file(f"trailbook/maps/walk-{i}.svg", f"<svg>trail {i}</svg>\n") for i in range(1, 7)]
        for i in range(8):
            c.file(f"trailbook/calibration/reading-{i}.csv")
        for path in ["trailbook/node_modules/pkg/readme.md", "trailbook/.cache/tmp.svg"]:
            c.file(path)
        c.log("Assemble a trailbook with maps and calibration appendix", "[Trailbook folder](trailbook/)")
        c.index()
        return c.assess(kind, wanted, ["Estuary", "maps"], all_wanted=wanted)

    if kind in ("range-shorthand", "glob-shorthand"):
        wanted = [c.file(f"exports/plot_{i:02}.svg") for i in range(3, 8)]
        c.file("exports/plot_02.svg")
        c.file("exports/plot_08.svg")
        if kind == "range-shorthand":
            reply = "Review `exports/plot_03–07.svg`."
        else:
            wanted += [c.project / "exports/plot_02.svg", c.project / "exports/plot_08.svg"]
            c.file("other/plot_09.svg")
            reply = "Review `exports/plot_*.svg`."
        c.log("Prepare plot panels for the exhibition", reply, provider="codex")
        c.index()
        return c.assess(kind, wanted, ["Estuary", "plot"], limit=10)

    if kind == "workspace-prefixed-relative":
        wanted = c.file("delivery/botanical-atlas.pdf")
        c.log("Deliver the botanical atlas", "[Atlas](Estuary/delivery/botanical-atlas.pdf)")
        c.index()
        return c.assess(kind, [wanted], ["atlas"])

    if kind == "repeated-section-identifiers":
        wanted = c.file("board/harbor-review.md", "# Harbor review\n\n## F7 — Tide gate\nThe gate needs replacement. No ruling has been communicated.\n")
        c.file("board/quarry-review.md", "# Quarry review\n\n## F7 — Road width\nIncrease the turning radius.\n")
        c.log("Provide the two site assessments", "[Harbor](board/harbor-review.md) and [Quarry](board/quarry-review.md).")
        c.index()
        result = c.assess(kind, [wanted], ["Harbor", "F7"])
        result["labels"]["section"] = {"id": "F7", "report": "board/harbor-review.md",
            "state": "finding only; no communicated ruling", "expected_content": "gate needs replacement"}
        reports = c.find()["results"]
        harbor = next(h["reference"] for h in reports if h["reference"]["path"] == str(wanted))
        quarry = next(h["reference"] for h in reports if h["reference"]["name"] == "quarry-review.md")
        outline = c.command("gleaner", "outline", harbor["delivery"], "F7", okay=(0, 1, 2))
        result["progressive_sections_supported"] = "sections" in outline
        if "sections" in outline:
            section = outline["sections"][0]
            read = c.command("gleaner", "section", harbor["delivery"], section["id"])
            other = c.command("gleaner", "outline", quarry["delivery"], "F7")
            wrong = c.command("gleaner", "section", quarry["delivery"], section["id"], okay=(0, 1, 2))
            result["progressive_section_correct"] = "gate needs replacement" in read["text"] and "Road width" not in read["text"]
            result["section_ids_scoped_to_report"] = section["id"] != other["sections"][0]["id"]
            result["cross_report_section_refused"] = wrong.get("error", {}).get("kind") == "section_not_found"
            result["progressive_expansions_after_report_selection"] = 2
        return result

    if kind == "version-exactness":
        wanted = c.file("policy/inspection.md", "# Salt survey\nObserve before opening.\n")
        expected = hashlib.sha256(wanted.read_bytes()).hexdigest()
        c.log("Publish the salt survey inspection procedure", "[Procedure](policy/inspection.md)")
        c.index()
        c.file("policy/inspection.md", "# Chloride survey\nKeep the gate shut.\n")
        c.log("Replace it with the chloride survey procedure", "[Procedure](policy/inspection.md)", append=True, stamp=LATER)
        c.index(LATER)
        result = c.assess(kind, [wanted], ["salt", "survey"])
        hit = c.find(["salt", "survey"])["results"][0]["reference"]
        read = c.command("gleaner", "read", hit["delivery"])
        result["correct_version"] = hit["sha256"] == expected and "Observe before opening" in read["text"]
        result["original_available"] = hit["availability"]["state"] == "original"
        result["exact_bytes_available"] = hit["availability"]["state"] in ("original", "saved_copy")
        return result

    if kind == "same-bytes-independent-contexts":
        other = c.root / "Workspaces/Orchard"
        wanted = c.file("forms/permit.md", "Generic permit template\n")
        c.file("forms/permit.md", "Generic permit template\n", project=other)
        c.log("Supply the estuary construction permit", "[Permit](forms/permit.md)", session="estuary")
        c.log("Supply the orchard event permit", "[Permit](forms/permit.md)", project=other, session="orchard")
        c.index()
        result = c.assess(kind, [wanted], ["permit"], project=c.project)
        result["two_contexts_retained"] = c.find(["permit"])["total"] == 2
        result["scope_correct"] = all(h["reference"]["path"] == str(wanted)
                                      for h in c.find(["permit"], project=c.project)["results"])
        return result

    if kind == "moved-original":
        wanted = c.file("minutes/harbor.md", "# Decisions\nInstall a guard rail.\n")
        c.log("Deliver the meeting decisions", "[Minutes](minutes/harbor.md)")
        c.index()
        wanted.rename(wanted.with_name("harbor-archived.md"))
        result = c.assess(kind, [wanted], ["decisions"])
        reference = c.find(["decisions"])["results"][0]["reference"]
        result["availability_correct"] = reference["availability"]["state"] == "saved_copy"
        result["exact_bytes_available"] = "guard rail" in c.command("gleaner", "read", reference["delivery"])["text"]
        return result

    if kind == "aborted-and-observed-not-delivered":
        c.file("drafts/site-memo.md")
        c.file("working/unannounced.txt")
        c.log("Prepare a site memo", "[Draft](drafts/site-memo.md)", interrupted=True)
        c.index()
        found = c.find()
        return {"name": kind, "labels": {"wanted_logical_objects": 0,
            "excluded": ["interrupted assistant text", "unannounced filesystem write"]},
            "false_deliveries": found["total"], "no_inferred_delivery": found["total"] == 0}

    if kind == "partial-versus-negative":
        wanted = c.file("deliveries/catalog.md")
        log = c.log("Publish the museum catalog", "[Catalog](deliveries/catalog.md)")
        c.index()
        with log.open("a") as handle:
            handle.write("{unreadable synthetic record\n")
        c.index(LATER)
        answer = c.find(["nonexistent"])
        return {"name": kind, "negative_result": answer["total"] == 0,
            "partial_is_explicit": answer["index"]["sources"]["claude-code"]["state"] == "read_with_problems",
            "prior_delivery_preserved": str(wanted) in {h["reference"]["path"] for h in c.find()["results"]},
            "scanned_at": answer["index"]["scanned_at"]}

    if kind == "irrelevant-evidence-metamorphism":
        wanted = c.file("plates/heron-poster.svg")
        c.log("Deliver the heron poster", "[Poster](plates/heron-poster.svg)")
        c.index()
        before = c.find(["heron", "poster"], limit=5)
        for i in range(35):
            c.file(f"work/soil-{i:02}.txt")
            c.log("Assemble soil measurements", f"[Data](work/soil-{i:02}.txt)", session=f"soil-{i}", stamp=LATER)
        c.index(LATER)
        after = c.find(["heron", "poster"], limit=5)
        result = c.assess(kind, [wanted], ["heron", "poster"])
        result["unchanged_ranking_and_identity"] = [h["reference"]["delivery"] for h in before["results"]] == [h["reference"]["delivery"] for h in after["results"]]
        return result

    raise ValueError(kind)


CASES = ["same-reply-selection", "directory-not-every-file-is-a-result", "range-shorthand",
         "glob-shorthand", "workspace-prefixed-relative", "repeated-section-identifiers",
         "version-exactness", "same-bytes-independent-contexts", "moved-original",
         "aborted-and-observed-not-delivered", "partial-versus-negative", "irrelevant-evidence-metamorphism"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bin-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--revision", required=True)
    args = parser.parse_args()
    results = []
    for case in CASES:
        with tempfile.TemporaryDirectory(prefix="gleaner-independent-") as folder:
            corpus = Corpus(Path(folder), args.bin_dir.resolve())
            try:
                result = run_case(corpus, case)
            except Exception as error:
                # Sanitize the disposable root; retained reports contain no machine paths.
                result = {"name": case, "runner_error": str(error).replace(folder, "$SYNTHETIC_HOME")}
            result["command_latency_ms"] = {
                "count": len(corpus.elapsed), "total": round(sum(corpus.elapsed), 2),
                "max": round(max(corpus.elapsed, default=0), 2)}
            results.append(result)
    report = {"schema": 1, "revision": args.revision,
        "binary_sha256": {name: hashlib.sha256((args.bin_dir / name).read_bytes()).hexdigest() for name in ("gleaner", "gleaner-index")},
        "fixture_source_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "corpus": "independently authored synthetic museum, ecology, civic engineering and field-work scenarios",
        "method": "real shared-core CLI; one fresh synthetic home per scenario; no tuning from these labels",
        "limitations": ["not a human usability study", "no Finder or agent-library superiority claim",
            "first relevant rank is an analyst effort proxy, not measured human effort",
            "small purposive corpus; no population-level generalization", "subprocess startup included in latency",
            "peak child RSS is process maximum, not whole-run allocation"],
        "child_peak_rss_kib": resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss,
        "cases": results}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "cases": len(results),
                      "runner_errors": sum("runner_error" in result for result in results)}))


if __name__ == "__main__":
    main()
