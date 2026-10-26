#!/usr/bin/env python3
"""Sequential on-device FM evaluation with incremental results and a bounded run budget."""
import argparse
from collections import Counter
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time

from benchmark import INSTRUCTIONS, percentile
from corpus import HERE, validate


def measure(case, version, timeout):
    request = {"composition_version": version, "context_before": case["context"], "candidates": case["candidates"]}
    baseline = case["candidates"][0]["id"]
    row = {"id": case["id"], "category": case["category"], "expected": case["expected_id"], "baseline": baseline}
    start = time.monotonic()
    command = ["/usr/bin/time", "-l", "fm", "respond", "--model", "system", "--no-stream", "--greedy",
               "--schema", str(HERE / "selection-schema.json"), "--instructions", INSTRUCTIONS,
               json.dumps(request, ensure_ascii=False)]
    process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        stdout, stderr = process.communicate(timeout=timeout)
        row.update(timeout=False, returncode=process.returncode)
        rss = re.search(r"(\d+)\s+maximum resident set size", stderr)
        row["cli_max_rss_bytes"] = int(rss.group(1)) if rss else None
        try:
            output = json.loads(stdout)
            selected = output.get("selected_id")
            row["valid"] = (
                process.returncode == 0 and type(selected) is int
                and selected in {candidate["id"] for candidate in case["candidates"]}
                and type(output.get("composition_version")) is int and output["composition_version"] == version
            )
            row["selected"] = selected if row["valid"] else None
        except (ValueError, TypeError, AttributeError):
            row.update(valid=False, selected=None)
        if process.returncode:
            row["error"] = stderr[:1000]
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.communicate()
        row.update(valid=False, selected=None, timeout=True)
    row["latency_ms"] = round((time.monotonic() - start) * 1000, 3)
    row["effective_selected"] = row["selected"] if row["valid"] else baseline
    return row


def summarize(rows):
    count = len(rows)
    if not count:
        return {"count": 0}
    latencies = [row["latency_ms"] for row in rows]
    baseline_correct = [row for row in rows if row["expected"] == row["baseline"]]
    harmful = sum(row["effective_selected"] != row["expected"] for row in baseline_correct)
    return {
        "count": count,
        "candidate_recall_by_construction": 1.0,
        "baseline_top1_accuracy": len(baseline_correct) / count,
        "effective_top1_accuracy": sum(row["effective_selected"] == row["expected"] for row in rows) / count,
        "baseline_correct_count": len(baseline_correct), "harmful_rerank_count": harmful,
        "harmful_rerank_rate_among_baseline_correct": harmful / len(baseline_correct) if baseline_correct else None,
        "invalid_output_rate": sum(not row["valid"] and not row["timeout"] for row in rows) / count,
        "timeout_rate": sum(row["timeout"] for row in rows) / count,
        "exceeds_150ms_rate": sum(row["latency_ms"] > 150 for row in rows) / count,
        "p50_ms": percentile(latencies, 50), "p95_ms": percentile(latencies, 95), "p99_ms": percentile(latencies, 99),
        "first_request_ms": latencies[0],
        "max_cli_rss_bytes": max((row.get("cli_max_rss_bytes") or 0) for row in rows),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=HERE / "corpus-results.json")
    parser.add_argument("--timeout", type=float, default=10)
    parser.add_argument("--budget-seconds", type=float, default=600)
    args = parser.parse_args()
    if args.timeout <= 0 or args.budget_seconds <= 0:
        parser.error("Timeout and run budget must be positive")
    if args.output.exists():
        parser.error("Output already exists; choose a new output path to preserve prior evidence")
    corpus_bytes = (HERE / "corpus-500.json").read_bytes()
    cases = json.loads(corpus_bytes)
    validation = validate(cases)
    status = subprocess.run(["fm", "license", "--status"], capture_output=True, text=True, check=True)
    if "Agreed to license" not in status.stdout:
        raise SystemExit("FM license consent not confirmed. No inference was attempted.")
    availability = subprocess.run(["fm", "available"], capture_output=True, text=True, check=True)
    if "System model available" not in availability.stdout:
        raise SystemExit("On-device model is unavailable. No cloud fallback is allowed.")
    started = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat()
    clock_start = time.monotonic()
    rows = []
    stop_reason = "complete"
    consecutive_failures = 0

    def save():
        output = {
            "timestamp_started": started,
            "timestamp_saved": datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
            "model": "system", "model_available": True,
            "corpus_sha256": hashlib.sha256(corpus_bytes).hexdigest(), "corpus_validation": validation,
            "timeout_seconds": args.timeout, "budget_seconds": args.budget_seconds,
            "measured_count": len(rows), "unmeasured_count": len(cases) - len(rows),
            "stop_reason": "in_progress" if stop_reason == "complete" and len(rows) < len(cases) else stop_reason,
            "elapsed_seconds": round(time.monotonic() - clock_start, 3),
            "summary": summarize(rows),
            "by_category": {category: summarize([row for row in rows if row["category"] == category]) for category in Counter(case["category"] for case in cases)},
            "caveats": "500 template variants from 100 synthetic seeds, not independent natural samples. No engine candidates or scores. Recall guaranteed by construction. Correlated variants require grouped train/test separation. CLI latency includes process startup; RSS excludes model service. First request is not verified cold start. Background load was not isolated.",
            "results": rows,
        }
        temp = args.output.with_suffix(args.output.suffix + ".partial")
        temp.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n")
        temp.replace(args.output)

    for index, case in enumerate(cases, 1):
        remaining = args.budget_seconds - (time.monotonic() - clock_start)
        if remaining <= 0:
            stop_reason = "time_budget_reached"
            break
        row = measure(case, index, min(args.timeout, remaining))
        rows.append(row)
        consecutive_failures = 0 if row["valid"] else consecutive_failures + 1
        if consecutive_failures >= 5:
            stop_reason = "five_consecutive_invalid_or_timeout_results"
        save()
        if index % 25 == 0 or stop_reason != "complete":
            print(json.dumps({"measured": index, "elapsed_seconds": round(time.monotonic() - clock_start, 2), "summary": summarize(rows)}, ensure_ascii=False), flush=True)
        if stop_reason != "complete":
            break
    save()
    print(json.dumps({"stop_reason": stop_reason, "measured_count": len(rows), "summary": summarize(rows)}, indent=2), flush=True)

if __name__ == "__main__":
    main()
