"""Where the Run & Bun study reads and writes. See RNB-STUDY.md for the whole pipeline."""
import json
import os
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
STUDY = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(STUDY, "tools")
# The trainer-doc sheet tabs (story order, 00-09) and "Mechanic Changes.txt".
SRC = os.path.join(STUDY, "extracted", "runandbun")
# Everything derived: parsed trainers, battle pairings, team files, results.
OUT = os.path.join(STUDY, "generated", "rnb")
# The foul-play clone and the pokemon-showdown npm install the battles need. Untracked.
WORK = os.environ.get("RNB_WORK", os.path.join(STUDY, "generated", "rnb_work"))
FOUL_PLAY = os.path.join(WORK, "foul-play")
TEAM_DIR = os.path.join(FOUL_PLAY, "fp", "teams", "teams")   # foul-play loads teams from here
DUMP = os.path.join(STUDY, "extracted", "smogon-dump")

POKEDEX = os.path.join(OUT, "pokedex.json")                    # cached, untracked
POKEDEX_URL = "https://play.pokemonshowdown.com/data/pokedex.json"


def out(name):
    return os.path.join(OUT, name)


def pokedex():
    """Showdown's gen 9 base stats and formes. Run & Bun's docs carry no base stats, so
    these are vanilla numbers -- wrong for any species the game rebalanced."""
    if not os.path.exists(POKEDEX):
        os.makedirs(OUT, exist_ok=True)
        # play.pokemonshowdown.com answers urllib's default User-Agent with a 403
        req = urllib.request.Request(POKEDEX_URL, headers={"User-Agent": "ai_study-rnb/1.0"})
        with urllib.request.urlopen(req) as resp, open(POKEDEX, "wb") as fh:
            fh.write(resp.read())
    with open(POKEDEX, encoding="utf-8") as fh:
        return json.load(fh)
