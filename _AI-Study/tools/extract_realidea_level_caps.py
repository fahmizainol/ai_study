#!/usr/bin/env python3
"""Derive the level-cap progression from compiled Realidea battle extraction."""

import argparse
import json


PROGRESSION = [
    (0, 78, "LIDER", "Abi", "Gym 1"),
    (1, 114, "AIMI", "Aimi", "Gym 2"),
    (2, 117, "KENN", "Kenn", "Gym 3"),
    (3, 240, "DOUGLAS", "Douglas", "Gym 4"),
    (4, 122, "CIARA", "Ciara", "Gym 5"),
    (5, 254, "DHARA", "Dhara", "Gym 6"),
    (6, 273, "ARDILLO", "Lawrence", "Gym 7"),
    (7, 287, "BAY", "Bay", "Gym 8"),
    (8, 156, "FINALILLIANA", "Lilliana", "Champion"),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("battles")
    parser.add_argument("output")
    args = parser.parse_args()
    with open(args.battles, encoding="utf-8") as source:
        battles = json.load(source)

    caps = []
    for badges, map_id, trainer_type, name, title in PROGRESSION:
        matches = [battle for battle in battles
                   if battle["map"] == map_id and battle["type"] == trainer_type and
                   battle["name"] == name]
        if len(matches) != 1:
            raise ValueError("expected one %s battle, found %d" % (title, len(matches)))
        team = matches[0]["party"]
        levels = [mon["level"] for mon in team if isinstance(mon["level"], int)]
        if not levels or len(levels) != len(team):
            raise ValueError("%s has a missing or dynamic level" % title)
        caps.append({
            "badges": badges,
            "next_battle": title,
            "map": map_id,
            "map_name": matches[0].get("map_name"),
            "trainer_type": trainer_type,
            "trainer": name,
            "team": team,
            "cap": max(levels),
        })

    with open(args.output, "w", encoding="utf-8", newline="\n") as output:
        json.dump(caps, output, indent=2, ensure_ascii=False)
        output.write("\n")
    print("caps: " + "/".join(str(row["cap"]) for row in caps))


if __name__ == "__main__":
    main()
