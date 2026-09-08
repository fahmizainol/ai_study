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


class PbsByteOrderMarkTest(unittest.TestCase):
    """Realidea's PBS files begin with a UTF-8 BOM, which ate the first row of each.

    `\ufeff` is not whitespace to Python's str.strip(), so `"\ufeff1".strip().isdigit()`
    is False and the id-prefixed first line of every csv was silently skipped -- costing
    MEGAHORN from moves, REPEL from items and STENCH from abilities, with no error
    anywhere. It went unnoticed because the three losses are the FIRST entries and
    nothing else in the study had asked for them; it surfaced when four gen 5 sample
    teams were dropped as "unknown move Megahorn". Both readers now open utf-8-sig.

    These assert the recovered rows specifically, not merely a table size, so a future
    reader rewritten without the BOM handling fails here rather than in a team draw.
    """

    @classmethod
    def setUpClass(cls):
        import showdown_names
        try:
            cls.game = showdown_names.Realidea()
        except SystemExit as reason:
            raise unittest.SkipTest(str(reason))

    def test_the_first_move_in_the_file_resolves(self):
        self.assertIn("MEGAHORN", self.game.moves)
        self.assertEqual(("MEGAHORN", None), self.game.resolve_move("Megahorn"))

    def test_the_first_item_and_ability_in_their_files_resolve(self):
        self.assertIn("REPEL", self.game.items)
        self.assertIn("STENCH", self.game.abilities)

    def test_no_table_key_carries_a_stray_bom(self):
        for label, table in (("moves", self.game.moves), ("items", self.game.items),
                             ("abilities", self.game.abilities),
                             ("species", self.game.species), ("types", self.game.types)):
            for key in table:
                self.assertNotIn("\ufeff", key, f"{label} key {key!r} carries a BOM")


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


class MatrixLinesTest(unittest.TestCase):
    """The 0.6.5 grid: our party down the side, theirs across the top."""

    def setUp(self):
        import importlib

        self.mod = importlib.import_module("render_realidea_battle")

    VIEW = {
        "matrix": {
            "own": [{"slot": 0, "species": "Zapdos", "hp_pct": 62, "active": True},
                    {"slot": 1, "species": "Magnezone", "hp_pct": 100,
                     "active": False}],
            "foe": [{"slot": 0, "species": "Heatran", "hp_pct": 100, "active": True},
                    {"slot": 1, "species": "Gyarados", "hp_pct": 100, "active": False}],
            "verdicts": {"0:0": "L", "0:1": "W", "1:0": "L"},
            "cells": {"0:0": {"out": 62.0, "in": None}},
        }
    }

    def test_matrix_lines_render_rows_by_own_party_and_columns_by_foe(self):
        lines = self.mod.matrix_lines(self.VIEW)
        self.assertEqual(4, len(lines))                 # header, columns, two rows
        self.assertIn("Heatran*", lines[1])
        self.assertIn("Gyarados", lines[1])
        self.assertTrue(lines[2].strip().startswith("Zapdos*"))
        self.assertIn("62%", lines[2])
        self.assertEqual(["L", "W"], lines[2].split()[2:])
        # A pair with no verdict prints as absent, never as a guess.
        self.assertEqual(["L", "-"], lines[3].split()[2:])

    def test_matrix_lines_are_empty_without_a_grid(self):
        self.assertEqual([], self.mod.matrix_lines({}))
        self.assertEqual([], self.mod.matrix_lines({"matrix": {"own": [], "foe": []}}))

    def test_cells_show_both_damage_numbers_and_mark_the_unpriced_one(self):
        lines = self.mod.matrix_lines(self.VIEW, cells=True)
        self.assertIn("L 62%/?", lines[2])


def _foul_play_doc():
    """One exported decision, shaped as FoulPlay.state_for writes it: Golurk facing
    Galvantula from the gen5ru_a roster, Golurk at +0 with a Substitute up."""
    def mon(species, types, stats, ability, item, nature, moves, **extra):
        out = {"species": species, "form": 0, "mega": False, "level": 100, "types": types,
               "hp": stats[0], "maxhp": stats[0], "attack": stats[1], "defense": stats[2],
               "special_attack": stats[3], "special_defense": stats[4], "speed": stats[5],
               "ability": ability, "item": item, "nature": nature,
               "evs": [0, 252, 0, 0, 4, 252], "status": "none", "status_count": 0,
               "weight_kg": 100.0,
               "moves": [{"id": m, "pp": 16, "disabled": False} for m in moves]}
        out.update(extra)
        return out
    golurk = mon("GOLURK", ["GROUND", "GHOST"], [335, 344, 196, 131, 196, 209],
                 "IRONFIST", "LIFEORB", "ADAMANT", ["EARTHQUAKE", "SHADOWPUNCH", "ICEPUNCH", "STEALTHROCK"])
    durant = mon("DURANT", ["BUG", "STEEL"], [261, 336, 260, 108, 132, 329],
                 "HUSTLE", "CHOICESCARF", "JOLLY", ["IRONHEAD", "XSCISSOR", "SUPERPOWER", "ROCKSLIDE"])
    galvantula = mon("GALVANTULA", ["BUG", "ELECTRIC"], [281, 170, 156, 299, 156, 346],
                     "COMPOUNDEYES", "CHOICESPECS", "TIMID", ["THUNDER", "BUGBUZZ", "GIGADRAIN", "VOLTSWITCH"])
    landorus = mon("LANDORUS", ["GROUND", "FLYING"], [319, 369, 216, 249, 196, 245],
                   "INTIMIDATE", "LEFTOVERS", "NAIVE", ["EARTHQUAKE", "HIDDENPOWER", "UTURN", "STEALTHROCK"],
                   form=1)
    landorus["moves"][1].update({"hp_type": "ICE", "hp_power": 70})
    side = lambda active, mons, **extra: dict({
        "active": active,
        "boosts": {"attack": 0, "defense": 0, "special_attack": 0, "special_defense": 0,
                   "speed": 0, "accuracy": 0, "evasion": 0},
        "conditions": {"reflect": 0, "light_screen": 0, "spikes": 0, "toxic_spikes": 0,
                       "stealth_rock": 0, "sticky_web": 0, "tailwind": 0, "safeguard": 0,
                       "mist": 0, "lucky_chant": 0, "crafty_shield": 0, "mat_block": 0,
                       "quick_guard": 0, "wide_guard": 0},
        "toxic_count": 0, "wish": [0, 0], "volatiles": [],
        "durations": {"confusion": 0, "encore": 0, "taunt": 0, "yawn": 0, "lockedmove": 0, "slowstart": 0},
        "substitute_health": 0, "trapped": False, "last_used_move": "move:none",
        "pokemon": mons}, **extra)
    return {
        "version": 1, "turn": 3, "actor": 1, "weather": "none", "weather_turns": 0,
        "trick_room": False, "trick_room_turns": 0, "terrain": ["none", 0], "iterations": 300,
        "side_one": side(0, [golurk, durant], volatiles=["SUBSTITUTE"], substitute_health=83),
        "side_two": side(0, [galvantula, landorus], conditions={"stealth_rock": 1}),
        "cells": {
            "out_moves": {"EARTHQUAKE": {"pct": 100.0, "damaging": True},
                          "SHADOWPUNCH": {"pct": 50.0, "damaging": True},
                          "STEALTHROCK": {"pct": 0.0, "damaging": False}},
            "in_moves": {"THUNDER": {"pct": 0.0, "damaging": True},
                         "GIGADRAIN": {"pct": 60.0, "damaging": True}},
        },
    }


class FoulPlaySidecarTest(unittest.TestCase):
    """tools/foul_play_sidecar.py: the Realidea export -> poke_engine State -> reply path.
    The engine-backed tests need the gen 6 build of poke_engine (tools/build_poke_engine.sh)."""

    def setUp(self):
        import foul_play_sidecar
        self.sidecar = foul_play_sidecar
        self.ids = foul_play_sidecar.load_ids()

    def test_id_list_is_the_gen6_engine_vocabulary(self):
        self.assertIn("GALVANTULA", self.ids["pokemon"])
        self.assertIn("LANDORUSTHERIAN", self.ids["pokemon"])
        self.assertIn("HIDDENPOWERICE70", self.ids["moves"])
        self.assertIn("SUBSTITUTE", self.ids["volatiles"])
        self.assertIn("TOXIC", self.ids["status"])

    def test_unknown_ids_are_reported_not_mapped_quietly(self):
        problems = self.sidecar.Problems()
        self.assertEqual("NONE", self.sidecar.species_id({"species": "NOTAMON"}, self.ids, problems))
        self.assertEqual("LANDORUSTHERIAN",
                         self.sidecar.species_id({"species": "LANDORUS", "form": 1}, self.ids, problems))
        self.assertEqual("CHARIZARDMEGAY",
                         self.sidecar.species_id({"species": "CHARIZARD", "form": 2, "mega": True}, self.ids, problems))
        self.assertEqual("HIDDENPOWERICE70",
                         self.sidecar.move_id({"id": "HIDDENPOWER", "hp_type": "ICE", "hp_power": 70}, self.ids, problems))
        self.assertEqual("HIDDENPOWERFIRE60",
                         self.sidecar.move_id({"id": "HIDDENPOWER", "hp_type": "FIRE", "hp_power": 59}, self.ids, problems))
        self.assertEqual("NONE", self.sidecar.named("items", "EJECTBUTTON", self.ids, problems, "NONE"))
        self.assertEqual(["species NOTAMON unknown to poke-engine", "item EJECTBUTTON unknown to poke-engine"],
                         list(problems))

    def test_durations_are_turned_from_remaining_into_elapsed(self):
        # Essentials: Taunt just used = 3 turns left; poke-engine: 0 turns elapsed.
        self.assertEqual({"taunt": 0, "encore": 2, "yawn": 1, "slowstart": 4, "confusion": 2, "lockedmove": 1},
                         self.sidecar.durations_for({"taunt": 3, "encore": 1, "yawn": 1, "slowstart": 4,
                                                     "confusion": 2, "lockedmove": 2}))
        self.assertEqual({"taunt": 0, "yawn": 0}, self.sidecar.durations_for({"taunt": 9, "yawn": 0}),
                         "more turns left than the move lasts reads as none elapsed, never as a panic")

    def test_reply_text_names_the_slot_and_every_option(self):
        text = self.sidecar.reply_text(("switch:1", 900, 540.0),
                                       [("move:0", 100, 60.0), ("switch:1", 900, 540.0)],
                                       [("move:2", 1000)], 1000, 1000)
        self.assertEqual(["type=switch", "slot=1", "visits=900", "score=0.600000", "iterations=1000",
                          "total=1000", "own=move:0:100,switch:1:900", "foe=move:2:1000"],
                         text.strip().split("\n"))

    def _engine(self):
        try:
            import poke_engine  # noqa: F401
        except ImportError:
            self.skipTest("poke_engine (gen 6 build) is not importable here")

    def test_state_builds_and_the_search_answers_with_a_playable_slot(self):
        self._engine()
        doc = _foul_play_doc()
        problems = self.sidecar.Problems()
        state = self.sidecar.build_state(doc, self.ids, problems)
        self.assertEqual([], list(problems))
        self.assertEqual("golurk", state.side_one.pokemon[0].id)
        self.assertEqual("landorustherian", state.side_two.pokemon[1].id)
        self.assertEqual("hiddenpowerice70", state.side_two.pokemon[1].moves[1].id)
        self.assertEqual(83, state.side_one.substitute_health)
        self.assertEqual(1, state.side_two.side_conditions.stealth_rock)
        best, own, foe, total = self.sidecar.search(doc, state, 300)
        self.assertGreaterEqual(total, 300, "poke-engine counts in chunks of a thousand")
        labels = sorted(label for label, _, _ in own)
        self.assertEqual(["move:0", "move:1", "move:2", "move:3", "switch:1"], labels,
                         "every option maps back to a slot the adapter can register")
        self.assertIn(best[0], labels)

    def test_damage_check_prices_both_directions_against_the_cells(self):
        self._engine()
        doc = _foul_play_doc()
        state = self.sidecar.build_state(doc, self.ids, self.sidecar.Problems())
        rows = self.sidecar.damage_check(doc, state, self.ids)
        by_move = {(r["direction"], r["move"]): r for r in rows}
        self.assertEqual({("out", "EARTHQUAKE"), ("out", "SHADOWPUNCH"), ("in", "THUNDER"), ("in", "GIGADRAIN")},
                         set(by_move), "status moves are not priced")
        self.assertGreater(by_move[("out", "EARTHQUAKE")]["engine_max_pct"], 50.0)
        self.assertEqual(0.0, by_move[("in", "THUNDER")]["engine_max_pct"], "Ground is immune")
        self.assertAlmostEqual(by_move[("in", "THUNDER")]["diff"], 0.0)
        self.assertIsNotNone(by_move[("out", "SHADOWPUNCH")]["diff"])


if __name__ == "__main__":
    unittest.main()
