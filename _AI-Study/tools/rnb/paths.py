"""Where the Run & Bun study reads and writes. See RNB-STUDY.md for the whole pipeline."""
import json
import os
import threading
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
STUDY = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(STUDY, "tools")
# The trainer-doc sheet tabs (story order, 00-09) and "Mechanic Changes.txt".
SRC = os.path.join(STUDY, "extracted", "runandbun")
# Everything derived: parsed trainers, battle pairings, team files, results.
RNB = os.path.join(STUDY, "generated", "rnb")
# Where a battle run reads its pairs/teams and writes results. RNB_OUT points the harness
# at another experiment (make_gen_battles.py uses generated/rnb_vs_gen).
OUT = os.environ.get("RNB_OUT", RNB)
# The foul-play clone and the pokemon-showdown npm install the battles need. Untracked.
WORK = os.environ.get("RNB_WORK", os.path.join(STUDY, "generated", "rnb_work"))
FOUL_PLAY = os.path.join(WORK, "foul-play")
VENV_PY = os.path.join(FOUL_PLAY, ".venv", *(("Scripts", "python.exe") if os.name == "nt" else ("bin", "python")))
SHOWDOWN = os.path.join(WORK, "showdown")
TEAM_DIR = os.path.join(FOUL_PLAY, "fp", "teams", "teams")   # foul-play loads teams from here
DUMP = os.path.join(STUDY, "extracted", "smogon-dump")

POKEDEX = os.path.join(RNB, "pokedex.json")                    # cached, untracked
POKEDEX_URL = "https://play.pokemonshowdown.com/data/pokedex.json"


def out(name):
    return os.path.join(OUT, name)


_append_lock = threading.Lock()


def read_results(path):
    """Every record in a results.ndjson. A power cut can leave a half-written last line;
    it is skipped (that battle is simply played again), never allowed to stop a resume."""
    if not os.path.exists(path):
        return []
    recs = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            try:
                recs.append(json.loads(line))
            except ValueError:
                continue
    return recs


def append_result(path, rec):
    """Append one record. If the file ends mid-line (a cut-off write), start on a fresh
    line so the new record is not glued onto the fragment. Workers are threads, so the
    append is locked."""
    with _append_lock:
        with open(path, "a+b") as fh:
            fh.seek(0, os.SEEK_END)
            if fh.tell():
                fh.seek(-1, os.SEEK_END)
                if fh.read(1) != b"\n":
                    fh.write(b"\n")
            fh.write((json.dumps(rec) + "\n").encode("utf-8"))
            fh.flush()
            os.fsync(fh.fileno())


def pokedex():
    """Showdown's gen 9 base stats and formes. Run & Bun's docs carry no base stats, so
    these are vanilla numbers -- wrong for any species the game rebalanced."""
    if not os.path.exists(POKEDEX):
        os.makedirs(RNB, exist_ok=True)
        # play.pokemonshowdown.com answers urllib's default User-Agent with a 403
        req = urllib.request.Request(POKEDEX_URL, headers={"User-Agent": "ai_study-rnb/1.0"})
        with urllib.request.urlopen(req) as resp, open(POKEDEX, "wb") as fh:
            fh.write(resp.read())
    with open(POKEDEX, encoding="utf-8") as fh:
        return json.load(fh)
