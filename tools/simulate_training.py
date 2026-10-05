"""
simulate_training.py — quanto o Campo de Treinamento pesa na economia.

Usa o MESMO simulador do jogo (tools/simulate_economy.py, que lê os configs
Luau de verdade) e só troca o requisito das 4 estações de treino:

  - "vitorias (antigo)": 0 / 10 / 60 / 300 vitórias
  - candidatos por Renascimento (0 / a / b / c)
  - "sem treino": as mesmas pessoas, mas o tempo na máquina não paga nada
    (é a referência para medir quanto o treino acelera)

Responde, por perfil e duração:
  - quando cada estação libera
  - quanto do Power veio do treino
  - quanto o treino adianta o próximo renascimento
  - se muda a barreira máxima alcançada

Uso:
  python tools/simulate_training.py              # relatório completo
  python tools/simulate_training.py --quick      # só 2 h, para conferir
"""

from __future__ import annotations

import argparse
import copy
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import simulate_economy as se  # noqa: E402

RATES = [station["Rate"] for station in se.TRAINING]
AUTO_TICKS = se.number(se.economy, "TicksPerSecond")


def stations(kind: str, values: list[float]) -> list[dict]:
    return [
        {"Id": f"T{index + 1}", "Rate": rate, "RequiredWins" if kind == "wins" else "RequiredRebirths": value}
        for index, (rate, value) in enumerate(zip(RATES, values))
    ]


SETS = {
    "vitorias 0/10/60/300 (antigo)": stations("wins", [0, 10, 60, 300]),
    "renasc. 0/1/2/4": stations("rebirths", [0, 1, 2, 4]),
    "renasc. 0/1/3/6": stations("rebirths", [0, 1, 3, 6]),
    "renasc. 0/2/5/10": stations("rebirths", [0, 2, 5, 10]),
    "sem treino": stations("rebirths", [0, 0, 0, 0]),
}


def profiles(start_rebirths: int = 0) -> list[se.Player]:
    casual = se.Player("casual", 0.35, 0.25, False, rebirths=start_rebirths, seed=7, training_share=0.4)
    ativo = se.Player("ativo", 0.75, 0.7, True, rebirths=start_rebirths, seed=11, training_share=0.2)
    muito = se.Player("muito ativo", 0.95, 0.9, True, rebirths=start_rebirths, seed=13, training_share=0.05)
    # Auto Click: 4 golpes/s do servidor, parado em cima da máquina o tempo todo.
    auto = se.Player("auto click (AFK no treino)", AUTO_TICKS / se.HOLD_CPS, 0.0, False, rebirths=start_rebirths, seed=19, training_share=1.0)
    auto.auto_click = True
    return [casual, ativo, muito, auto]


def run(player: se.Player, hours: float, set_name: str) -> se.Player:
    p = copy.deepcopy(player)
    p.stations = SETS[set_name]
    if set_name == "sem treino":
        p.stations = [dict(station, Rate=0.0) for station in p.stations]
    return se.simulate(p, hours, 0.0)


def unlock_times(p: se.Player, set_name: str) -> str:
    out = []
    for station in SETS[set_name]:
        need_r = station.get("RequiredRebirths", 0)
        need_w = station.get("RequiredWins", 0)
        if need_r == 0 and need_w == 0:
            out.append("0")
        elif need_r:
            key = f"rebirth {int(need_r)}"
            out.append(se.human(p.milestones[key]) if key in p.milestones else ("ja" if p.rebirths >= need_r and key not in p.milestones else "-"))
        else:
            out.append("?")
    return "/".join(out)


def reach(p: se.Player) -> int:
    dps = p.per_click() * max(p.cps, 1e-9)
    best = 0
    for stage in se.STAGES:
        if dps * se.BREAK_PATIENCE >= stage["Hp"]:
            best = stage["Order"]
    return best


def share(p: se.Player) -> float:
    total = sum(p.income.values()) or 1
    return p.income["training"] / total * 100


def rebirth_marks(p: se.Player) -> str:
    keys = sorted((k for k in p.milestones if k.startswith("rebirth")), key=lambda k: p.milestones[k])
    return " ".join(f"R{k.split()[1]}@{se.human(p.milestones[k])}" for k in keys[:6]) or "-"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--quick", action="store_true")
    args = parser.parse_args()
    hours_list = [2.0] if args.quick else [0.5, 1, 2, 4, 8, 12]

    print(f"Rates: {RATES}  teto {se.TRAINING_CAP:.2f}  clique segurado {se.HOLD_CPS:.0f}/s  auto click {AUTO_TICKS:.0f}/s")
    print()
    print("== 1. Perfis do zero (0 renascimentos) ==")
    for hours in hours_list:
        print(f"-- {se.human(hours * 3600)} --")
        for base in profiles(0):
            line = [f"  {base.name:<26}"]
            for set_name in SETS:
                p = run(base, hours, set_name)
                line.append(f"[{set_name}] R={p.rebirths} treino={share(p):4.1f}% est={reach(p)} lib={unlock_times(p, set_name)} power={se.short(p.total_power)}")
            print(line[0])
            for item in line[1:]:
                print("     " + item)
    print()
    print("== 2. Aceleracao dos renascimentos (ativo e casual, 4 h) ==")
    for base in profiles(0)[:2]:
        for set_name in SETS:
            p = run(base, 4 if not args.quick else 2, set_name)
            print(f"  {base.name:<10} {set_name:<30} {rebirth_marks(p)}")
    print()
    print("== 3. Jogador que ja renasceu (ativo, 2 h a partir de R renascimentos) ==")
    for start in [0, 1, 3, 5, 10, 20]:
        base = profiles(start)[1]
        cells = []
        for set_name in SETS:
            p = run(base, 2, set_name)
            cells.append(f"{set_name.split(' (')[0]}: +{p.rebirths - start}R treino {share(p):4.1f}% est {reach(p)}")
        print(f"  R={start:<3} " + " | ".join(cells))
    print()
    print("== 4. Escala: treino em relacao ao clique (independe de Renascimento x Pet x Aura) ==")
    for rate in RATES:
        print(f"  rate {rate:.2f}: {rate / se.HOLD_CPS * 100:4.1f}% do clique segurado, {rate / AUTO_TICKS * 100:4.1f}% do auto click")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
