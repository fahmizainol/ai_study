"""The Wash appliance move is legal only on the matching form."""
import copy
import json
import sys
import unittest
from pathlib import Path

STUDY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(STUDY / "tools"))
from validate_team import validate


class RotomWashSetTest(unittest.TestCase):
    def setUp(self):
        teams = json.loads((STUDY / "generated/teams_trainers.json").read_text())
        self.team = copy.deepcopy(next(t for t in teams if t["id"] == "boss_JEREMIAH_Jeremiah_map016"))

    def test_wash_set_is_legal(self):
        errors, _ = validate([self.team])
        self.assertEqual([], errors)
        rotom = self.team["mons"][0]
        self.assertEqual(2, rotom["form"])
        self.assertIn("HYDROPUMP", rotom["moves"])

    def test_base_rotom_cannot_use_hydro_pump(self):
        self.team["mons"][0]["form"] = 0
        errors, _ = validate([self.team])
        self.assertTrue(any("can't learn HYDROPUMP" in e for e in errors), errors)

    def test_other_rotom_form_cannot_use_hydro_pump(self):
        self.team["mons"][0]["form"] = 1
        errors, _ = validate([self.team])
        self.assertTrue(any("can't learn HYDROPUMP" in e for e in errors), errors)


if __name__ == "__main__":
    unittest.main()
