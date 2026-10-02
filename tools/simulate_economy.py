"""
simulate_economy.py — plays the game on paper, minute by minute.

Rewritten for the game as it is TODAY: hold-to-click, cut pads, the win
corridor, eggs/pets, upgrades and rebirth. The training islands are gone
(ZoneConfig.Build = false), so they are not modelled any more — the old version
still counted them and reported income that no longer exists.

It reads the real Luau configs, so it can never drift from the game by itself.

What it answers:
  - where the Power actually comes from now
  - how long until: first egg, first useful pet, each barrier, first rebirth
  - whether a player stalls (a barrier they cannot dent, nothing left to buy)
  - what a player who just rebirthed goes through on the way back

Usage:
  python tools/simulate_economy.py                 # the four profiles
  python tools/simulate_economy.py --hours 6       # longer session
  python tools/simulate_economy.py --training 0.5  # assume a training area
                                                   # paying 50% of a click/sec
"""

from __future__ import annotations

import argparse
import os
import random
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, "src", "shared", "Config")


def read(name: str) -> str:
    return open(os.path.join(CONFIG, name), encoding="utf-8").read()


def number(text: str, field: str, default: float | None = None) -> float:
    """First `Field = <number>` in `text` (underscores allowed: 5_000)."""
    match = re.search(rf"\b{field}\s*=\s*([0-9_]+(?:\.[0-9]+)?)", text)
    if not match:
        if default is None:
            raise SystemExit(f"config field not found: {field}")
        return default
    return float(match.group(1).replace("_", ""))


# ── Config ──────────────────────────────────────────────────────────────────

economy = read("EconomyConfig.luau")
BASE_PER_CLICK = number(economy, "BasePowerPerClick")
HOLD_CPS = number(economy, "HoldClicksPerSecond")

rebirth_text = read("RebirthConfig.luau")
REBIRTH_BASE_COST = number(rebirth_text, "BaseCost")
REBIRTH_GROWTH = number(rebirth_text, "CostGrowth")
REBIRTH_BONUS = number(rebirth_text, "MultiplierPerRebirth")
REBIRTH_BASE_GEMS = number(rebirth_text, "BaseGems")
REBIRTH_GEMS_PER = number(rebirth_text, "GemsPerRebirth")

event = read("EventConfig.luau")
pickup_block = event.split("Pickup = {", 1)[1].split("Boss = {", 1)[0]
boss_block = event.split("Boss = {", 1)[1]
ORB_INTERVAL = number(pickup_block, "IntervalSeconds")
ORB_CLICKS = number(pickup_block, "ClicksWorth")
BOSS_INTERVAL = number(boss_block, "IntervalSeconds")
BOSS_CLICKS_TO_KILL = number(boss_block, "ClicksToKill")
BOSS_REWARD_RATIO = number(boss_block, "RewardRatio")

training_text = read("TrainingConfig.luau")
# Each machine is "clicks per second equivalent"; a player uses the best one
# they qualify for. The fields span several lines, so each station is read as a
# block between braces.
STATION_BLOCK = re.compile(
    r'Id = "(\w+)",.*?Rate = ([\d.]+),\s*RequiredWins = ([\d_]+)', re.S
)
TRAINING = [
    {
        "Id": match.group(1),
        "Rate": float(match.group(2)),
        "RequiredWins": float(match.group(3).replace("_", "")),
    }
    for match in STATION_BLOCK.finditer(training_text)
]
if not TRAINING:
    raise SystemExit("could not read the training stations from TrainingConfig")
TRAINING.sort(key=lambda item: item["Rate"])
TRAINING_CAP = number(training_text, "MaxShareOfHoldClick") * HOLD_CPS


def training_rate(wins: float) -> float:
    """Best machine the player qualifies for, in clicks per second."""
    rate = 0.0
    for machine in TRAINING:
        if wins >= machine["RequiredWins"]:
            rate = min(machine["Rate"], TRAINING_CAP)
    return rate


session = read("SessionConfig.luau")
CHESTS = [
    (float(minutes.replace("_", "")), float(clicks.replace("_", "")))
    for minutes, clicks in re.findall(r"Minutes\s*=\s*([0-9_]+),\s*ClicksWorth\s*=\s*([0-9_]+)", session)
]

upgrades_text = read("UpgradeConfig.luau")
UPGRADES = []
for block in upgrades_text.split("\t\tId = ")[1:]:
    UPGRADES.append(
        {
            "Id": block.split('"')[1],
            "Currency": "Gems" if 'Currency = "Gems"' in block else "Power",
            "BaseCost": number(block, "BaseCost"),
            "CostGrowth": number(block, "CostGrowth"),
            "MaxLevel": number(block, "MaxLevel"),
            "EffectType": re.search(r'EffectType\s*=\s*"(\w+)"', block).group(1),
            "EffectPerLevel": number(block, "EffectPerLevel"),
        }
    )

cuts_text = read("CutConfig.luau")
CUTS = []
for line in cuts_text.split("\n"):
    if not re.match(r"\tCut\d+ = \{", line):
        continue
    CUTS.append(
        {
            "Id": line.split('"')[1],
            "Flat": number(line, "Flat"),
            "Price": number(line, "Price"),
            "RequiredWins": number(line, "RequiredWins"),
        }
    )
CUTS.sort(key=lambda cut: cut["Flat"])

walls_text = read("WallConfig.luau")
WALL_OPEN_SECONDS = number(walls_text, "OpenSeconds")
# Rendimento decrescente ao repetir uma barreira (WallConfig.Repeat).
_repeat = walls_text.split("Repeat = {")[1]
REPEAT_SHARE = number(_repeat, "Share")
REPEAT_FALLOFF = number(_repeat, "FalloffPerStage")
REPEAT_MIN = number(_repeat, "MinShare")
# How long a player is willing to hammer one row before giving up on it.
BREAK_PATIENCE = 120.0
# Stages are written with the `stage(...)` helper:
#   stage("Wood", 1, "Madeira", 60, 3, { 1, 2 }, 0, Color3..., Material..., ...)
STAGE_CALL = re.compile(
    r'stage\(\s*"(\w+)",\s*(\d+),\s*"[^"]*",\s*([\d_]+),\s*(\d+),\s*\{([^}]*)\},\s*([\d_]+)'
)
STAGES = []
for match in STAGE_CALL.finditer(walls_text):
    pads = [float(p.replace("_", "")) for p in re.findall(r"[\d_]+", match.group(5))]
    STAGES.append(
        {
            "Id": match.group(1),
            "Order": int(match.group(2)),
            "Hp": float(match.group(3).replace("_", "")),
            "Rows": float(match.group(4)),
            "Pads": pads,
            "FirstClearGems": float(match.group(6).replace("_", "")),
        }
    )
if not STAGES:
    raise SystemExit("could not read the tower stages from WallConfig")
STAGES.sort(key=lambda item: item["Order"])

eggs_text = read("EggConfig.luau")
pets_text = read("PetConfig.luau")
PET_BONUS = {
    match.group(1): float(match.group(2))
    for match in re.finditer(r'pet\("(\w+)", "[^"]*", "\w+", ([\d.]+)', pets_text)
}
BASE_EQUIP_SLOTS = number(pets_text, "BaseEquipSlots")
BASE_INVENTORY_SLOTS = number(pets_text, "BaseInventorySlots")

EGGS = []
for block in eggs_text.split("\t\tId = ")[1:]:
    drops = [
        (match.group(1), float(match.group(2)))
        for match in re.finditer(r'PetId = "(\w+)", Weight = ([\d.]+)', block)
    ]
    EGGS.append(
        {
            "Id": block.split('"')[1],
            "Currency": "Gems" if 'Currency = "Gems"' in block else "Power",
            "Price": number(block, "Price"),
            "Drops": drops,
            "RequiredStage": (
                re.search(r'RequiredStage = "(\w+)"', block).group(1)
                if 'RequiredStage = "' in block
                else None
            ),
        }
    )
# Melhor ovo primeiro: o jogador compra o mais caro que consegue pagar.
EGGS.sort(key=lambda egg: egg["Price"], reverse=True)
POWER_EGG = next(egg for egg in EGGS if egg["Currency"] == "Power")


# ── Player ──────────────────────────────────────────────────────────────────


class Player:
    """One simulated player. Time in seconds, Power in Power."""

    def __init__(self, name: str, hold_share: float, orb_catch: float, fights_boss: bool, rebirths: int = 0, seed: int = 1, training_share: float = 0.0):
        self.name = name
        # Holding the button fires HOLD_CPS; `hold_share` is how much of the
        # time this player actually holds it.
        self.cps = HOLD_CPS * hold_share
        # Time spent on a training machine instead of holding the button.
        self.training_share = training_share
        self.orb_catch = orb_catch
        self.fights_boss = fights_boss
        self.rng = random.Random(seed)

        self.power = 0.0
        self.gems = 0.0
        self.wins = 0.0
        self.total_power = 0.0
        self.rebirths = rebirths
        self.levels: dict[str, int] = {}
        self.pets: list[float] = []
        self.cut_index = 0  # index into CUTS
        self.stage = 0  # highest stage index the player may attack
        self.cleared: set[str] = set()  # a first clear pays gems once
        self.highest = 0  # maior Order conquistado: manda no rendimento decrescente
        self.income = {"clicks": 0.0, "orbs": 0.0, "boss": 0.0, "chests": 0.0, "training": 0.0}
        self.milestones: dict[str, float] = {}
        self.stalled_at: float | None = None

    # ── Power ───────────────────────────────────────────────────────────
    def equip_capacity(self) -> int:
        extra = 0
        for upgrade in UPGRADES:
            if upgrade["EffectType"] == "EquipSlots":
                extra += int(upgrade["EffectPerLevel"]) * self.levels.get(upgrade["Id"], 0)
        return int(BASE_EQUIP_SLOTS) + extra

    def pet_multiplier(self) -> float:
        best = sorted(self.pets, reverse=True)[: self.equip_capacity()]
        return 1 + sum(best)

    def per_click(self) -> float:
        flat = CUTS[self.cut_index]["Flat"]
        multiplier = 1.0
        for upgrade in UPGRADES:
            level = self.levels.get(upgrade["Id"], 0)
            if upgrade["EffectType"] == "ClickPowerFlat":
                flat += upgrade["EffectPerLevel"] * level
            elif upgrade["EffectType"] == "PowerMultiplier":
                multiplier += upgrade["EffectPerLevel"] * level
        # Composto, igual ao EconomyFormulas.RebirthMultiplier.
        rebirth_multiplier = (1 + REBIRTH_BONUS) ** self.rebirths
        return (BASE_PER_CLICK + flat) * multiplier * rebirth_multiplier * self.pet_multiplier()

    def earn(self, source: str, amount: float):
        self.power += amount
        self.total_power += amount
        self.income[source] += amount

    def mark(self, key: str, seconds: float):
        self.milestones.setdefault(key, seconds)

    # ── Spending ────────────────────────────────────────────────────────
    def buy_upgrades(self):
        """
        Compra como um jogador compra: a melhoria mais barata que ele pode
        pagar — mas guardando gema para ovo. Gastar toda gema em nível de
        melhoria permanente deixaria o multiplicador de pets parado, que é o
        oposto do que alguém faz.
        """
        egg_reserve = min(
            (egg["Price"] for egg in EGGS if egg["Currency"] == "Gems"), default=0
        )
        while True:
            best = None
            best_cost = None
            for upgrade in UPGRADES:
                level = self.levels.get(upgrade["Id"], 0)
                if level >= upgrade["MaxLevel"]:
                    continue
                cost = upgrade["BaseCost"] * upgrade["CostGrowth"] ** level
                balance = self.power if upgrade["Currency"] == "Power" else self.gems
                if upgrade["Currency"] == "Gems" and upgrade["EffectType"] not in ("EquipSlots", "InventorySlots"):
                    # Melhorias de gema que não são espaço só com troco sobrando.
                    balance -= egg_reserve
                if cost <= balance and (best_cost is None or cost < best_cost):
                    best, best_cost = upgrade, cost
            if not best:
                return
            if best["Currency"] == "Power":
                self.power -= best_cost
            else:
                self.gems -= best_cost
            self.levels[best["Id"]] = self.levels.get(best["Id"], 0) + 1

    def buy_cut(self, now: float):
        """The next cut, when it is affordable and the wins are there."""
        while self.cut_index + 1 < len(CUTS):
            nxt = CUTS[self.cut_index + 1]
            if self.power < nxt["Price"] or self.wins < nxt["RequiredWins"]:
                return
            self.power -= nxt["Price"]
            self.cut_index += 1
            self.mark(f"cut {nxt['Id']}", now)

    def hatch(self, now: float):
        """
        Abre o MELHOR ovo que o jogador pode pagar e já liberou (os da torre
        pedem o estágio). Antes isto só comprava o ovo de Power, e a simulação
        mostrava o multiplicador de pets travado em +60% para sempre — um
        problema do simulador, não do jogo.

        Guarda um troco: gastar a última gema em ovo deixaria o jogador sem as
        melhorias permanentes, o que nenhum jogador faz.
        """
        while len(self.pets) < BASE_INVENTORY_SLOTS:
            egg = None
            for candidate in EGGS:
                stage = candidate["RequiredStage"]
                if stage and stage not in self.cleared:
                    continue
                balance = self.power if candidate["Currency"] == "Power" else self.gems
                if balance >= candidate["Price"] * (10 if candidate["Currency"] == "Power" else 2):
                    egg = candidate
                    break
            if not egg:
                return
            if egg["Currency"] == "Power":
                self.power -= egg["Price"]
            else:
                self.gems -= egg["Price"]
            total = sum(weight for _, weight in egg["Drops"])
            roll = self.rng.uniform(0, total)
            for pet_id, weight in egg["Drops"]:
                roll -= weight
                if roll <= 0:
                    bonus = PET_BONUS.get(pet_id, 0.0)
                    self.pets.append(bonus)
                    self.mark("first egg", now)
                    if bonus >= 0.3:
                        self.mark("useful pet", now)
                    if bonus >= 5:
                        self.mark("pet forte", now)
                    break

    def rebirth_cost(self) -> float:
        return REBIRTH_BASE_COST * REBIRTH_GROWTH**self.rebirths

    def do_rebirth(self, now: float):
        self.gems += REBIRTH_BASE_GEMS + REBIRTH_GEMS_PER * self.rebirths
        self.rebirths += 1
        self.power = 0.0
        # Temporary (Power) upgrades reset; gem upgrades stay.
        for upgrade in UPGRADES:
            if upgrade["Currency"] == "Power":
                self.levels[upgrade["Id"]] = 0
        self.mark(f"rebirth {self.rebirths}", now)


def simulate(player: Player, hours: float, training: float) -> Player:
    step = 1.0
    elapsed = 0.0
    next_orb = ORB_INTERVAL
    next_boss = BOSS_INTERVAL
    chests_paid = 0
    row_hp_left = 0.0
    rows_left = 0.0
    farming_stage = None
    last_progress_at = 0.0
    last_power_mark = 0.0

    while elapsed < hours * 3600:
        per_click = player.per_click()
        clicks = player.cps * step * (1 - player.training_share)

        #[[
        #   The corridor: the player attacks the HIGHEST barrier whose row they
        #   can break in BREAK_PATIENCE seconds, and keeps farming it (the
        #   barrier rebuilds, the pads pay again). Only modelling the first
        #   break of each stage made wins stop forever, which is not the game.
        #]]
        dps = per_click * player.cps
        stage = None
        for candidate in STAGES[: player.stage + 1]:
            if dps * BREAK_PATIENCE >= candidate["Hp"]:
                stage = candidate
        attacking = stage is not None

        player.earn("clicks", per_click * clicks)
        # Training pays while the player is on a machine; they are not clicking
        # then, which is why the share is taken off the clicking time above.
        machine = training if training > 0 else training_rate(player.wins) * player.training_share
        if machine > 0:
            player.earn("training", per_click * machine * step)

        if attacking:
            if stage is not farming_stage:
                farming_stage = stage
                rows_left = 0
            if rows_left <= 0:
                rows_left = stage["Rows"]
                row_hp_left = stage["Hp"]
            row_hp_left -= per_click * clicks
            while row_hp_left <= 0 and rows_left > 0:
                rows_left -= 1
                if rows_left > 0:
                    row_hp_left += stage["Hp"]
            if rows_left <= 0:
                # Way open: grab the best pad in the window, then it rebuilds.
                # Mesma regra do servidor: repetir paga uma fração, e cai
                # mais ainda se o estágio está abaixo do melhor já conquistado.
                pad = max(stage["Pads"])
                if stage["Id"] in player.cleared:
                    behind = max(player.highest - stage["Order"], 0)
                    share = max(REPEAT_SHARE * REPEAT_FALLOFF**behind, REPEAT_MIN)
                else:
                    share = 1.0
                    player.cleared.add(stage["Id"])
                    player.highest = max(player.highest, stage["Order"])
                    # First clear of a stage is the game's gem tap.
                    player.gems += stage["FirstClearGems"]
                player.wins += max(int(pad * share), 1)
                player.mark(f"stage {stage['Id']}", elapsed)
                if stage is STAGES[player.stage] and player.stage + 1 < len(STAGES):
                    player.stage += 1
                last_progress_at = elapsed
                rows_left = 0
                row_hp_left = 0.0
                # The run back and the rebuild are part of the cycle.
                elapsed += WALL_OPEN_SECONDS

        # Orbs and chests are the passive trickle.
        next_orb -= step
        if next_orb <= 0:
            next_orb += ORB_INTERVAL
            if player.rng.random() < player.orb_catch:
                player.earn("orbs", per_click * ORB_CLICKS)
        if player.fights_boss:
            next_boss -= step
            if next_boss <= 0:
                next_boss += BOSS_INTERVAL
                # Solo server: the whole pool, which is the optimistic case.
                player.earn("boss", per_click * BOSS_CLICKS_TO_KILL * BOSS_REWARD_RATIO)
        if chests_paid < len(CHESTS) and elapsed >= CHESTS[chests_paid][0] * 60:
            player.earn("chests", per_click * CHESTS[chests_paid][1])
            chests_paid += 1

        # A player close to a rebirth stops spending and banks for it; buying
        # upgrades that are about to be reset is exactly what they avoid.
        saving = player.power >= player.rebirth_cost() * 0.5
        if not saving:
            player.buy_upgrades()
            player.buy_cut(elapsed)
            player.hatch(elapsed)
        if player.power >= player.rebirth_cost():
            player.do_rebirth(elapsed)

        # A player is "stalled" when 20 minutes pass with no new stage and no
        # meaningful Power growth — the wall the brief wants to avoid.
        if player.total_power > last_power_mark * 1.5:
            last_power_mark = player.total_power
            last_progress_at = elapsed
        if player.stalled_at is None and elapsed - last_progress_at > 20 * 60:
            player.stalled_at = elapsed

        elapsed += step
    return player


# ── Report ──────────────────────────────────────────────────────────────────


def human(seconds: float) -> str:
    if seconds < 60:
        return f"{seconds:.0f}s"
    if seconds < 3600:
        return f"{seconds / 60:.0f}min"
    return f"{seconds / 3600:.1f}h"


def short(value: float) -> str:
    for limit, suffix in ((1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")):
        if value >= limit:
            return f"{value / limit:.2f}{suffix}"
    return f"{value:.0f}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--hours", type=float, default=2.0)
    parser.add_argument(
        "--training",
        type=float,
        default=0.0,
        help="forca um Rate de treino (cliques/s) em vez de usar o TrainingConfig",
    )
    args = parser.parse_args()

    profiles = [
        Player("casual (clique 35%, treino 40% do tempo)", 0.35, 0.25, False, seed=7, training_share=0.4),
        Player("ativo (clique 75%, treino 20%)", 0.75, 0.7, True, seed=11, training_share=0.2),
        Player("muito ativo (clique 95%, quase nao treina)", 0.95, 0.9, True, seed=13, training_share=0.05),
        Player("pos-renascimento (5 renascimentos, do zero)", 0.75, 0.7, True, rebirths=5, seed=17, training_share=0.2),
    ]

    print(f"Simulacao: {args.hours:.0f}h de sessao   |   clique segurado = {HOLD_CPS:.0f}/s")
    if args.training > 0:
        print(f"Area de treino assumida: {args.training:.2f} clique/s equivalente")
    print()

    for player in profiles:
        simulate(player, args.hours, args.training)
        total = sum(player.income.values()) or 1
        print(player.name)
        per_click = player.per_click()
        dps = per_click * player.cps
        # Qual barreira esse dano derruba dentro da paciencia do jogador?
        reachable = 0
        for stage in STAGES:
            if dps * BREAK_PATIENCE >= stage["Hp"]:
                reachable = stage["Order"]
        print(
            f"  por clique: {short(per_click)}   alcance: estagio {reachable}"
            f"   gemas: {player.gems:.0f}"
        )
        print(
            f"  renascimentos: {player.rebirths}   vitorias: {player.wins:.0f}"
            f"   corte: {CUTS[player.cut_index]['Id']}   pets: {len(player.pets)}"
            f"   power total: {short(player.total_power)}"
        )
        sources = "  ".join(f"{name}: {value / total * 100:4.1f}%" for name, value in player.income.items() if value > 0)
        print(f"  origem do power -> {sources}")
        stages = [key for key in player.milestones if key.startswith("stage")]
        print(f"  estagios abertos: {len(stages)}/{len(STAGES)}")
        marks = "  ".join(f"{key}: {human(seconds)}" for key, seconds in sorted(player.milestones.items(), key=lambda item: item[1]))
        print(f"  marcos -> {marks if marks else 'nenhum'}")
        if player.stalled_at is not None:
            print(f"  ATENCAO: travado a partir de {human(player.stalled_at)} (sem estagio novo nem crescimento)")
        print()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
