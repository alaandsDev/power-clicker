"""
render_map3d.py — render 3D APROXIMADO do mundo inicial, a partir do JSON do
tools/lune/export_map.luau.

Não é o renderizador do Roblox: primitivas com sombreamento chapado, sem
textura, sombra nem pós-processamento. Serve para julgar composição, peso de
cor, silhuetas, linha de visão e poluição de texto (os BillboardGui só
aparecem dentro do MaxDistance, como no jogo). O render_map.py continua sendo
a PLANTA 2D com as validações de layout; este arquivo é complementar.

Uso (da raiz do repositório):
    lune run tools/lune/export_map.luau
    python tools/render_map3d.py [build/map_parts.json] [build/render/mapa] [rótulo]

Gera <prefixo>_spawn.png (vista ao nascer), _overview.png (visão geral),
_gate.png (chegando na entrada do Caminho) e _top.png (vista de cima).
Requer: pip install pillow numpy
"""
from __future__ import annotations
import json, math, sys, re
import numpy as np
from PIL import Image, ImageDraw, ImageFont

W, H = 1280, 720

def unit_mesh(shape):
    """Triangles in unit local space (-0.5..0.5)."""
    tris = []
    if shape in ("Block",):
        c = [(x, y, z) for x in (-.5, .5) for y in (-.5, .5) for z in (-.5, .5)]
        def v(i): return c[i]
        faces = [(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]
        for a,b,cc,d in faces:
            tris += [(v(a),v(b),v(cc)),(v(a),v(cc),v(d))]
    elif shape == "Wedge":
        # high edge at +z (back), slope down to -z front
        A=(-.5,-.5,-.5);B=(.5,-.5,-.5);C=(.5,-.5,.5);D=(-.5,-.5,.5);E=(-.5,.5,.5);F=(.5,.5,.5)
        tris += [(A,B,C),(A,C,D),(D,C,F),(D,F,E),(A,E,F),(A,F,B),(A,D,E),(B,F,C)]
    elif shape == "Cylinder":
        n = 16
        for i in range(n):
            a0, a1 = 2*math.pi*i/n, 2*math.pi*(i+1)/n
            p0 = (math.cos(a0)*.5, math.sin(a0)*.5); p1 = (math.cos(a1)*.5, math.sin(a1)*.5)
            tris += [((-.5,p0[0],p0[1]),(.5,p0[0],p0[1]),(.5,p1[0],p1[1])),((-.5,p0[0],p0[1]),(.5,p1[0],p1[1]),(-.5,p1[0],p1[1]))]
            tris += [((.5,0,0),(.5,p0[0],p0[1]),(.5,p1[0],p1[1])),((-.5,0,0),(-.5,p1[0],p1[1]),(-.5,p0[0],p0[1]))]
    elif shape in ("Ball", "Egg"):
        nu, nv = 12, 8
        def sp(u, v):
            th, ph = 2*math.pi*u/nu, math.pi*v/nv
            return (math.sin(ph)*math.cos(th)*.5, math.cos(ph)*.5, math.sin(ph)*math.sin(th)*.5)
        for i in range(nu):
            for j in range(nv):
                a,b,c,d = sp(i,j),sp(i+1,j),sp(i+1,j+1),sp(i,j+1)
                tris += [(a,b,c),(a,c,d)]
    return np.array(tris, dtype=np.float64)

MESHES = {s: unit_mesh(s) for s in ("Block","Wedge","Cylinder","Ball","Egg")}

def load(path):
    data = json.load(open(path))
    return data["parts"], data["meta"]

class Cam:
    def __init__(self, eye, target, fov=70):
        self.eye = np.array(eye, float)
        f = np.array(target, float) - self.eye; f /= np.linalg.norm(f)
        r = np.cross(f, [0,1,0]); r /= np.linalg.norm(r)
        u = np.cross(r, f)
        self.f, self.r, self.u = f, r, u
        self.k = (H/2) / math.tan(math.radians(fov)/2)
    def project(self, pts):
        d = pts - self.eye
        x = d @ self.r; y = d @ self.u; z = d @ self.f
        return x, y, z

def _split_near(parts, cam):
    """
    Blocos grandes que CRUZAM o plano da câmera saíam distorcidos ou sumiam
    (a projeção corta pelo triângulo inteiro). Corta esses blocos em pedaços
    menores ao longo dos eixos locais, e só os pedaços na frente são
    desenhados. Só afeta o render; o mapa não muda.
    """
    out = []
    for part in parts:
        if part["s"] != "Block" or part.get("b"):
            out.append(part)
            continue
        size = np.array(part["z"], float)
        if size.max() < 8:
            out.append(part)
            continue
        Rm = np.array(part["r"]).reshape(3, 3)
        pos = np.array(part["p"], float)
        corners = np.array([[sx, sy, sz] for sx in (-.5, .5) for sy in (-.5, .5) for sz in (-.5, .5)]) * size @ Rm + pos
        depth = (corners - cam.eye) @ cam.f
        if depth.min() >= 0.5 or depth.max() < 0.5:
            out.append(part)
            continue
        counts = np.maximum(np.ceil(size / 4.0), 1).astype(int)
        counts[1] = min(counts[1], 4)
        piece = size / counts
        for i in range(counts[0]):
            for j in range(counts[1]):
                for k in range(counts[2]):
                    local = (np.array([i, j, k]) + 0.5) * piece - size / 2
                    centre = local @ Rm + pos
                    if (centre - cam.eye) @ cam.f < 0.5 - np.linalg.norm(piece):
                        continue
                    sub = dict(part)
                    sub["p"] = centre.tolist()
                    sub["z"] = piece.tolist()
                    out.append(sub)
    return out


def render(parts, cam: Cam, out, title=None, show_text=True, ortho=None):
    img = np.zeros((H, W, 3))
    # sky gradient
    sky_top, sky_bot = np.array([0.42,0.66,0.95]), np.array([0.80,0.90,1.0])
    t = np.linspace(0,1,H)[:,None]
    img[:] = (sky_top*(1-t) + sky_bot*t)[:,None,:]
    zbuf = np.full((H, W), np.inf)
    sun = np.array([0.4, 0.85, 0.3]); sun /= np.linalg.norm(sun)
    labels = []
    if ortho is None:
        parts = _split_near(parts, cam)
    for part in parts:
        if part.get("b") and show_text:
            labels.append(part)
        if part["s"] == "None" or part["t"] >= 0.6:
            continue
        mesh = MESHES.get(part["s"], MESHES["Block"])
        size = np.array(part["z"]); 
        if part["s"] == "Egg": size = size*np.array([1,1.3,1])
        R = np.array(part["r"]).reshape(3,3)  # rows: right, up, back(-look)
        pos = np.array(part["p"])
        verts = (mesh*size) @ R + pos   # (T,3,3)
        col = np.array(part["c"])
        neon = part["m"] == "Neon"
        e1 = verts[:,1]-verts[:,0]; e2 = verts[:,2]-verts[:,0]
        nrm = np.cross(e1, e2); ln = np.linalg.norm(nrm,axis=1,keepdims=True); ln[ln==0]=1; nrm/=ln
        flat = verts.reshape(-1,3)
        if ortho is None:
            x,y,z = cam.project(flat)
            z = z.reshape(-1,3)
            if np.all(z < 0.5): continue
            sx = (W/2 + cam.k*x/np.maximum(z.ravel(),0.5)).reshape(-1,3)
            sy = (H/2 - cam.k*y/np.maximum(z.ravel(),0.5)).reshape(-1,3)
        else:
            cx, cz, scale = ortho
            sx = (W/2 + (flat[:,0]-cx)*scale).reshape(-1,3)
            sy = (H/2 + (flat[:,2]-cz)*scale).reshape(-1,3)
            z = (1000 - flat[:,1]).reshape(-1,3)
        for i in range(len(verts)):
            zi = z[i]
            if ortho is None and np.any(zi < 0.5): continue
            xs, ys = sx[i], sy[i]
            minx, maxx = int(max(math.floor(xs.min()),0)), int(min(math.ceil(xs.max()),W-1))
            miny, maxy = int(max(math.floor(ys.min()),0)), int(min(math.ceil(ys.max()),H-1))
            if minx > maxx or miny > maxy: continue
            if (maxx-minx)*(maxy-miny) > 4_000_000: continue
            n = nrm[i]
            if ortho is None:
                if np.dot(n, verts[i].mean(0)-cam.eye) > 0: n = -n
            shade = 1.0 if neon else 0.55 + 0.45*max(0.0, float(np.dot(n, sun)))
            c = np.clip(col*shade*(1.25 if neon else 1.0), 0, 1)
            gx, gy = np.meshgrid(np.arange(minx, maxx+1)+0.5, np.arange(miny, maxy+1)+0.5)
            x0,x1,x2 = xs; y0,y1,y2 = ys
            den = (y1-y2)*(x0-x2)+(x2-x1)*(y0-y2)
            if abs(den) < 1e-9: continue
            a = ((y1-y2)*(gx-x2)+(x2-x1)*(gy-y2))/den
            b = ((y2-y0)*(gx-x2)+(x0-x2)*(gy-y2))/den
            g = 1-a-b
            m = (a>=0)&(b>=0)&(g>=0)
            if not m.any(): continue
            if ortho is None:
                inv = a/zi[0]+b/zi[1]+g/zi[2]
                depth = 1/np.where(inv>0, inv, 1e-9)
            else:
                depth = a*zi[0]+b*zi[1]+g*zi[2]
            sub = zbuf[miny:maxy+1, minx:maxx+1]
            m &= depth < sub
            if not m.any(): continue
            sub[m] = depth[m]
            if ortho is None:
                fog = np.clip((depth[m]-120)/700, 0, 0.75)[:,None]
                img[miny:maxy+1, minx:maxx+1][m] = c*(1-fog) + sky_bot*fog
            else:
                img[miny:maxy+1, minx:maxx+1][m] = c
    out_img = Image.fromarray((np.clip(img,0,1)*255).astype(np.uint8))
    draw = ImageDraw.Draw(out_img)
    if show_text and ortho is None:
        try:
            font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
            ImageFont.truetype(font_path, 12)
        except Exception:
            font_path = None
        for part in labels:
            text, offy, maxd, sx_, sy_ = part["b"]
            pos = np.array(part["p"]) + np.array([0, offy, 0])
            dist = np.linalg.norm(pos - cam.eye)
            if dist > maxd: continue
            x,y,z = cam.project(pos[None,:])
            if z[0] < 1: continue
            px = W/2 + cam.k*x[0]/z[0]; py = H/2 - cam.k*y[0]/z[0]
            # occlusion test vs zbuffer
            ix, iy = int(px), int(py)
            if 0 <= ix < W and 0 <= iy < H and zbuf[iy, ix] < z[0] - 2: continue
            text = re.sub(r"[^\x00-ɏ\n ·—+%/()]", "", text).strip()
            if not text: continue
            lines = text.split("\n")
            box_h = cam.k*sy_/z[0]
            fs = max(6, min(64, int(box_h/len(lines)*0.8)))
            font = ImageFont.truetype(font_path, fs) if font_path else ImageFont.load_default()
            col = tuple(int(v*255) for v in part["c"])
            for li, line in enumerate(lines):
                ty = py - box_h/2 + li*box_h/len(lines)
                draw.text((px, ty), line, fill=col, font=font, anchor="mt", stroke_width=max(1, fs//8), stroke_fill=(0,0,0))
    if title:
        draw.rectangle([0,0,W,26], fill=(0,0,0))
        draw.text((10,5), title, fill=(255,255,255))
    out_img.save(out)

if __name__ == "__main__":
    import os
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "build", "map_parts.json")
    out_prefix = sys.argv[2] if len(sys.argv) > 2 else os.path.join(root, "build", "render", "mapa")
    label = sys.argv[3] if len(sys.argv) > 3 else "Power Clicker"
    os.makedirs(os.path.dirname(out_prefix) or ".", exist_ok=True)
    parts, meta = load(src)
    sx, sy, sz, lx, ly, lz = meta["spawn"]
    look = np.array([lx, 0, lz], float); look /= np.linalg.norm(look)
    char = np.array([sx, sy, sz])
    eye = char - look*16 + np.array([0, 7, 0])
    render(parts, Cam(eye, char + look*40 + np.array([0, 2, 0])), out_prefix + "_spawn.png", f"{label} - vista ao nascer (camera atras do personagem)")
    render(parts, Cam([-105, 95, 105], [70, 0, -25], fov=62), out_prefix + "_overview.png", f"{label} - visao geral do lobby")
    render(parts, Cam([60, 12, 10], [200, 14, 0], fov=70), out_prefix + "_gate.png", f"{label} - chegando na entrada do Caminho")
    render(parts, None, out_prefix + "_top.png", f"{label} - planta (vista de cima)", show_text=False, ortho=(60, 0, 2.0))
    # Estação de Melhorias (protótipo "máquina"): longe / média / perto, de
    # quem chega pela praça (a máquina olha para a origem).
    machine = next((p for p in parts if p["n"] == "Station_Upgrades"), None)
    if machine:
        mx, _, mz = machine["p"]
        d = np.array([-mx, 0, -mz], float); d /= np.linalg.norm(d)
        side = np.array([d[2], 0, -d[0]])
        target = np.array([mx, 8, mz])
        for name, dist, height, fov in (("far", 70, 9, 55), ("mid", 32, 7, 60), ("near", 15, 6.5, 70)):
            eye = target + d * dist + side * dist * 0.18 + np.array([0, height - 8, 0])
            render(parts, Cam(eye, target - np.array([0, 1.5 if name == "near" else 0, 0]), fov=fov), out_prefix + f"_upgrades_{name}.png", f"{label} - Melhorias ({name}: {dist} studs)")
        # 3/4 lateral próxima: para julgar a profundidade (colunas, núcleo,
        # anéis, console e o encaixe da base no chão).
        eye = target + d * 11 + side * 11 + np.array([0, -1.5, 0])
        render(parts, Cam(eye, target + np.array([0, -1.5, 0]) - side * 1.0, fov=68), out_prefix + "_upgrades_side.png", f"{label} - Melhorias (3/4 lateral, ~15 studs)")
    # Estações do lobby (perto e 3/4): peça de referência, lado de onde se
    # chega (direção "frente" no chão) e altura do alvo.
    def station_views(key, anchor, front, height, dist):
        part = next((p for p in parts if p["n"] == anchor), None)
        if not part:
            return
        f = np.array([front[0], 0, front[1]], float); f /= np.linalg.norm(f)
        side = np.array([f[2], 0, -f[0]])
        target = np.array([part["p"][0], height, part["p"][2]])
        render(parts, Cam(target + f * dist + np.array([0, -1.5, 0]), target, fov=68), out_prefix + f"_{key}_near.png", f"{label} - {key} (perto)")
        render(parts, Cam(target + f * dist * 0.75 + side * dist * 0.75 + np.array([0, -1, 0]), target - side * 1.0, fov=68), out_prefix + f"_{key}_side.png", f"{label} - {key} (3/4)")
    station_views("cuts", "ForgeBack", (0, 1), 7, 24)
    pets = next((p for p in parts if p["n"] == "Station_Pets"), None)
    if pets:
        station_views("pets", "LabWall", (-pets["p"][0], -pets["p"][2]), 5, 22)
    altar = next((p for p in parts if p["n"] == "RebirthCore"), None)
    if altar:
        station_views("rebirth", "RebirthCore", (-altar["p"][0], -altar["p"][2]), 7, 26)
    # Campo de Treinamento: entrada, os quatro juntos, cada alvo (de frente,
    # de onde se chega), lateral e aérea.
    gate = next((p for p in parts if p["n"] == "FieldGateBeam"), None)
    if gate:
        gx, _, gz = gate["p"]
        centre = np.array([gx, 0, gz + 23 - 1.2])
        render(parts, Cam([gx - 6, 6, gz - 16], [gx, 5, gz + 14], fov=70), out_prefix + "_training_1_entrance.png", f"{label} - Treino: entrada")
        render(parts, Cam(centre + np.array([0, 13, -36]), centre + np.array([0, 3, 2]), fov=66), out_prefix + "_training_2_all.png", f"{label} - Treino: os quatro alvos")
        for index, (name, title) in enumerate((("Dummy", "I Boneco de Treino"), ("Scarecrow", "II Espantalho Reforcado"), ("Warrior", "III Guerreiro de Treino"), ("Guardian", "IV Guardiao de Poder"))):
            plaque = next((p for p in parts if p["n"] == f"TrainingPlaque_{name}"), None)
            if not plaque:
                continue
            px, _, pz = plaque["p"]
            focus = np.array([gx, 0, gz - 8])
            f = focus - np.array([px, 0, pz]); f /= np.linalg.norm(f)
            target = np.array([px, 4.5, pz]) - f * 3
            render(parts, Cam(target + f * 15 + np.array([0, 1.5, 0]) + np.array([f[2], 0, -f[0]]) * 3, target, fov=62), out_prefix + f"_training_{index + 3}_{name.lower()}.png", f"{label} - Treino {title}")
        render(parts, Cam(centre + np.array([-34, 7, 8]), centre + np.array([4, 4, 2]), fov=66), out_prefix + "_training_7_side.png", f"{label} - Treino: lateral")
        render(parts, Cam(centre + np.array([-6, 52, -30]), centre + np.array([0, 0, 2]), fov=60), out_prefix + "_training_8_aerial.png", f"{label} - Treino: aerea")
    station_views("eggs", "EggHeaderStone", (0, 1), 8, 84)
    # Missões e Prêmios (área "Spawn" do LobbyConfig, em z = 92): chegando
    # pela calçada da praça, de frente, 3/4 e aérea.
    rz = 92
    render(parts, Cam([4, 6, rz - 44], [0, 6, rz], fov=68), out_prefix + "_rewards_1_arrival.png", f"{label} - Missoes/Premios: chegando")
    render(parts, Cam([0, 9, rz - 26], [0, 5, rz + 2], fov=72), out_prefix + "_rewards_2_front.png", f"{label} - Missoes/Premios: frente")
    render(parts, Cam([30, 9, rz - 20], [-4, 4, rz + 2], fov=68), out_prefix + "_rewards_3_side.png", f"{label} - Missoes/Premios: 3/4")
    render(parts, Cam([0, 62, rz - 30], [0, 0, rz], fov=62), out_prefix + "_rewards_4_aerial.png", f"{label} - Missoes/Premios: aerea")
    render(parts, Cam([-12, 5.5, rz - 12], [-19, 3.5, rz + 2], fov=62), out_prefix + "_rewards_6_chest.png", f"{label} - Premios de perto")
    # Circulação lateral: na altura do olho, cruzando a praça entre as áreas.
    render(parts, Cam([-30, 6, 70], [60, 4, -40], fov=72), out_prefix + "_circulation.png", f"{label} - circulacao lateral (altura do jogador)")
    print("renders em " + out_prefix + "_{spawn,overview,gate,top,upgrades_*,<estação>_*}.png")
