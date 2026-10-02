"""
render_map.py — desenha a PLANTA do mapa a partir dos configs.

Por que planta e não render de verdade: o mapa do Power Clicker é construído em
tempo de execução pelo WorldBuilder, então o arquivo .rbxlx publicado só tem os
scripts — não existe geometria para renderizar fora do Roblox. O que dá para
fazer, e é o que realmente evita erro, é ler os MESMOS configs que o builder lê
e desenhar:

  - vista de cima da ilha: áreas do lobby, caminho, pads de corte, o corredor
    reto com as dez áreas e suas barreiras;
  - a ordem dos estágios do corredor, com HP e posição de cada um.

Serve para achar o tipo de erro que eu já cometi às cegas: área em cima de
área, pad invadindo área, caminhada vazia entre barreiras, corredor encostando
no mundo vizinho.

Uso:
  python tools/render_map.py                 # gera build/mapa_planta.png
  python tools/render_map.py --check         # só valida, sem desenhar
"""

from __future__ import annotations

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, "src", "shared", "Config")
OUT_DIR = os.path.join(ROOT, "build")


def read(name: str) -> str:
    return open(os.path.join(CONFIG, name), encoding="utf-8").read()


def number(text: str, field: str, default: float | None = None) -> float:
    match = re.search(rf"\b{field}\s*=\s*(-?[0-9_]+(?:\.[0-9]+)?)", text)
    if not match:
        if default is None:
            raise SystemExit(f"campo nao encontrado: {field}")
        return default
    return float(match.group(1).replace("_", ""))


def vector(text: str) -> tuple[float, float, float]:
    match = re.search(r"Vector3\.new\((-?[\d_.]+),\s*(-?[\d_.]+),\s*(-?[\d_.]+)\)", text)
    if not match:
        raise SystemExit("Vector3 nao encontrado")
    return tuple(float(part.replace("_", "")) for part in match.groups())  # type: ignore[return-value]


# ── Configs ─────────────────────────────────────────────────────────────────

builder = open(os.path.join(ROOT, "src", "server", "World", "WorldBuilder.luau"), encoding="utf-8").read()
GROUND_RADIUS = number(builder, "GROUND_RADIUS")
TILE_STUDS = number(builder, "TILE_STUDS")
# Altura que o personagem padrão do Roblox alcança num pulo.
ROBLOX_JUMP = 7.2

lobby = read("LobbyConfig.luau")
_cliffs = lobby.split("Cliffs = {")[1]
CLIFF_MIN_HEIGHT = number(_cliffs, "MinHeight")
CLIFF_DEPTH = number(_cliffs, "Depth")
AREAS = []
for block in lobby.split("\t\tId = ")[1:]:
    AREAS.append(
        {
            "Id": block.split('"')[1],
            "Offset": vector(block.split("Offset = ")[1]),
            "Radius": number(block, "Radius"),
        }
    )
PATH_WIDTH = number(lobby.split("Path = {")[1], "Width")
SCOREBOARD = vector(lobby.split("Scoreboard = ")[1])

cuts = read("CutConfig.luau")
cut_layout = cuts.split("Layout = {")[1]
CUT_AREA = re.search(r'Area = "(\w+)"', cut_layout).group(1)
CUT_COLUMNS = int(number(cut_layout, "Columns"))
_spacing = re.search(r"Spacing = Vector2\.new\(([\d.]+),\s*([\d.]+)\)", cut_layout)
CUT_SPACING = (float(_spacing.group(1)), float(_spacing.group(2)))
CUT_PAD = number(cut_layout, "PadSize")
CUT_COUNT = len(re.findall(r"\tCut\d+ = \{", cuts))


def cut_pad_positions() -> list[tuple[float, float]]:
    """A mesma grade que o WorldBuilder monta, em coordenadas do mundo."""
    area = next(item for item in AREAS if item["Id"] == CUT_AREA)
    rows = -(-CUT_COUNT // CUT_COLUMNS)
    positions = []
    for index in range(CUT_COUNT):
        column = index % CUT_COLUMNS
        row = index // CUT_COLUMNS
        x = area["Offset"][0] + (column - (CUT_COLUMNS - 1) / 2) * CUT_SPACING[0]
        z = area["Offset"][2] + (row - (rows - 1) / 2) * CUT_SPACING[1]
        positions.append((x, z))
    return positions

walls = read("WallConfig.luau")
wall_layout = walls.split("Layout = {")[1]
CORRIDOR = {
    field: number(wall_layout, field)
    for field in (
        "StartX",
        "RoomLength",
        "Width",
        "RowThickness",
        "RowGap",
        "FinalScale",
        "WallHeight",
    )
}
STAGE_CALL = re.compile(r'stage\(\s*"(\w+)",\s*(\d+),\s*"([^"]*)",\s*([\d_]+),\s*(\d+)')
STAGES = [
    {
        "Id": match.group(1),
        "Order": int(match.group(2)),
        "Name": match.group(3),
        "Hp": float(match.group(4).replace("_", "")),
        "Rows": int(match.group(5)),
    }
    for match in STAGE_CALL.finditer(walls)
]
STAGES.sort(key=lambda item: item["Order"])

world_service = open(os.path.join(ROOT, "src", "server", "Services", "WorldService.luau"), encoding="utf-8").read()
WORLD_SPACING = number(world_service, "WORLD_SPACING")


# ── Geometria da torre (igual à do builder) ─────────────────────────────────


def corridor_areas() -> list[dict]:
    """Mesma geometria que o WorldBuilder monta: áreas em linha, no mesmo nível."""
    areas = []
    cursor = CORRIDOR["StartX"]
    for index, stage in enumerate(STAGES, start=1):
        final = index == len(STAGES)
        scale = CORRIDOR["FinalScale"] if final else 1.0
        length = CORRIDOR["RoomLength"] * scale
        width = CORRIDOR["Width"] * scale
        depth = stage["Rows"] * CORRIDOR["RowThickness"] + (stage["Rows"] - 1) * CORRIDOR["RowGap"]
        tail = depth + 72
        areas.append(
            {
                "Stage": stage,
                "X0": cursor,
                "X1": cursor + length,
                "BarrierX0": cursor + length,
                "BarrierX1": cursor + length + depth,
                # Fim do PISO do trecho: pads e pad de voltar ficam aqui dentro.
                "FloorEnd": cursor + length + tail,
                "PadX": cursor + length + depth + 24,
                "ReturnPadX": cursor + length + depth + 48,
                "Width": width,
            }
        )
        cursor = cursor + length + tail
    return areas


# ── Validação ───────────────────────────────────────────────────────────────


def check() -> list[str]:
    problems: list[str] = []

    # áreas não podem se sobrepor
    for i, a in enumerate(AREAS):
        for b in AREAS[i + 1 :]:
            dx = a["Offset"][0] - b["Offset"][0]
            dz = a["Offset"][2] - b["Offset"][2]
            distance = (dx * dx + dz * dz) ** 0.5
            overlap = a["Radius"] + b["Radius"] - distance
            if overlap > 0:
                problems.append(
                    f"areas {a['Id']} e {b['Id']} se sobrepoem em {overlap:.0f} studs"
                )

    # tudo dentro da ilha (menos a torre, que sai de propósito)
    for area in AREAS:
        if area["Id"] == "Tower":
            continue
        reach = (area["Offset"][0] ** 2 + area["Offset"][2] ** 2) ** 0.5 + area["Radius"]
        if reach > GROUND_RADIUS:
            problems.append(f"area {area['Id']} passa da borda da ilha em {reach - GROUND_RADIUS:.0f} studs")

    # pads de corte: não podem invadir outra área, se encostar, nem vazar
    pads = cut_pad_positions()
    half = CUT_PAD / 2
    for area in AREAS:
        if area["Id"] == CUT_AREA:
            continue
        for x, z in pads:
            distance = ((x - area["Offset"][0]) ** 2 + (z - area["Offset"][2]) ** 2) ** 0.5
            if distance < area["Radius"] + half:
                problems.append(f"pad de corte em ({x:.0f}, {z:.0f}) invade a area {area['Id']}")
                break
    if CUT_SPACING[0] < CUT_PAD or CUT_SPACING[1] < CUT_PAD:
        problems.append("pads de corte se encostam (Spacing menor que PadSize)")
    host = next(item for item in AREAS if item["Id"] == CUT_AREA)
    for x, z in pads:
        distance = ((x - host["Offset"][0]) ** 2 + (z - host["Offset"][2]) ** 2) ** 0.5
        if distance + half > host["Radius"]:
            problems.append(f"pad de corte em ({x:.0f}, {z:.0f}) passa da borda da area {CUT_AREA}")
            break

    # o corredor não pode encostar no mundo vizinho
    areas = corridor_areas()
    far = max(area["BarrierX1"] for area in areas) + 200  # praça final + portal
    if far > WORLD_SPACING - GROUND_RADIUS:
        problems.append(
            f"o corredor chega a x={far:.0f} e o mundo vizinho comeca em {WORLD_SPACING - GROUND_RADIUS:.0f}"
        )

    # o paredão tem de ser inescalável, com folga para pulo turbinado por
    # aura de velocidade e para subir em decoração encostada nele
    if CLIFF_MIN_HEIGHT < ROBLOX_JUMP * 6:
        problems.append(
            f"paredao com {CLIFF_MIN_HEIGHT:.0f} studs: baixo demais (pulo do Roblox sobe {ROBLOX_JUMP:.1f})"
        )

    # o corredor tem de começar colado na ilha, sem vão para cair
    if areas[0]["X0"] > GROUND_RADIUS:
        problems.append(
            f"vao de {areas[0]['X0'] - GROUND_RADIUS:.0f} studs entre a borda da ilha e o corredor"
        )

    #[[
    #   Tudo do estágio tem de ficar SOBRE o piso. Foi exatamente isto que
    #   faltou na primeira versão do corredor: o piso parava no fim da área
    #   temática e o jogador caía ao atravessar a barreira.
    #]]
    for area in areas:
        for name, x in (("barreira", area["BarrierX1"]), ("pads", area["PadX"]), ("pad de voltar", area["ReturnPadX"])):
            if x + CUT_PAD / 2 > area["FloorEnd"]:
                problems.append(
                    f"estagio {area['Stage']['Order']}: {name} em x={x:.0f} passa do piso (termina em {area['FloorEnd']:.0f})"
                )

    # progressão: as áreas têm de estar em ordem e sem buraco entre elas
    for previous, area in zip(areas, areas[1:]):
        if abs(area["X0"] - previous["FloorEnd"]) > 0.5:
            problems.append(
                f"buraco de {area['X0'] - previous['FloorEnd']:.0f} studs no piso entre os estagios "
                f"{previous['Stage']['Order']} e {area['Stage']['Order']}"
            )
        if area["X0"] < previous["BarrierX1"]:
            problems.append(
                f"a area do estagio {area['Stage']['Order']} comeca antes da barreira anterior terminar"
            )
        gap = area["X0"] - previous["BarrierX1"]
        if gap > 100:
            problems.append(
                f"{gap:.0f} studs de caminhada vazia entre os estagios {previous['Stage']['Order']} e {area['Stage']['Order']}"
            )

    # a área final tem de ser maior que as outras
    if areas[-1]["Width"] <= areas[0]["Width"]:
        problems.append("a area final nao e mais larga que as outras")
    return problems


# ── Desenho ─────────────────────────────────────────────────────────────────


def draw() -> str:
    from PIL import Image, ImageDraw  # importado só aqui: --check nao precisa

    scale = 1.6  # pixels por stud
    margin = 40
    areas = corridor_areas()
    min_x = -GROUND_RADIUS - CLIFF_DEPTH
    max_x = max(area["BarrierX1"] for area in areas) + 220
    min_z = -GROUND_RADIUS - 40
    max_z = GROUND_RADIUS + 40
    plan_w = int((max_x - min_x) * scale) + margin * 2
    plan_h = int((max_z - min_z) * scale) + margin * 2
    side_h = len(areas) * 26 + margin * 3

    image = Image.new("RGB", (plan_w, plan_h + side_h), (18, 20, 32))
    draw_ctx = ImageDraw.Draw(image)

    def px(x: float, z: float) -> tuple[float, float]:
        return (margin + (x - min_x) * scale, margin + (z - min_z) * scale)

    # ilha
    centre = px(0, 0)
    draw_ctx.ellipse(
        [centre[0] - GROUND_RADIUS * scale, centre[1] - GROUND_RADIUS * scale,
         centre[0] + GROUND_RADIUS * scale, centre[1] + GROUND_RADIUS * scale],
        fill=(44, 84, 48), outline=(90, 140, 90), width=2,
    )

    # caminho para a torre
    tower = next(area for area in AREAS if area["Id"] == "Tower")
    p0 = px(0, -PATH_WIDTH / 2)
    p1 = px(tower["Offset"][0], PATH_WIDTH / 2)
    draw_ctx.rectangle([p0[0], p0[1], p1[0], p1[1]], fill=(120, 116, 104))

    # áreas
    palette = {
        "Spawn": (255, 226, 120), "Eggs": (255, 196, 45), "Pets": (80, 220, 255),
        "Shop": (255, 150, 80), "Rebirth": (170, 120, 255), "Training": (104, 230, 140),
        "Tower": (255, 120, 230),
    }
    for area in AREAS:
        colour = palette.get(area["Id"], (200, 200, 200))
        c = px(area["Offset"][0], area["Offset"][2])
        r = area["Radius"] * scale
        draw_ctx.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], outline=colour, width=3)
        draw_ctx.text((c[0] - 18, c[1] - 6), area["Id"], fill=colour)

    # pads de corte
    for x, z in cut_pad_positions():
        c = px(x, z)
        half = CUT_PAD / 2 * scale
        draw_ctx.rectangle([c[0] - half, c[1] - half, c[0] + half, c[1] + half], fill=(255, 210, 90))

    # quadro de recordes
    c = px(SCOREBOARD[0], SCOREBOARD[2])
    draw_ctx.rectangle([c[0] - 12, c[1] - 5, c[0] + 12, c[1] + 5], fill=(160, 170, 200))

    # corredor visto de cima: área clara, barreira cheia
    for area in areas:
        a = px(area["X0"], -area["Width"] / 2)
        b = px(area["X1"], area["Width"] / 2)
        draw_ctx.rectangle([a[0], a[1], b[0], b[1]], outline=(200, 120, 230), width=1)
        c = px(area["BarrierX0"], -area["Width"] / 2)
        d = px(area["BarrierX1"], area["Width"] / 2)
        draw_ctx.rectangle([c[0], c[1], d[0], d[1]], fill=(200, 120, 230))
    draw_ctx.text((margin, margin - 24), "VISTA DE CIMA — LOBBY E CORREDOR (studs)", fill=(220, 220, 235))

    # ── ordem do corredor, em lista ──
    base_y = plan_h + margin
    draw_ctx.text((margin, base_y - 24), "CORREDOR — ORDEM DOS ESTAGIOS", fill=(220, 220, 235))
    for index, area in enumerate(areas):
        stage = area["Stage"]
        y = base_y + index * 26
        draw_ctx.rectangle([margin, y, margin + 240, y + 18], outline=(150, 150, 180), width=1)
        draw_ctx.text((margin + 6, y + 4), f"area {stage['Order']}", fill=(200, 200, 220))
        draw_ctx.rectangle([margin + 244, y, margin + 268, y + 18], fill=(200, 120, 230))
        label = (
            f"{stage['Name']}  ({stage['Rows']}x{stage['Hp']:,.0f})"
            f"   x {area['X0']:.0f}..{area['BarrierX1']:.0f}"
        )
        draw_ctx.text((margin + 280, y + 4), label, fill=(230, 220, 160))

    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, "mapa_planta.png")
    image.save(out)
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="valida sem desenhar")
    args = parser.parse_args()

    problems = check()
    areas = corridor_areas()
    print(f"ilha: raio {GROUND_RADIUS:.0f}   areas do lobby: {len(AREAS)}   cortes: {CUT_COUNT}")
    print(
        f"corredor: {len(areas)} estagios em linha, x de {areas[0]['X0']:.0f} "
        f"a {areas[-1]['BarrierX1']:.0f} ({areas[-1]['BarrierX1'] - areas[0]['X0']:.0f} studs)"
    )
    if problems:
        print(f"{len(problems)} problema(s):")
        for problem in problems:
            print("  -", problem)
    else:
        print("OK: areas separadas, corredor reto em ordem, sem caminhada vazia.")

    if not args.check:
        try:
            print("planta:", draw())
        except ImportError:
            print("(Pillow nao instalado: rode com --check ou instale com 'pip install pillow')")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
