import copy
import hashlib
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

from benchmark_corpus import measure, summarize
from corpus import generate, validate

HERE = Path(__file__).resolve().parent


class CorpusTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cases = json.loads((HERE / "corpus-500.json").read_text())
        cls.seeds = json.loads((HERE / "seed-pairs.json").read_text())

    def test_generated_corpus_matches_checked_in_fixture(self):
        self.assertEqual(generate(self.seeds), self.cases)
        self.assertEqual(validate(self.cases)["cases"], 500)

    def test_every_category_has_100_cases_and_20_seed_groups(self):
        for category in {case["category"] for case in self.cases}:
            rows = [case for case in self.cases if case["category"] == category]
            self.assertEqual(len(rows), 100)
            self.assertEqual(len({row["seed_id"] for row in rows}), 20)

    def test_rejects_duplicate_case_id(self):
        invalid = copy.deepcopy(self.cases)
        invalid[1]["id"] = invalid[0]["id"]
        with self.assertRaises(ValueError):
            validate(invalid)

    def test_rejects_duplicate_candidate_id(self):
        invalid = copy.deepcopy(self.cases)
        invalid[0]["candidates"][1]["id"] = invalid[0]["candidates"][0]["id"]
        with self.assertRaises(ValueError):
            validate(invalid)

    def test_rejects_missing_or_mismatched_answer(self):
        for key, value in [("expected_id", 99), ("answer", "答案不在候選中")]:
            invalid = copy.deepcopy(self.cases)
            invalid[0][key] = value
            with self.assertRaises(ValueError):
                validate(invalid)

    def test_rejects_incorrect_category_count(self):
        invalid = copy.deepcopy(self.cases)
        invalid[0]["category"] = "mixed"
        with self.assertRaises(ValueError):
            validate(invalid)

    def test_rejects_duplicate_template_for_seed(self):
        invalid = copy.deepcopy(self.cases)
        invalid[1]["template_id"] = invalid[0]["template_id"]
        with self.assertRaises(ValueError):
            validate(invalid)

    def test_rejects_missing_provenance(self):
        invalid = copy.deepcopy(self.cases)
        invalid[0]["provenance"] = ""
        with self.assertRaises(ValueError):
            validate(invalid)

    def test_saved_results_cover_corpus_and_match_metrics(self):
        report = json.loads((HERE / "corpus-results.json").read_text())
        self.assertEqual(report["corpus_sha256"], hashlib.sha256((HERE / "corpus-500.json").read_bytes()).hexdigest())
        self.assertEqual(report["measured_count"], 500)
        self.assertEqual(report["unmeasured_count"], 0)
        self.assertEqual(report["stop_reason"], "complete")
        self.assertEqual(report["summary"], summarize(report["results"]))
        self.assertEqual({row["id"] for row in report["results"]}, {row["id"] for row in self.cases})
        cases = {case["id"]: case for case in self.cases}
        for row in report["results"]:
            case = cases[row["id"]]
            self.assertEqual(row["category"], case["category"])
            self.assertEqual(row["expected"], case["expected_id"])
            if row["valid"]:
                self.assertIn(row["selected"], [candidate["id"] for candidate in case["candidates"]])
        for category, summary in report["by_category"].items():
            self.assertEqual(summary, summarize([row for row in report["results"] if row["category"] == category]))

    def test_preserve_cases_start_with_correct_literal(self):
        for case in self.cases:
            if case["category"] == "preserve":
                self.assertEqual(case["expected_id"], case["candidates"][0]["id"])
                self.assertIn(case["answer"], case["context"])


class BenchmarkTests(unittest.TestCase):
    case = {
        "id": "example", "category": "mixed", "context": "請讀取 JSON", "expected_id": 8,
        "candidates": [{"id": 5, "text": "擋案"}, {"id": 8, "text": "檔案"}],
    }

    def test_accepts_existing_noncontiguous_id(self):
        with patch("benchmark_corpus.subprocess.Popen") as popen:
            popen.return_value.communicate.return_value = ('{"composition_version":42,"selected_id":8}', '')
            popen.return_value.returncode = 0
            row = measure(self.case, 42, 1)
            self.assertTrue(row["valid"])
            self.assertEqual(row["effective_selected"], 8)

    def test_rejects_boolean_version_unknown_id_and_invalid_json(self):
        for output in ['{"composition_version":true,"selected_id":8}',
                       '{"composition_version":1,"selected_id":99}', 'not JSON']:
            with patch("benchmark_corpus.subprocess.Popen") as popen:
                popen.return_value.communicate.return_value = (output, '')
                popen.return_value.returncode = 0
                row = measure(self.case, 1, 1)
                self.assertFalse(row["valid"])
                self.assertEqual(row["effective_selected"], 5)

    def test_timeout_terminates_process_group_and_falls_back(self):
        with patch("benchmark_corpus.subprocess.Popen") as popen, patch("benchmark_corpus.os.killpg") as killpg:
            popen.return_value.pid = 12345
            popen.return_value.communicate.side_effect = [subprocess.TimeoutExpired("fm", 1), ("", "")]
            row = measure(self.case, 1, 1)
            self.assertTrue(row["timeout"])
            self.assertFalse(row["valid"])
            self.assertEqual(row["effective_selected"], 5)
            killpg.assert_called_once()

    def test_summary_distinguishes_invalid_timeout_and_harmful_results(self):
        rows = [
            {"expected":0, "baseline":0, "effective_selected":1, "valid":True, "timeout":False, "latency_ms":200},
            {"expected":0, "baseline":0, "effective_selected":0, "valid":False, "timeout":True, "latency_ms":1000},
            {"expected":1, "baseline":0, "effective_selected":0, "valid":False, "timeout":False, "latency_ms":100},
        ]
        result = summarize(rows)
        self.assertEqual(result["harmful_rerank_count"], 1)
        self.assertEqual(result["baseline_correct_count"], 2)
        self.assertEqual(result["harmful_rerank_rate_among_baseline_correct"], 0.5)
        self.assertEqual(result["invalid_output_rate"], 1 / 3)
        self.assertEqual(result["timeout_rate"], 1 / 3)
        self.assertEqual(result["effective_top1_accuracy"], 1 / 3)


if __name__ == "__main__":
    unittest.main()
