#!/usr/bin/env python3
"""Run the opt-in development workload after building, recording child peak RSS.

Run inside the documented unprivileged Swift container, from the repository root.
The workload records its own index/load/query times. This wrapper measures the
whole skip-build SwiftPM/test invocation; RSS is a child-process maximum, not a
sum of all concurrent processes and not a per-query memory measurement.
"""
import json
import os
from pathlib import Path
import resource
import subprocess
import sys
import time

root = Path(__file__).resolve().parents[3]
destination = root / "docs/retrieval-core/cycle2"
command = ["swift", "test", "--skip-build", "--filter", "DevelopmentMeasurements"]
environment = dict(os.environ, GLEANER_CYCLE2_MEASURE="1", GLEANER_CYCLE2_RESULTS_DIR=str(destination))
started = time.monotonic()
result = subprocess.run(command, cwd=root, env=environment)
usage = resource.getrusage(resource.RUSAGE_CHILDREN)
record = {
    "command": command,
    "exit_code": result.returncode,
    "elapsed_seconds": time.monotonic() - started,
    "child_max_rss_kib": usage.ru_maxrss / 1024 if sys.platform == "darwin" else usage.ru_maxrss,
    "child_user_cpu_seconds": usage.ru_utime,
    "child_system_cpu_seconds": usage.ru_stime,
    "platform": sys.platform,
    "boundary": "Whole skip-build SwiftPM/test invocation; child maximum RSS, not summed process memory or per-query memory. Debug build, no concurrent experiment runs.",
}
(destination / "development-resource-results.json").write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
raise SystemExit(result.returncode)
