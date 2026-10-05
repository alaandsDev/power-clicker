"""
render_power_path.py — renders do CAMINHO DO PODER (corredor das barreiras).

  python tools/render_power_path.py [map_parts.json] [pasta_saida] [prefixo]

Usa o renderizador aproximado do lobby (tools/render_map3d.py): sem textura,
sem sombra, sem PointLight, vidro opaco, Neon chapado. Serve para comparar
COMPOSIÇÃO entre versões nas MESMAS câmeras — escala e luz reais: Studio.

Câmeras (todas derivadas do CorridorLayout, a mesma conta do WorldBuilder):
  01 entrada olhando o corredor     02-07 barreiras 1, 3, 5, 7, 9, 10
  08 portal                         09 aérea completa (planta, 3 faixas)
  10 lateral completa (4 trechos)   11 fundo olhando o lobby
  12 visão geral lobby + Caminho    13-15 transições 1→2, 3→4, 8→9

  Com o 4º argumento "B": o conjunto da Fase B (estágios 1–3) — portão,
  floresta, transição 1→2, ruínas, transição 2→3 (3 posições), gelo, folha
  comparativa 1/2/3 SEM TEXTO na mesma câmera relativa e o gelo olhando
  para trás.
"""
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_map3d as R  # noqa: E402

W, H = R.W, R.H

# Mesma conta do CorridorLayout.luau / WorldBuilder.buildCorridor.
STAGES = [("Wood", 3), ("Ruins", 4), ("Ice", 4), ("Crystal", 4), ("Gold", 5), ("Ancient", 5), ("Volcanic", 5), ("Magma", 6), ("Tech", 6), ("Colossus", 8)]
START, ROOM, WIDTH, WALLH, ROWT, GAP, FINAL = 150, 110, 86, 30, 8, 2, 1.6
SEG = []
cursor = START
for i, (sid, rows) in enumerate(STAGES):
    scale = FINAL if i == len(STAGES) - 1 else 1
    depth = rows * ROWT + (rows - 1) * GAP
    SEG.append(dict(id=sid, start=cursor, wall=cursor + ROOM * scale, depth=depth, end=cursor + ROOM * scale + depth + 72, h=WALLH * scale))
    cursor = SEG[-1]["end"]
PORTAL_X = cursor + 120 - 4


def phase_b(parts, out, tag):
    """Câmeras da Fase B (estágios 1–3), relativas ao CorridorLayout."""
    A = [SEG[i]["start"] for i in range(3)]
    B = [SEG[i]["wall"] for i in range(3)]
    END = [SEG[i]["end"] for i in range(3)]

    def shot(name, eye, target, title, fov=70, text=True):
        R.render(parts, R.Cam(eye, target, fov=fov), f"{out}/{name}.png", f"{tag} - {title}", show_text=text)

    def aerial(name, index, title):
        cx = (A[index] + END[index]) / 2
        span = END[index] - A[index] + 20
        R.render(parts, None, f"{out}/{name}.png", f"{tag} - {title}", show_text=False, ortho=(cx, 0, W / span))

    shot("b00_portao_do_lobby", [60, 12, 10], [260, 14, 0], "olhando do lobby pelo portao")
    # Estágio 1 — floresta.
    shot("b10_floresta_entrada_portao", [118, 9, -8], [260, 11, 0], "1 floresta: entrada pelo portao")
    shot("b11_floresta_jogador_entrando", [A[0] + 6, 8, 4], [A[0] + 80, 9, -2], "1 floresta: jogador entrando")
    shot("b12_floresta_aproximando_b1", [B[0] - 34, 8, -6], [B[0], 12, 2], "1 floresta: aproximando da Barreira 1")
    aerial("b13_floresta_aerea", 0, "1 floresta: aerea")
    # Transição 1 → 2.
    shot("b20_trans12_inicio", [A[0] + 70, 9, 12], [B[0] + 10, 9, -10], "transicao 1-2: inicio (fim da floresta)")
    shot("b21_trans12_meio", [B[0] + SEG[0]["depth"] + 4, 12, -24], [A[1] + 40, 8, 6], "transicao 1-2: meio (depois da Barreira 1)")
    shot("b22_trans12_entrada_ruinas", [A[1] + 4, 8, 6], [A[1] + 90, 10, -4], "transicao 1-2: entrando nas ruinas")
    # Estágio 2 — ruínas.
    shot("b30_ruinas_entrada", [A[1] + 6, 9, -4], [B[1], 12, 4], "2 ruinas: entrada")
    shot("b31_ruinas_landmark", [A[1] + 36, 9, 14], [A[1] + 58, 18, -30], "2 ruinas: landmark (arco quebrado)")
    shot("b32_ruinas_aproximando_b2", [B[1] - 34, 8, 6], [B[1], 12, -2], "2 ruinas: aproximando da Barreira 2")
    aerial("b33_ruinas_aerea", 1, "2 ruinas: aerea")
    # Transição 2 → 3 (pedra → frost → gelo).
    shot("b40_trans23_pedra_fria", [A[1] + 70, 8, -14], [B[1] - 4, 6, 26], "transicao 2-3: pedra comecando a congelar")
    shot("b41_trans23_frost", [B[1] + SEG[1]["depth"] + 4, 12, 24], [A[2] + 30, 6, -8], "transicao 2-3: frost depois da Barreira 2")
    shot("b42_trans23_gelo", [A[2] - 8, 9, -6], [A[2] + 70, 12, 4], "transicao 2-3: entrando no gelo")
    # Estágio 3 — gelo.
    shot("b50_gelo_entrada", [A[2] + 2, 9, 4], [B[2], 14, 0], "3 gelo: entrada")
    shot("b51_gelo_landmark", [A[2] + 40, 10, -6], [A[2] + 60, 16, 34], "3 gelo: landmark (formacoes de gelo)")
    shot("b52_gelo_camera_jogador", [A[2] + 48, 8, 3], [A[2] + 90, 7, 0], "3 gelo: camera normal do jogador")
    shot("b53_gelo_aproximando_b3", [B[2] - 34, 8, -6], [B[2], 12, 2], "3 gelo: aproximando da Barreira 3")
    aerial("b54_gelo_aerea", 2, "3 gelo: aerea")
    shot("b55_gelo_olhando_para_tras", [B[2] - 10, 22, 10], [150, 4, 0], "3 gelo olhando para tras (a jornada)", fov=60, text=False)
    # Folha 1/2/3 sem texto, mesma câmera relativa.
    panels = []
    for i in range(3):
        R.render(parts, R.Cam([A[i] + 20, 9, -10], [A[i] + 110, 10, 6], fov=70), f"{out}/_cmp.png", None, show_text=False)
        panels.append(Image.open(f"{out}/_cmp.png").resize((640, 360)))
    os.remove(f"{out}/_cmp.png")
    sheet = Image.new("RGB", (640 * 3 + 8, 360), (255, 255, 255))
    for i, im in enumerate(panels):
        sheet.paste(im, (i * 644, 0))
    sheet.save(f"{out}/b60_comparacao_1_2_3_sem_texto.png")


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "build", "map_parts.json")
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(root, "build", "render", "power_path")
    tag = sys.argv[3] if len(sys.argv) > 3 else "Caminho do Poder"
    os.makedirs(out, exist_ok=True)
    parts, _ = R.load(src)
    if len(sys.argv) > 4 and sys.argv[4] == "B":
        phase_b(parts, out, tag)
        return

    def shot(name, cam, title, text=True):
        R.render(parts, cam, f"{out}/{name}.png", f"{tag} - {title}", show_text=text)

    shot("01_entrada", R.Cam([118, 9, -8], [260, 11, 0], fov=72), "entrada olhando o corredor")
    for n, index in ((2, 0), (3, 2), (4, 4), (5, 6), (6, 8), (7, 9)):
        s = SEG[index]
        shot(f"{n:02d}_barreira_{index + 1}", R.Cam([s["wall"] - 46, 10, -16], [s["wall"], 12 + (s["h"] - 30) * 0.3, 0], fov=72), f"Barreira {index + 1} (camera igual em todas)")
    shot("08_portal", R.Cam([PORTAL_X - 95, 14, -10], [PORTAL_X, 20, 0], fov=70), "portal futuro")
    # Aérea: o corredor tem ~2.500 studs; em perspectiva a névoa apaga tudo.
    span = (PORTAL_X + 30 - START) / 3
    strips = []
    for k in range(3):
        cx = START + span * (k + 0.5)
        R.render(parts, None, f"{out}/_strip.png", None, show_text=False, ortho=(cx, 0, W / span))
        strips.append(Image.open(f"{out}/_strip.png").crop((0, H // 2 - 110, W, H // 2 + 110)))
    os.remove(f"{out}/_strip.png")
    sheet = Image.new("RGB", (W, 26 + 220 * 3), (0, 0, 0))
    for k, strip in enumerate(strips):
        sheet.paste(strip, (0, 26 + 220 * k))
    ImageDraw.Draw(sheet).text((10, 5), f"{tag} - aerea (planta) do corredor inteiro: entrada a esquerda, em 3 faixas", fill=(255, 255, 255))
    sheet.save(f"{out}/09_aerea.png")
    shots = []
    for cx in (START + 300, START + 900, START + 1500, PORTAL_X - 280):
        R.render(parts, R.Cam([cx - 60, 95, -230], [cx, 10, 0], fov=78), f"{out}/_lat.png", None, show_text=False)
        shots.append(Image.open(f"{out}/_lat.png").resize((640, 360)))
    os.remove(f"{out}/_lat.png")
    sheet = Image.new("RGB", (1280, 26 + 720), (0, 0, 0))
    for k, im in enumerate(shots):
        sheet.paste(im, ((k % 2) * 640, 26 + (k // 2) * 360))
    ImageDraw.Draw(sheet).text((10, 5), f"{tag} - lateral em 4 trechos (1-3 | 3-6 | 6-8 | 9-10 e portal)", fill=(255, 255, 255))
    sheet.save(f"{out}/10_lateral.png")
    shot("11_fundo_ate_o_lobby", R.Cam([PORTAL_X - 30, 62, 0], [PORTAL_X - 760, 6, 0], fov=60), "do fundo olhando o lobby (elevada)", text=False)
    shot("12_lobby_e_caminho", R.Cam([-60, 150, -170], [420, 0, 0], fov=62), "visao geral: lobby + Caminho do Poder", text=False)
    # Transições: logo depois da barreira N (na zona de decisão) olhando a área N+1.
    for n, index in ((13, 0), (14, 2), (15, 7)):
        s = SEG[index]
        x = s["wall"] + s["depth"] + 4
        shot(f"{n:02d}_transicao_{index + 1}_{index + 2}", R.Cam([x, 16, -26], [x + 120, 6, 6], fov=70), f"transicao {index + 1} -> {index + 2} (depois da barreira {index + 1})")
        # E o último terço da área N (o anúncio do próximo tema) até a barreira.
        shot(f"{n:02d}b_anuncio_{index + 1}_{index + 2}", R.Cam([s["wall"] - 60, 12, 24], [s["wall"], 8, -10], fov=70), f"ultimo terco da area {index + 1} anunciando a {index + 2}")


if __name__ == "__main__":
    main()
