import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


STUDY = Path(__file__).resolve().parents[1]
CHECK = STUDY / "tools" / "check_scenarios.py"
sys.path.insert(0, str(STUDY / "tools"))


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


class RealideaHiddenPowerTest(unittest.TestCase):
    """The IV solver in showdown_names.Realidea.

    Realidea derives Hidden Power's type from IV parities over a 17-type pool, one
    wider than the generation these teams were built for, so importing a Showdown
    spread unchanged silently retypes the move -- Hidden Power Ice becomes Dragon on
    the gen6ou Zapdos/Thundurus/Charizard sets. These pin the fix.
    """

    @classmethod
    def setUpClass(cls):
        import showdown_names
        cls.sn = showdown_names
        try:
            cls.game = showdown_names.Realidea()
        except SystemExit as reason:      # game folder absent on this machine
            raise unittest.SkipTest(str(reason))

    def test_showdown_spread_would_mistype_without_the_solver(self):
        """The bug this exists for, stated as a fact about the engine."""
        self.assertEqual("DRAGON", self.game._hp_type([31, 0, 30, 31, 31, 31]))

    def test_every_type_is_reachable_and_verified(self):
        for wanted in self.game.HP_POOL:
            ivs, hptype = self.game.finalise_hidden_power([31] * 6, wanted)
            self.assertIsNone(hptype, "hptype must be consumed; v16 has no such field")
            self.assertEqual(wanted, self.game._hp_type(ivs))

    def test_only_low_bits_move_so_every_iv_keeps_its_band(self):
        start = [31, 0, 30, 31, 31, 31]
        ivs, _ = self.game.finalise_hidden_power(list(start), "ICE")
        self.assertEqual("ICE", self.game._hp_type(ivs))
        for before, after in zip(start, ivs):
            self.assertEqual(before >> 1, after >> 1, f"{before} -> {after} left its band")

    def test_a_spread_that_already_works_is_left_alone(self):
        start = [31, 1, 31, 31, 30, 30]          # gen6ou Volcarona, Hidden Power Ground
        ivs, _ = self.game.finalise_hidden_power(list(start), "GROUND")
        self.assertEqual(start, ivs)

    def test_sets_without_hidden_power_are_untouched(self):
        start = [31, 0, 31, 31, 31, 31]
        self.assertEqual((start, None), self.game.finalise_hidden_power(list(start), None))


class RealideaVetoTest(unittest.TestCase):
    """Names that resolve against machinery Realidea never implemented."""

    @classmethod
    def setUpClass(cls):
        import showdown_names
        try:
            cls.game = showdown_names.Realidea()
        except SystemExit as reason:
            raise unittest.SkipTest(str(reason))

    def test_z_crystal_is_rejected_not_imported_as_an_inert_item(self):
        reason = self.game.veto({"item": "Firium Z", "ability": "Blaze"})
        self.assertIn("Z-move engine", reason or "")

    def test_battle_bond_is_rejected(self):
        reason = self.game.veto({"item": "Life Orb", "ability": "Battle Bond"})
        self.assertIn("Battle Bond", reason or "")

    def test_an_ordinary_set_passes(self):
        self.assertIsNone(self.game.veto({"item": "Leftovers", "ability": "Levitate"}))


if __name__ == "__main__":
    unittest.main()
