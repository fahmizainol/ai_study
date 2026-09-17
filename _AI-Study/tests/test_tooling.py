import json
import os
import re
import shutil
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


class TeamOverrideBattleFormatTest(unittest.TestCase):
    def record(self, battle_format):
        return [{
            "id": "double_boss", "map": 1, "type_id": 2, "name": "Boss",
            "orig_ace_level": 20, "battle_format": battle_format,
            "mons": [{"species": "PIKACHU", "level": 20,
                      "moves": ["TACKLE"], "item": None, "ability": 0,
                      "nature": "HARDY", "iv": 31, "ev": [0] * 6}],
        }]

    def emit(self, battle_format):
        import emit_registry
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            teams = root / "teams.json"
            output = root / "Team_Overrides.rb"
            teams.write_text(json.dumps(self.record(battle_format)), encoding="utf-8")
            emit_registry.main(str(output), str(teams))
            return output.read_text(encoding="utf-8")

    def test_double_format_is_compiled_and_applied_to_custom_battle(self):
        source = self.emit("double")
        self.assertIn('TEAM_OVERRIDE_FORMATS[[1,2,"Boss",20]] = :double', source)
        self.assertIn("def customTrainerBattle(trainer, endspeech, doublebattle=false", source)
        self.assertIn("doublebattle = (fmt == :double)", source)

    def test_inherit_format_leaves_the_event_unforced(self):
        source = self.emit("inherit")
        self.assertNotIn('TEAM_OVERRIDE_FORMATS[[1,2,"Boss",20]]', source)

    def test_unknown_format_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "invalid battle_format"):
            self.emit("triple")

    def test_studio_export_imports_politoed_from_poliwhirl_family(self):
        """The branching-evolution un-pin: POLIWHIRL supplies POLIWRATH *or*
        POLITOED, so un-pinning on family membership alone dropped an imported
        POLITOED and shifted the whole gym up a slot.

        Reads the SHIPPED gym file, not a draft export: teams_bosses_studio.json
        was the draft and is gone, and guarding this on a file that can vanish is
        how the regression stopped being covered at all."""
        import boss_studio
        if _shipped_is_valid():
            self.skipTest("generated/ is invalid — see ShippedTeamFilesTest")
        path = STUDY / "generated" / "teams_bosses_gyms.json"
        self.assertTrue(path.exists(), f"{path.name} is the shipped gym file")
        team = json.loads(path.read_text(encoding="utf-8"))
        if not any(mon["species"] == "POLITOED" for mon in team[2]["mons"]):
            self.skipTest("gym 3 no longer carries POLITOED to regress on")
        loaded = boss_studio.team_load(path.name, boss_studio.defaults())
        self.assertEqual(9, loaded["gyms"])
        self.assertEqual(sum(len(r["mons"]) for r in team), loaded["mons"])
        self.assertTrue(loaded["settings"]["PICKS"]["g2"]["keep"]["POLITOED"])


class BossStudioFreezeTest(unittest.TestCase):
    """Freezing pins a fight to a team the generator is then never asked to
    re-derive. The point is that it survives the thing card overrides cannot:
    PBS and the Smogon dump live outside this repo, so the same knobs give
    different teams later, and a preset that only stores knobs cannot promise
    another machine the same teams."""

    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(STUDY / "tools"))
        import boss_studio
        cls.BS = boss_studio
        cls.base = boss_studio.run({})

    @staticmethod
    def sig(records):
        return [[mon["species"] for mon in r["mons"]] for r in records]

    # Knobs chosen to reroll everything if anything is listening: a theme every
    # gym has to rebuild around, a band nothing currently sits in, a fresh seed.
    HOSTILE = {"THEME": ["STEEL"] * 9, "TARGET": [300] * 9, "SET_SEED": 777}

    def test_frozen_fights_ignore_knobs_that_would_reroll_them(self):
        frozen = self.BS.set_frozen({}, None, True)
        self.assertEqual(27, frozen["count"], "nine gyms plus 18 named trainers")
        got = self.BS.run({**frozen["settings"], **self.HOSTILE})
        self.assertEqual(self.sig(self.base["records"]), self.sig(got["records"]))
        self.assertEqual(self.sig(self.base["trainer_records"]),
                         self.sig(got["trainer_records"]))
        self.assertEqual(self.base["sha"], got["sha"])

    def test_the_same_knobs_do_reroll_an_unfrozen_build(self):
        """Without this the test above passes on a generator that ignores the
        knobs entirely, which would prove nothing about freezing."""
        loose = self.BS.run(dict(self.HOSTILE))
        self.assertNotEqual(self.sig(self.base["records"]),
                            self.sig(loose["records"]))

    def test_unfreezing_one_fight_rerolls_only_that_one(self):
        frozen = self.BS.set_frozen({}, None, True)["settings"]
        one = self.BS.set_frozen({**frozen, **self.HOSTILE}, ["g3"], False)
        self.assertEqual(26, one["count"])
        got = self.sig(self.BS.run(one["settings"])["records"])
        moved = [i for i, (a, b) in
                 enumerate(zip(got, self.sig(self.base["records"]))) if a != b]
        self.assertEqual([3], moved)

    def test_frozen_payload_survives_json(self):
        """Presets and localStorage are both JSON, so a set or a Counter left in
        the payload would come back as something the next build cannot use."""
        frozen = self.BS.set_frozen({}, None, True)["settings"]
        got = self.BS.run(json.loads(json.dumps(frozen)))
        self.assertEqual(self.base["sha"], got["sha"])
        # And byte-stable, or every preset save churns its own diff.
        again = self.BS.set_frozen({}, None, True)["settings"]
        self.assertEqual(json.dumps(frozen, sort_keys=True),
                         json.dumps(again, sort_keys=True))


class BossStudioCompanionPresetTest(unittest.TestCase):
    """A team file written by Export or Install names a companion preset holding
    those teams frozen, so loading the TEAM JSON is exact rather than a
    reverse-engineering of the knobs that might reach them."""

    def setUp(self):
        sys.path.insert(0, str(STUDY / "tools"))
        import boss_studio
        self.BS = boss_studio
        self.dir = tempfile.mkdtemp(prefix="studio-tie-")
        self._gen, self._pre = boss_studio.GENDIR, boss_studio.PRESETS
        boss_studio.GENDIR = self.dir
        boss_studio.PRESETS = os.path.join(self.dir, "presets")
        os.makedirs(boss_studio.PRESETS, exist_ok=True)

    def tearDown(self):
        self.BS.GENDIR, self.BS.PRESETS = self._gen, self._pre
        shutil.rmtree(self.dir, ignore_errors=True)

    @staticmethod
    def sig(records):
        return [[mon["species"] for mon in r["mons"]] for r in records]

    def _export(self, settings=None):
        """What /api/export does: snapshot a companion preset, stamp the tie, write."""
        built = self.BS.run(settings or {})
        preset = self.BS._companion("teams_bosses_gyms.json")
        self.BS.preset_save(preset, self.BS._snapshot(settings or {}, built), "probe")
        for name, key in (("teams_bosses_gyms.json", "records"),
                          ("teams_trainers.json", "trainer_records")):
            with open(os.path.join(self.dir, name), "w", encoding="utf-8") as fh:
                json.dump(self.BS._tie(built[key], preset), fh, indent=1)
        return built, preset

    def test_loading_the_team_json_follows_the_tie_and_is_exact(self):
        built, preset = self._export()
        got = self.BS.import_teams("teams_bosses_gyms.json", {})
        self.assertTrue(got["exact"])
        self.assertEqual(preset, got["preset"])
        rebuilt = self.BS.run(got["settings"])
        self.assertEqual(self.sig(built["records"]), self.sig(rebuilt["records"]))
        self.assertEqual(self.sig(built["trainer_records"]),
                         self.sig(rebuilt["trainer_records"]))
        self.assertEqual(built["sha"], rebuilt["sha"])

    def test_the_tie_holds_when_the_receiving_knobs_are_hostile(self):
        """The whole point: another machine's data and knobs must not reach it."""
        built, _ = self._export()
        got = self.BS.import_teams("teams_bosses_gyms.json", {})
        hostile = {**got["settings"], "THEME": ["STEEL"] * 9,
                   "TARGET": [300] * 9, "SET_SEED": 31337}
        self.assertEqual(self.sig(built["records"]),
                         self.sig(self.BS.run(hostile)["records"]))

    def test_exporting_does_not_freeze_the_live_session(self):
        """Handing someone an exact artifact must not pin the cards you are still
        editing -- the snapshot is frozen, the settings it came from are not."""
        built, preset = self._export()
        snap = self.BS.preset_load(preset)["settings"]
        self.assertEqual(27, len(snap["FROZEN"]))
        self.assertEqual({}, self.BS._thaw({}.get("FROZEN")))

    def test_a_file_with_no_companion_falls_back_and_says_so(self):
        self._export()
        path = os.path.join(self.dir, "teams_trainers.json")
        bare = json.loads(open(path, encoding="utf-8").read())
        for record in bare:
            record["design"].pop("preset", None)
        with open(os.path.join(self.dir, "bare.json"), "w", encoding="utf-8") as fh:
            json.dump(bare, fh, indent=1)
        got = self.BS.import_teams("bare.json", {})
        self.assertFalse(got["exact"])
        self.assertEqual(18, got["trainers"])

    def test_a_stitched_file_naming_two_presets_is_not_trusted(self):
        built, preset = self._export()
        path = os.path.join(self.dir, "teams_bosses_gyms.json")
        rows = json.loads(open(path, encoding="utf-8").read())
        rows[0]["design"]["preset"] = "somewhere_else"
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(rows, fh, indent=1)
        self.assertIsNone(self.BS._pointed_preset("teams_bosses_gyms.json"))


class BossStudioInstallScopeTest(unittest.TestCase):
    """Scoping the view has to scope the WRITE too, or it is a trap: loading a
    trainers JSON, hiding the gym cards and installing would still rewrite the
    gyms from cards nobody can see."""

    HOSTILE = {"THEME": ["STEEL"] * 9, "TARGET": [300] * 9, "SET_SEED": 99}

    def setUp(self):
        sys.path.insert(0, str(STUDY / "tools"))
        import boss_studio
        self.BS = boss_studio
        self.captured = {}
        self._real = boss_studio._replace_all
        boss_studio._replace_all = self.captured.update
        self._presets = boss_studio.PRESETS
        boss_studio.PRESETS = tempfile.mkdtemp(prefix="scope-presets-")

    def tearDown(self):
        self.BS._replace_all = self._real
        shutil.rmtree(self.BS.PRESETS, ignore_errors=True)
        self.BS.PRESETS = self._presets

    @staticmethod
    def sig(records):
        return [[mon["species"] for mon in r["mons"]] for r in records]

    def test_gyms_scope_leaves_the_trainer_file_alone(self):
        res = self.BS.install_game(self.HOSTILE, "gyms")
        self.assertNotIn("teams_trainers.json", res["replaced"])
        self.assertIn("teams_bosses_gyms.json", res["replaced"])
        self.assertNotIn(self.BS.SHIPPED_TRAINERS, self.captured)

    def test_trainers_scope_leaves_the_gym_file_alone(self):
        if _shipped_is_valid():
            self.skipTest("generated/ is invalid — see ShippedTeamFilesTest")
        res = self.BS.install_game(self.HOSTILE, "trainers")
        self.assertNotIn("teams_bosses_gyms.json", res["replaced"])
        self.assertNotIn(self.BS.SHIPPED, self.captured)

    def test_the_registry_still_carries_every_fight_and_takes_the_out_of_scope_half_from_disk(self):
        """The registry is one flat hash of all 161 teams, so scope cannot drop
        fights from it -- it only decides whether a half comes from the cards or
        off disk."""
        disk = json.loads(Path(self.BS.SHIPPED_TRAINERS).read_text(encoding="utf-8"))
        want = {r["id"]: [m["species"] for m in r["mons"]] for r in disk}
        self.BS.install_game(self.HOSTILE, "gyms")
        registry = self.captured[self.BS.REGISTRY].decode("utf-8")
        self.assertEqual(146, registry.count("TEAM_OVERRIDES[["))
        # Teresa's lead must be what the committed file says, not what the
        # hidden live cards built under HOSTILE.
        block = re.search(r"^# rival_TERESA_Teresa_map164\n.*?\n((?:  \[.*\n)+)",
                          registry, re.M)
        self.assertIsNotNone(block)
        lead = block.group(1).splitlines()[0].split('"')[1]
        self.assertEqual(want["rival_TERESA_Teresa_map164"][0], lead)

    def test_all_scope_writes_both(self):
        res = self.BS.install_game(self.HOSTILE, "all")
        for name in ("teams_bosses_gyms.json", "teams_trainers.json",
                     "Team_Overrides.rb", "Scripts.rxdata"):
            self.assertIn(name, res["replaced"])


class BossStudioLoadInstalledTest(unittest.TestCase):
    """A page with no saved session must open on what the game is running. Without
    it a fresh checkout shows teams built from the DEFAULT knobs, which match the
    installed gym file on none of the nine."""

    def setUp(self):
        sys.path.insert(0, str(STUDY / "tools"))
        import boss_studio
        self.BS = boss_studio

    @staticmethod
    def sig(records):
        return [[mon["species"] for mon in r["mons"]] for r in records]

    def _disk(self, path):
        return json.loads(Path(path).read_text(encoding="utf-8"))

    def test_it_reproduces_both_installed_files(self):
        got = self.BS.load_installed({})
        self.assertEqual(9, got["gyms"])
        self.assertEqual(18, got["trainers"])
        built = self.BS.run(got["settings"])
        self.assertEqual(self.sig(self._disk(self.BS.SHIPPED)),
                         self.sig(built["records"]))
        self.assertEqual(self.sig(self._disk(self.BS.SHIPPED_TRAINERS)),
                         self.sig(built["trainer_records"]))

    def test_the_default_knobs_do_not_already_match(self):
        """Otherwise the test above proves nothing -- it would pass on a page that
        never loaded anything."""
        fresh = self.sig(self.BS.run({})["records"])
        self.assertNotEqual(self.sig(self._disk(self.BS.SHIPPED)), fresh)


def _shipped_is_valid():
    """Whether generated/'s shipped team files would pass Install's own gate.

    generated/ is working data a person edits through the Studio, so a test that
    builds on it should say plainly that it is broken rather than fail somewhere
    deep in install with a SIZE error."""
    sys.path.insert(0, str(STUDY / "tools"))
    import boss_studio, validate_team
    rows = []
    for path in (boss_studio.SHIPPED, boss_studio.SHIPPED_TRAINERS):
        rows += json.loads(Path(path).read_text(encoding="utf-8"))
    errors, _warnings = validate_team.validate(rows)
    return errors


class ShippedTeamFilesTest(unittest.TestCase):
    def test_the_shipped_team_files_pass_the_install_gate(self):
        """If this is the only thing red, generated/ needs repairing, not the code:
        open the Studio, fix the named fight and Export again."""
        errors = _shipped_is_valid()
        self.assertEqual([], errors,
                         "generated/ holds teams Install would refuse: "
                         + "; ".join(errors[:3]))


class BossStudioLoadUnpinsTest(unittest.TestCase):
    """Loading used to hand back a board of locked cards. Pinning every species is
    the reverse-engineering path's only lever, but freezing holds the same teams
    outright, so once it is on the pins hold nothing and are cleared."""

    def setUp(self):
        sys.path.insert(0, str(STUDY / "tools"))
        import boss_studio
        self.BS = boss_studio

    @staticmethod
    def pins(settings):
        return sum(1 for v in (settings.get("PICKS") or {}).values()
                   if isinstance(v, dict)
                   for _sp, on in (v.get("keep") or {}).items() if on)

    @staticmethod
    def sig(records):
        return [[mon["species"] for mon in r["mons"]] for r in records]

    def test_loading_leaves_no_pins_and_freezes_instead(self):
        for name, key, shipped in (
                ("teams_bosses_gyms.json", "records", self.BS.SHIPPED),
                ("teams_trainers.json", "trainer_records",
                 self.BS.SHIPPED_TRAINERS)):
            with self.subTest(name):
                got = self.BS.import_teams(name, {})
                settings = got["settings"]
                self.assertEqual(0, self.pins(settings), "no pins survive a load")
                self.assertTrue(settings.get("FROZEN"), "frozen instead")
                disk = json.loads(Path(shipped).read_text(encoding="utf-8"))
                self.assertEqual(self.sig(disk),
                                 self.sig(self.BS.run(settings)[key]))

    def test_the_freeze_is_what_holds_them_now(self):
        """Unpinned teams must survive knobs that would otherwise reroll them --
        otherwise clearing the pins quietly threw the teams away."""
        got = self.BS.import_teams("teams_trainers.json", {})
        hostile = {**got["settings"], "THEME": ["STEEL"] * 9,
                   "TARGET": [300] * 9, "SET_SEED": 5150}
        disk = json.loads(
            Path(self.BS.SHIPPED_TRAINERS).read_text(encoding="utf-8"))
        self.assertEqual(self.sig(disk),
                         self.sig(self.BS.run(hostile)["trainer_records"]))

    def test_a_companion_snapshot_carries_no_pins(self):
        """Fixed at the source: every fight in a snapshot is frozen, so every pin
        in it is redundant and must not reach whoever loads it."""
        built = self.BS.run({})
        pinned = {"PICKS": {"g0": {"keep": {"KLEFKI": True}}}}
        snap = self.BS._snapshot(pinned, built)
        self.assertEqual(27, len(snap["FROZEN"]))
        self.assertEqual(0, self.pins(snap))
        # and the caller's own settings are untouched
        self.assertEqual(1, self.pins(pinned))


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


class LiveFoulPlayRenderTest(unittest.TestCase):
    def test_live_entry_renders_like_the_full_battle_readout(self):
        import contextlib
        import io
        import render_live_foul_play

        entry = {
            "battle_id": "demo", "portable_version": "0.8.1", "turn": 0,
            "actor": 1, "type": "move", "slot": 0, "move_id": "PECK",
            "score": 0.625,
            "view": {
                "species": "Vivillon", "hp_pct": 100, "speed": 42,
                "faster": True, "incoming_damage_pct": 20,
                "certain_incoming_damage_pct": 20, "threatened_lethal": False,
                "targets": [{"index": 0, "species": "Gulliby", "hp_pct": 100}],
                "race": {}, "matrix": {"own": [], "foe": []},
            },
            "foe": {"0": {"type": "move", "move_id": "AQUAJET"}},
            "candidates": [{"type": "move", "slot": 0, "move_id": "PECK",
                            "score": 3000, "search_visits": 3000,
                            "reasons": [["foul_play_visits", 3000]]}],
        }
        stream = io.StringIO()
        with contextlib.redirect_stdout(stream):
            render_live_foul_play.render([entry])
        text = stream.getvalue()
        self.assertIn("Turn 0", text)
        self.assertIn("Vivillon 100%  vs  Gulliby 100%", text)
        self.assertIn("Gulliby -> AQUAJET", text)
        self.assertIn("options considered:", text)
        self.assertIn("foul_play_visits +3000", text)


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
        self.assertEqual("WINGULL", self.sidecar.species_id({"species": "GULLIBY"}, self.ids, problems))
        self.assertEqual("SITRUSBERRY",
                         self.sidecar.named("items", "ORANBERRY", self.ids, problems, "NONE"))
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

    def test_permanent_gimmick_counters_fit_poke_engine_state(self):
        self.assertEqual(-1, self.sidecar.engine_turns(-1),
                         "permanent weather keeps poke-engine's native sentinel")
        self.assertEqual(127, self.sidecar.engine_turns(999),
                         "permanent terrain/rooms remain active without overflowing i8")
        self.assertEqual(5, self.sidecar.engine_turns(5))

    def test_state_carries_permanent_field_restoration_forecast(self):
        self._engine()
        doc = _foul_play_doc()
        doc["weather"] = "rain"
        doc["weather_turns"] = 2
        doc["base_weather"] = "sun"
        doc["terrain"] = ["electricterrain", 2]
        doc["base_terrain"] = ["grassyterrain", 127]
        state = self.sidecar.build_state(doc, self.ids, self.sidecar.Problems())
        self.assertEqual("sun", state.base_weather)
        self.assertEqual(-1, state.base_weather_turns_remaining)
        self.assertEqual("grassyterrain", state.base_terrain)
        self.assertEqual(127, state.base_terrain_turns_remaining)

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

    def test_realidea_gulliby_and_oran_build_without_unknown_placeholders(self):
        self._engine()
        doc = _foul_play_doc()
        mon = doc["side_one"]["pokemon"][0]
        mon["species"] = "GULLIBY"
        mon["item"] = "ORANBERRY"
        problems = self.sidecar.Problems()
        state = self.sidecar.build_state(doc, self.ids, problems)
        self.assertEqual([], list(problems))
        self.assertEqual("wingull", state.side_one.pokemon[0].id)
        self.assertEqual("sitrusberry", state.side_one.pokemon[0].item)

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
