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


class ShadowComparisonTest(unittest.TestCase):
    """How a shadow run decides two AIs picked the same thing.

    The rule has one owner (tools/shadow_check.py) because the readout and the
    statistics both consume it; if they disagreed about what counts as a
    disagreement, nothing downstream would be trustworthy.
    """

    @classmethod
    def setUpClass(cls):
        import shadow_check
        cls.mod = shadow_check

    def test_same_move_agrees_on_numeric_id_not_name(self):
        # The host choice carries a numeric id; only the portable side has the name.
        portable = {"type": "move", "numeric_move_id": 418, "move_id": "BULLETPUNCH"}
        self.assertTrue(self.mod.same_choice(portable, {"type": "move",
                                                        "numeric_move_id": 418}))
        self.assertFalse(self.mod.same_choice(portable, {"type": "move",
                                                         "numeric_move_id": 97}))

    def test_different_kinds_disagree(self):
        self.assertFalse(self.mod.same_choice(
            {"type": "switch", "slot": 2}, {"type": "move", "numeric_move_id": 97}))

    def test_switches_compare_on_party_slot(self):
        self.assertTrue(self.mod.same_choice({"type": "switch", "slot": 3},
                                             {"type": "switch", "slot": 3}))
        self.assertFalse(self.mod.same_choice({"type": "switch", "slot": 3},
                                              {"type": "switch", "slot": 1}))

    # An unscorable pair must not be counted either way: silently calling it agreement
    # would understate disagreement, and disagreement would overstate it.
    def test_unscorable_pairs_are_none_not_false(self):
        self.assertIsNone(self.mod.same_choice(None, {"type": "move"}))
        self.assertIsNone(self.mod.same_choice({"type": "move"}, None))
        self.assertIsNone(self.mod.same_choice({"type": "move", "numeric_move_id": 1},
                                               {"type": "unregistered", "code": 9}))
        self.assertIsNone(self.mod.same_choice({"type": "move"},
                                               {"type": "move", "numeric_move_id": 1}))

    # Two roster sets name their matchups identically (team1_vs_team2 in both
    # gen6ou_a and gen6ou_b), so a key without the set silently collapses them and
    # halves the sample -- which is exactly what it did on the first full run.
    def test_records_from_two_roster_sets_do_not_collide(self):
        rows = [
            {"mode": "stock", "teams": "gen6ou_a", "id": "t1_vs_t2", "seed": 1},
            {"mode": "stock", "teams": "gen6ou_b", "id": "t1_vs_t2", "seed": 1},
            {"mode": "shadow", "teams": "gen6ou_a", "id": "t1_vs_t2", "seed": 1},
            {"mode": "shadow", "teams": "gen6ou_b", "id": "t1_vs_t2", "seed": 1},
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "run.ndjson"
            path.write_text("\n".join(json.dumps(r) for r in rows), encoding="utf-8")
            stock, shadow = self.mod.load(str(path))
        self.assertEqual(2, len(stock))
        self.assertEqual(2, len(shadow))

    def test_divergent_outcomes_are_reported_as_not_free(self):
        stock = {("s", "m", 1): {"decision": 2, "turns": 22}}
        shadow = {("s", "m", 1): {"decision": 2, "turns": 14}}
        paired, bad = self.mod.check_free(stock, shadow)
        self.assertEqual(1, paired)
        self.assertEqual(1, len(bad))

    def test_identical_outcomes_are_reported_as_free(self):
        stock = {("s", "m", 1): {"decision": 2, "turns": 22}}
        shadow = {("s", "m", 1): {"decision": 2, "turns": 22}}
        paired, bad = self.mod.check_free(stock, shadow)
        self.assertEqual((1, []), (paired, bad))


class RenderSelectionTest(unittest.TestCase):
    """Addressing one battle in a tier trace.

    A matchup id and seed name four records, not one: both roster sets call their
    matchups team1_vs_team2, and every battle is recorded once per mode. Same
    collision that halved the shadow sample -- here it made the renderer print four
    battles when asked for one.
    """

    @classmethod
    def setUpClass(cls):
        import render_realidea_battle
        cls.mod = render_realidea_battle

    ROWS = [
        {"teams": "gen6ou_a", "mode": "portable", "id": "t1_vs_t2", "seed": 1},
        {"teams": "gen6ou_a", "mode": "shadow", "id": "t1_vs_t2", "seed": 1},
        {"teams": "gen6ou_b", "mode": "portable", "id": "t1_vs_t2", "seed": 1},
        {"teams": "gen6ou_b", "mode": "shadow", "id": "t1_vs_t2", "seed": 1},
    ]

    def test_teams_and_mode_together_name_one_record(self):
        picked = self.mod.select(self.ROWS, teams="gen6ou_a", mode="shadow")
        self.assertEqual(1, len(picked))
        self.assertEqual("gen6ou_a", picked[0]["teams"])
        self.assertEqual("shadow", picked[0]["mode"])

    def test_either_filter_alone_still_narrows(self):
        self.assertEqual(2, len(self.mod.select(self.ROWS, teams="gen6ou_b")))
        self.assertEqual(2, len(self.mod.select(self.ROWS, mode="shadow")))

    def test_no_filter_keeps_everything(self):
        self.assertEqual(4, len(self.mod.select(self.ROWS)))

    def test_flag_reads_its_value_and_ignores_others(self):
        argv = ["run.ndjson", "--teams=gen6ou_b", "--mode=shadow", "--list"]
        self.assertEqual("gen6ou_b", self.mod.flag(argv, "teams"))
        self.assertEqual("shadow", self.mod.flag(argv, "mode"))
        self.assertIsNone(self.mod.flag(argv, "format"))


if __name__ == "__main__":
    unittest.main()
