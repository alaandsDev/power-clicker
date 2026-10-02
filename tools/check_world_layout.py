"""
check_world_layout.py — checks the training zones on paper.

The game cannot be played from here, but most of what breaks in a zone layout
is arithmetic, and that can be checked: islands overlapping each other or the
plaza, bridges too long to walk, requirements that go backwards, and targets
that pay more than they cost.

Run after touching ZoneConfig or the island size in WorldBuilder:
  python tools/check_world_layout.py
"""

from __future__ import annotations

import math
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ZONE_CONFIG = os.path.join(ROOT, "src", "shared", "Config", "ZoneConfig.luau")
WORLD_BUILDER = os.path.join(ROOT, "src", "server", "World", "WorldBuilder.luau")

# A bridge longer than this is a long walk over nothing; shorter than the
# island rim means the platform would sit on top of the island.
MAX_BRIDGE = 140
MIN_GAP = 12
# A Roblox character walks up a slope comfortably to about this angle; past it
# the ramp turns into a wall and the player has to jump.
MAX_SLOPE_DEGREES = 32


def read(path: str) -> str:
    return open(path, encoding="utf-8").read()


def number(text: str, field: str) -> float:
    match = re.search(rf"\b{field}\s*=\s*(-?[0-9_]+(?:\.[0-9]+)?(?:e[+-]?\d+)?)", text)
    if not match:
        raise SystemExit(f"field not found: {field}")
    return float(match.group(1).replace("_", ""))


def main() -> int:
    zones_text = read(ZONE_CONFIG)
    builder = read(WORLD_BUILDER)
    ground_radius = number(builder, "GROUND_RADIUS")
    first_z = number(zones_text, "FIRST_Z")
    spacing_z = number(zones_text, "SPACING_Z")
    platform_height = number(zones_text, "PlatformHeight")

    zones = []
    for block in zones_text.split("\t\tId = ")[1:]:
        zones.append(
            {
                "Id": block.split('"')[1],
                "World": re.search(r'WorldId = "(\w+)"', block).group(1),
                "Order": int(number(block, "Order")),
                "Radius": number(block, "Radius"),
                "Multiplier": number(block, "Multiplier"),
                "Power": number(block, "Power"),
                "Rebirths": number(block, "Rebirths"),
                "Hp": number(block, "Hp"),
                "Reward": number(block, "Reward"),
                "Count": number(block, "Count"),
            }
        )

    problems: list[str] = []
    by_world: dict[str, list[dict]] = {}
    for zone in zones:
        by_world.setdefault(zone["World"], []).append(zone)

    for world, world_zones in sorted(by_world.items()):
        world_zones.sort(key=lambda zone: zone["Order"])
        print(f"{world}: {len(world_zones)} zona(s)")
        previous_edge = -(ground_radius - 2)  # north rim of the island
        previous = None
        for zone in world_zones:
            centre = first_z + spacing_z * (zone["Order"] - 1)
            gate = centre + zone["Radius"] - 2  # south rim, where the bridge lands
            bridge = abs(gate - previous_edge)
            # Only the first ramp climbs: the islands all sit at the same height.
            rise = platform_height if previous is None else 0.0
            slope = math.degrees(math.atan2(rise, bridge)) if bridge > 0 else 90.0
            print(f"  {zone['Id']:<14} centro z={centre:>6.0f}  raio={zone['Radius']:>3.0f}  ponte={bridge:>5.0f}  subida={slope:>4.1f} graus")

            if slope > MAX_SLOPE_DEGREES:
                problems.append(f"{world}/{zone['Id']}: ramp at {slope:.0f} degrees is too steep to walk up")
            if bridge > MAX_BRIDGE:
                problems.append(f"{world}/{zone['Id']}: bridge of {bridge:.0f} studs is a long walk over nothing")
            if bridge < MIN_GAP:
                problems.append(f"{world}/{zone['Id']}: only {bridge:.0f} studs from the previous edge (they touch)")
            if zone["Reward"] >= zone["Hp"]:
                problems.append(f"{world}/{zone['Id']}: target pays {zone['Reward']:.0f} for {zone['Hp']:.0f} of damage")
            if zone["Count"] < 4:
                problems.append(f"{world}/{zone['Id']}: only {zone['Count']:.0f} targets, players will queue")
            if previous:
                if zone["Multiplier"] <= previous["Multiplier"]:
                    problems.append(f"{world}/{zone['Id']}: multiplier does not grow over {previous['Id']}")
                if zone["Power"] <= previous["Power"]:
                    problems.append(f"{world}/{zone['Id']}: requirement does not grow over {previous['Id']}")
                if zone["Rebirths"] < previous["Rebirths"]:
                    problems.append(f"{world}/{zone['Id']}: asks fewer rebirths than {previous['Id']}")
            previous = zone
            previous_edge = centre - (zone["Radius"] - 2)  # north rim, next bridge starts here

    print()
    if problems:
        print(f"{len(problems)} problema(s):")
        for problem in problems:
            print("  -", problem)
        return 1
    print("OK: ilhas separadas, pontes caminháveis, exigências e alvos coerentes.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
