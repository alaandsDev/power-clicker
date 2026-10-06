"""Folhas de poses do golpe (vista de trás antes/depois, frente e lado) a partir de tools/lune/swing_poses.luau."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_map3d as R
from PIL import Image, ImageDraw
S = sys.argv[1]
before = json.load(open(f'{S}/before.json'))['poses']
after = json.load(open(f'{S}/after.json'))['poses']
ground = {'c': [0.45, 0.5, 0.45], 'l': False, 'm': 'Grass', 'n': 'G', 'p': [0, -0.5, 0], 'r': [1,0,0,0,1,0,0,0,1], 's': 'Block', 't': 0, 'z': [40, 1, 40]}
order = ['STANCE', 'A PREP', 'A HIT', 'A REC', 'B PREP', 'B HIT', 'C PREP', 'C HIT']
views = {'atras (camera do jogador)': ([0, 6.5, 11], [0, 3.2, -6]), 'frente': ([0, 4.5, -10], [0, 3, 0]), 'lado': ([11, 4.5, -1], [0, 3, -1])}
W2, H2 = 300, 330
def panel(parts, eye, tgt):
    R.render(parts + [ground], R.Cam(eye, tgt, fov=50), f'{S}/_p.png', None, show_text=False)
    return Image.open(f'{S}/_p.png').resize((W2, H2))
for vname, (eye, tgt) in views.items():
    rows = [('ANTES', before), ('DEPOIS', after)] if vname.startswith('atras') else [('DEPOIS', after)]
    sheet = Image.new('RGB', (W2 * len(order), (H2 + 22) * len(rows) + 24), (20, 20, 28))
    d = ImageDraw.Draw(sheet)
    d.text((8, 4), f'Golpe da espada - vista {vname}', fill=(255, 255, 255))
    for ri, (label, poses) in enumerate(rows):
        for ci, name in enumerate(order):
            img = panel(poses[name], eye, tgt)
            y = 24 + ri * (H2 + 22)
            sheet.paste(img, (ci * W2, y + 18))
            d.text((ci * W2 + 6, y + 2), f'{label}: {name}', fill=(255, 230, 160))
    key = vname.split()[0]
    sheet.save(f'{S}/poses_{key}.png')
os.remove(f'{S}/_p.png')
print('ok')
