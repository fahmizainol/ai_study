import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


STUDY = Path(__file__).resolve().parents[1]
CHECK = STUDY / "tools" / "check_scenarios.py"


class CheckScenariosGateTest(unittest.TestCase):
    def run_check(self, corpus, records):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            corpus_path = root / "scenarios.json"
            result_path = root / "results.ndjson"
            corpus_path.write_text(json.dumps(corpus), encoding="utf-8")
            result_path.write_text(
                "".join(json.dumps(record) + "\n" for record in records),
                encoding="utf-8",
            )
            return subprocess.run(
                [sys.executable, str(CHECK), str(corpus_path), str(result_path)],
                text=True,
                capture_output=True,
                check=False,
            )

    def test_missing_result_fails_the_gate(self):
        corpus = [{"id": "missing", "move_ids": {}, "assertions": [["must_choose_any"]]}]
        result = self.run_check(corpus, [])
        self.assertEqual(1, result.returncode)
        self.assertIn("MISS", result.stdout)

    def test_engine_error_fails_the_gate(self):
        corpus = [{"id": "error", "move_ids": {}, "assertions": [["must_choose_any"]]}]
        result = self.run_check(corpus, [{"id": "error", "error": "boom"}])
        self.assertEqual(1, result.returncode)
        self.assertIn("ERR", result.stdout)

    def test_explicit_skip_is_allowed_and_reported(self):
        corpus = [{"id": "field", "move_ids": {}, "assertions": [["must_choose_any"]]}]
        result = self.run_check(
            corpus,
            [{"id": "field", "skipped": True, "reason": "unsupported field"}],
        )
        self.assertEqual(0, result.returncode)
        self.assertIn("SKIP", result.stdout)


if __name__ == "__main__":
    unittest.main()
