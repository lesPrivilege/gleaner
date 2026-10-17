#!/usr/bin/env python3
"""Safe fictional fixture checks, not a model/retrieval benchmark or Gleaner code.

Run: python synthetic/probe.py --out run-001
Only writes a new directory immediately below this script's directory.
No network, model, private log, credential, repository or external tool access.
"""
import argparse
import hashlib
import json
import platform
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path


def canonical(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True,
                       separators=(",", ":")) + "\n").encode("utf-8")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def put(root, path, value):
    target = root / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(value if isinstance(value, bytes) else canonical(value))


def json_rows(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line]


def inventory(root):
    return [{"path": p.relative_to(root).as_posix(), "size": p.stat().st_size,
             "sha256": digest(p.read_bytes())}
            for p in sorted(root.rglob("*")) if p.is_file()]


CONFIG = {"extractor": "fictional-probe-1", "timezone": "UTC",
          "normalization": "raw bytes retained; JSON keys sorted; IDs not coalesced",
          "relation_rule": "source-explicit only", "summaries": False}


def derive(root, reverse=False):
    """A minimal projection for information tests, not a proposed product schema."""
    objects = json_rows(root / "raw/objects.jsonl")
    if reverse:
        objects.reverse()
    objects = sorted(objects, key=lambda x: (x["project"], x["object_id"]))
    # Preserve identities even when payload hashes match.
    approvals_path = root / "state/approvals.jsonl"
    annotation_path = root / "state/annotations.jsonl"
    return {"objects": objects,
            "approvals": json_rows(approvals_path) if approvals_path.exists() else [],
            "annotations": json_rows(annotation_path) if annotation_path.exists() else [],
            "snapshots": sorted(p.relative_to(root).as_posix()
                                for p in (root / "state/snapshots").glob("*")
                                if p.is_file()),
            "scope": json.loads((root / "scope.json").read_text())}


def input_identity(root, config=CONFIG):
    return digest(canonical({"manifest": inventory(root), "config": config}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="run-001")
    args = parser.parse_args()
    if Path(args.out).name != args.out or args.out in {".", "..", ""}:
        parser.error("--out must be one new directory name")
    parent = Path(__file__).resolve().parent
    run = parent / args.out
    run.mkdir(exist_ok=False)
    started = datetime.now(timezone.utc).isoformat()
    c0 = run / "fixture-c0"
    c1 = run / "fixture-c1"
    common = b"# Fictional template\nNo approval is implied.\n"
    objects = [
        {"object_id": "n-01", "project": "north", "version": "v1",
         "path": "payloads/north/template.txt", "sha256": digest(common)},
        {"object_id": "s-01", "project": "south", "version": "v1",
         "path": "payloads/south/template.txt", "sha256": digest(common)},
    ]
    put(c0, "raw/objects.jsonl", b"".join(canonical(o) for o in objects))
    events = [
        {"id": "r1", "kind": "approval_requested", "object_id": "n-01",
         "version": "v2", "purpose": "publication"},
        {"id": "w1", "kind": "write_requested", "path": "budget.txt",
         "proposed_value": 600, "result_id": None},
        {"id": "w2", "kind": "write_observed", "path": "budget.txt",
         "value": 900, "observed_at": "2026-01-01T10:05:00Z"},
    ]
    put(c0, "raw/events.jsonl", b"".join(canonical(e) for e in events))
    put(c0, "payloads/north/template.txt", common)
    put(c0, "payloads/south/template.txt", common)
    put(c0, "payloads/north/budget.txt", b"budget: 900\n")
    put(c0, "scope.json", {"snapshot": "synthetic-epoch-1",
        "source_units": ["north-session", "south-session", "unavailable-tail"],
        "covered_units": ["north-session", "south-session"],
        "excluded": [{"id": "unavailable-tail", "reason": "not observed"}],
        "closed_world": False})
    shutil.copytree(c0, c1)
    approval = {"id": "a1", "actor": "Mira", "authority_policy": "fixture-owner",
                "object_id": "n-01", "version": "v1", "purpose": "internal-review",
                "decision": "approved", "event_at": "2026-01-01T11:00:00Z"}
    annotation = {"id": "u1", "object_id": "n-01", "version": "v1",
                  "alias": "Board packet", "collections": ["Review", "Archive"]}
    put(c1, "state/approvals.jsonl", canonical(approval))
    put(c1, "state/annotations.jsonl", canonical(annotation))
    put(c1, "state/snapshots/budget-v0.txt", b"budget: 700\n")
    put(c1, "state/capture-observations.jsonl", canonical({
        "id": "c1", "path": "state/snapshots/budget-v0.txt",
        "sha256": digest(b"budget: 700\n"), "observed_at": "2026-01-01T10:04:59Z",
        "next_operation": "w2", "intervening_writes": []}))

    checks = []
    def check(name, passed, evidence, limit):
        checks.append({"name": name, "passed": bool(passed),
                       "evidence": evidence, "limit": limit})

    d0, d1 = derive(c0), derive(c1)
    check("same_hash_distinct_project_objects",
          objects[0]["sha256"] == objects[1]["sha256"] and len(d0["objects"]) == 2
          and d0["objects"][0]["object_id"] != d0["objects"][1]["object_id"],
          {"digest": objects[0]["sha256"], "objects": [o["object_id"] for o in objects]},
          "Byte equality does not establish logical identity or shared approval.")
    check("equal_information_state_in_c1",
          d1["approvals"] == json_rows(c1 / "state/approvals.jsonl")
          and (c1 / d1["snapshots"][0]).read_bytes() == b"budget: 700\n",
          {"raw_state": "fixture-c1/state", "catalog_approval_count": len(d1["approvals"])},
          "Both representations contain the same supplied state; no retrieval speed was measured.")
    check("c0_has_no_supplied_decision_or_snapshot",
          not d0["approvals"] and not d0["snapshots"] and not (c0 / "state").exists(),
          {"approvals": len(d0["approvals"]), "snapshots": len(d0["snapshots"])},
          "Absence from the visible fixture does not prove no real-world event occurred.")
    check("requests_do_not_supply_v2_approval_or_write_result",
          all(a["version"] != "v2" for a in d1["approvals"])
          and events[1]["result_id"] is None and events[1]["proposed_value"] != 700,
          {"approval_request": "r1", "unobserved_write": "w1"},
          "The 600 proposal cannot establish the historical 700 payload or a successful write.")
    # Two distinct hidden histories have exactly the same observable C0 inputs.
    world_a = {"hidden_owner_approved": True, "visible_input_hash": input_identity(c0)}
    world_b = {"hidden_owner_approved": False, "visible_input_hash": input_identity(c0)}
    check("indistinguishable_visible_histories",
          world_a["hidden_owner_approved"] != world_b["hidden_owner_approved"]
          and world_a["visible_input_hash"] == world_b["visible_input_hash"],
          {"visible_input_hash": world_a["visible_input_hash"]},
          "A method using only these inputs cannot warrant the differing hidden approval bit.")
    check("partial_coverage_cannot_support_global_absence",
          len(d0["scope"]["covered_units"]) < len(d0["scope"]["source_units"])
          and not d0["scope"]["closed_world"], d0["scope"],
          "A coverage contract can expose a gap; no model fallback behavior was tested.")
    check("fixed_input_rebuild_stable_under_enumeration_change",
          canonical(derive(c1)) == canonical(derive(c1, reverse=True)),
          {"input_identity": input_identity(c1), "canonical_output_hash": digest(canonical(d1))},
          "Only this deterministic probe projection/configuration was checked.")

    # A separate epoch changes bytes at an existing path, without touching the frozen inputs.
    drift = run / "fixture-drift"
    shutil.copytree(c1, drift)
    put(drift, "payloads/north/template.txt", b"Unrelated reused path\n")
    old_pointer_hash = objects[0]["sha256"]
    current_hash = digest((drift / objects[0]["path"]).read_bytes())
    check("source_drift_and_stale_pointer_are_detectable",
          input_identity(c1) != input_identity(drift) and old_pointer_hash != current_hash,
          {"old_input": input_identity(c1), "new_input": input_identity(drift),
           "expected_payload": old_pointer_hash, "observed_payload": current_hash},
          "This is a declared source change, not nondeterministic rebuilding.")
    changed_config = {**CONFIG, "extractor": "fictional-probe-2"}
    check("extraction_configuration_is_part_of_input_identity",
          input_identity(c1) != input_identity(c1, changed_config),
          {"v1": input_identity(c1), "v2": input_identity(c1, changed_config)},
          "Identity changes do not prove semantic correctness of either extractor.")

    derived = run / "derived"
    derived.mkdir()
    put(derived, "catalog.json", d1)
    before = inventory(c1)
    # Explicit narrow deletion: only the derived folder created immediately above.
    shutil.rmtree(derived)
    derived.mkdir()
    put(derived, "catalog.json", derive(c1, reverse=True))
    rebuilt = json.loads((derived / "catalog.json").read_text())
    check("derived_reset_preserves_authored_state_and_capture_reachability",
          before == inventory(c1) and rebuilt["annotations"] == [annotation]
          and (c1 / rebuilt["snapshots"][0]).exists(),
          {"annotation_id": "u1", "reachable_capture": rebuilt["snapshots"][0]},
          "This does not test Gleaner's registry removal, migrations or real retention policy.")

    put(run, "config.json", CONFIG)
    put(run, "fixture-manifests.json", {"c0": inventory(c0), "c1": inventory(c1),
                                         "drift": inventory(drift)})
    result = {"kind": "synthetic_fixture_contract_checks_not_model_benchmark",
              "started_utc": started, "python": platform.python_version(),
              "command": f"python synthetic/probe.py --out {args.out}",
              "script_sha256": digest(Path(__file__).read_bytes()),
              "config_sha256": digest(canonical(CONFIG)),
              "checks_passed": sum(c["passed"] for c in checks),
              "checks_total": len(checks), "checks": checks,
              "model_trials": 0, "retrieval_strategies_compared": 0,
              "private_sources_read": 0}
    put(run, "results.json", result)
    print(json.dumps({k: result[k] for k in ["kind", "checks_passed", "checks_total",
                                           "script_sha256", "model_trials"]}, indent=2))
    print("Evidence:", run / "results.json")
    return 0 if all(c["passed"] for c in checks) else 1


if __name__ == "__main__":
    sys.exit(main())
