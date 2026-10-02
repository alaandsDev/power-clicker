"""
build_place.py — builds build/PowerClicker.rbxlx from default.project.json + src/.

Fallback for machines without Rojo. Follows Rojo's file conventions:
  *.server.luau -> Script, *.client.luau -> LocalScript, *.luau -> ModuleScript,
  folder with init.luau -> ModuleScript (children nested), other folders -> Folder.

The recommended workflow is still Rojo (`rojo serve` + Studio plugin), which
syncs live. This script produces a standalone place for a quick open-and-play.

Usage:  python tools/build_place.py                (from the project root)
        python tools/build_place.py --studio-mock  (test build: DataConfig.StudioBackend
                                                    = "Mock" in the OUTPUT only; source
                                                    files are never modified)
"""

from __future__ import annotations

import json
import os
import sys
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = os.path.join(ROOT, "default.project.json")
OUT_DIR = os.path.join(ROOT, "build")
OUT_FILE = os.path.join(OUT_DIR, "PowerClicker.rbxlx")
STUDIO_MOCK = "--studio-mock" in sys.argv
if STUDIO_MOCK:
    OUT_FILE = os.path.join(OUT_DIR, "PowerClicker_StudioMock.rbxlx")

_ref = 0


def next_ref() -> str:
    global _ref
    _ref += 1
    return f"RBX{_ref:08X}"


def cdata(text: str) -> str:
    # "]]>" cannot appear inside CDATA; split it across two sections.
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


class Node:
    def __init__(self, class_name: str, name: str, source: str | None = None, props: str = ""):
        self.class_name = class_name
        self.name = name
        self.source = source
        self.props = props
        self.children: list[Node] = []

    def to_xml(self, indent: int = 1) -> str:
        pad = "\t" * indent
        parts = [f'{pad}<Item class="{self.class_name}" referent="{next_ref()}">', f"{pad}\t<Properties>"]
        parts.append(f'{pad}\t\t<string name="Name">{escape(self.name)}</string>')
        if self.source is not None:
            parts.append(f'{pad}\t\t<ProtectedString name="Source">{cdata(self.source)}</ProtectedString>')
        if self.props:
            parts.append(self.props)
        parts.append(f"{pad}\t</Properties>")
        for child in self.children:
            parts.append(child.to_xml(indent + 1))
        parts.append(f"{pad}</Item>")
        return "\n".join(parts)


def read(path: str) -> str:
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def script_node(file_name: str, path: str) -> Node | None:
    for suffix, class_name in ((".server.luau", "Script"), (".client.luau", "LocalScript"), (".luau", "ModuleScript")):
        if file_name.endswith(suffix):
            source = read(path)
            if STUDIO_MOCK and file_name == "DataConfig.luau":
                patched = source.replace('StudioBackend = "Real"', 'StudioBackend = "Mock"')
                assert patched != source, "StudioBackend line not found in DataConfig"
                source = patched
            return Node(class_name, file_name[: -len(suffix)], source)
    return None


def dir_node(name: str, path: str) -> Node:
    entries = sorted(os.listdir(path))
    init_file = next((e for e in entries if e in ("init.luau", "init.server.luau", "init.client.luau")), None)
    if init_file:
        node = script_node(init_file, os.path.join(path, init_file))
        assert node is not None
        node.name = name
    else:
        node = Node("Folder", name)
    for entry in entries:
        if entry == init_file:
            continue
        full = os.path.join(path, entry)
        if os.path.isdir(full):
            node.children.append(dir_node(entry, full))
        else:
            child = script_node(entry, full)
            if child:
                node.children.append(child)
    return node


def tree_node(name: str, spec: dict) -> Node:
    if "$path" in spec and os.path.isfile(os.path.join(ROOT, spec["$path"])):
        path = os.path.join(ROOT, spec["$path"])
        node = script_node(os.path.basename(path), path)
        assert node is not None, path
        node.name = name
    elif "$path" in spec:
        node = dir_node(name, os.path.join(ROOT, spec["$path"]))
    else:
        node = Node(spec.get("$className", "Folder"), name)
    for key, value in spec.items():
        if not key.startswith("$") and isinstance(value, dict):
            node.children.append(tree_node(key, value))
    return node


def part_props(size: tuple[float, float, float], position: tuple[float, float, float], color: int) -> str:
    sx, sy, sz = size
    x, y, z = position
    return (
        "\t\t\t\t<bool name=\"Anchored\">true</bool>\n"
        "\t\t\t\t<bool name=\"Locked\">true</bool>\n"
        f"\t\t\t\t<Vector3 name=\"size\"><X>{sx}</X><Y>{sy}</Y><Z>{sz}</Z></Vector3>\n"
        f"\t\t\t\t<CoordinateFrame name=\"CFrame\"><X>{x}</X><Y>{y}</Y><Z>{z}</Z>"
        "<R00>1</R00><R01>0</R01><R02>0</R02><R10>0</R10><R11>1</R11><R12>0</R12>"
        "<R20>0</R20><R21>0</R21><R22>1</R22></CoordinateFrame>\n"
        f"\t\t\t\t<Color3uint8 name=\"Color3uint8\">{color}</Color3uint8>"
    )


def main() -> int:
    project = json.loads(read(PROJECT))
    services = []
    for name, spec in project["tree"].items():
        if name.startswith("$"):
            continue
        node = tree_node(name, spec)
        # Workspace needs no static parts: WorldService/WorldBuilder generate every
        # enabled world (ground, SpawnLocation, stations) at server start.
        services.append(node)

    body = "\n".join(s.to_xml() for s in services)
    # Full root tag, exactly as Studio writes it: Open Cloud's place upload
    # rejects the short form ("Invalid Content stream").
    root = (
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" '
        'version="4">'
    )
    xml = f"{root}\n{body}\n</roblox>\n"
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(OUT_FILE, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(xml)

    count = xml.count("<Item ")
    print(f"Built {os.path.relpath(OUT_FILE, ROOT)} ({count} instances)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
