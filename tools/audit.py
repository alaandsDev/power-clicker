"""
audit.py — static checks for the Power Clicker codebase (no Roblox needed).

  python tools/audit.py

Checks:
  1. every ClientToServer remote has exactly one server handler (On/OnInvoke)
  2. every ServerToClient remote is fired somewhere and listened to on the client
  3. no deprecated globals (wait/spawn/delay without task.)
  4. no print() outside Logger/TestRunner (use Logger)
  5. every Text.Get("literal") key exists in every locale
  6. services with per-player tables clean them up on PlayerRemoving
Exit code 1 if any check fails.
"""

from __future__ import annotations

import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")


def read(path: str) -> str:
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def lua_files() -> list[str]:
    return sorted(glob.glob(os.path.join(SRC, "**", "*.luau"), recursive=True))


def strip_comments(text: str) -> str:
    text = re.sub(r"--\[\[.*?\]\]", "", text, flags=re.S)
    return re.sub(r"--[^\n]*", "", text)


problems: list[str] = []
files = {path: read(path) for path in lua_files()}
code = {path: strip_comments(text) for path, text in files.items()}
rel = lambda p: os.path.relpath(p, ROOT)

# 1/2. Remotes
defs = read(os.path.join(SRC, "shared", "Net", "RemoteDefinitions.luau"))
remotes = re.findall(r"^\t(\w+) = \{[^\n]*?(?:\n\t\t[^\n]*)*?Direction = \"(\w+)\"", defs, flags=re.M)
if not remotes:
    problems.append("could not parse RemoteDefinitions")
server_code = "\n".join(t for p, t in code.items() if os.sep + "server" + os.sep in p)
client_code = "\n".join(t for p, t in code.items() if os.sep + "client" + os.sep in p)
for name, direction in remotes:
    if direction == "ClientToServer":
        handlers = len(re.findall(r'NetService\.(?:On|OnInvoke)\(\s*"' + name + '"', server_code))
        if handlers != 1:
            problems.append(f"remote {name}: expected 1 server handler, found {handlers}")
    else:
        if not re.search(r'Fire(?:Client|AllClients)\(\s*"' + name + '"', server_code):
            problems.append(f"remote {name}: never fired by the server")
        if not re.search(r'ClientNet\.On\(\s*"' + name + '"', client_code):
            problems.append(f"remote {name}: no client listener")

# 3/4. Deprecated globals and print
for path, text in code.items():
    for match in re.finditer(r"(?<![\w.:])(wait|spawn|delay)\s*\(", text):
        problems.append(f"{rel(path)}: deprecated global {match.group(1)}() (use task.*)")
    if not path.endswith(("Logger.luau", "TestRunner.luau")) and re.search(r"(?<![\w.:])print\s*\(", text):
        problems.append(f"{rel(path)}: print() outside Logger")

# 5. Localization keys
def locale_keys(name: str) -> set[str]:
    return set(re.findall(r'\["([^"]+)"\]\s*=', read(os.path.join(SRC, "shared", "Localization", "Strings", name))))

def locale_key_list(name: str) -> list[str]:
    return re.findall(r'\["([^"]+)"\]\s*=', read(os.path.join(SRC, "shared", "Localization", "Strings", name)))

# A duplicated key silently overrides the first one (Luau warns, but only in Studio).
for locale_file in ("ptBR.luau", "en.luau"):
    seen: dict[str, int] = {}
    for key in locale_key_list(locale_file):
        seen[key] = seen.get(key, 0) + 1
    for key, count in seen.items():
        if count > 1:
            problems.append(f"{locale_file}: duplicated string '{key}' ({count}x)")

locales = {"ptBR": locale_keys("ptBR.luau"), "en": locale_keys("en.luau")}
if locales["ptBR"] != locales["en"]:
    problems.append(f"locale key mismatch: {sorted(locales['ptBR'] ^ locales['en'])}")
for path, text in code.items():
    if path.endswith(".spec.luau"):
        continue
    # Only complete literals ("key") — dynamic keys ("prefix." .. id) are checked below.
    for key in re.findall(r'Text\.Get(?:For)?\((?:[^,()]+,\s*)?"([a-zA-Z][\w.]*)"\s*[,)]', text):
        for locale, keys in locales.items():
            if key not in keys:
                problems.append(f"{rel(path)}: missing {locale} string '{key}'")

# Dynamic key families: every config id needs its strings.
def config_ids(relpath: str, table: str) -> list[str]:
    text = read(os.path.join(SRC, "shared", "Config", relpath))
    block = text.split("local " + table, 1)[1] if ("local " + table) in text else text
    block = block.split("\n}\n", 1)[0]
    return re.findall(r"^\t(\w+) = [{p]", block, flags=re.M)

families = {
    "quest.{}.name": config_ids("QuestConfig.luau", "Quests"),
    "achievement.{}.name": config_ids("AchievementConfig.luau", "Achievements"),
    "achievement.{}.desc": config_ids("AchievementConfig.luau", "Achievements"),
    "pass.{}.name": config_ids("ProductConfig.luau", "GamePasses"),
    "pass.{}.desc": config_ids("ProductConfig.luau", "GamePasses"),
    "product.{}.name": config_ids("ProductConfig.luau", "DeveloperProducts"),
    "boost.{}.name": config_ids("BoostConfig.luau", "Boosts"),
    "settings.{}": ["SfxVolume", "MusicVolume", "ShowFloatingNumbers", "ReducedEffects"],
    "kick.{}": ["Failed", "Locked", "FutureVersion", "Corrupt", "Migration", "LockLost", "StudioHint"],
    "ranking.{}": ["Clicks", "Rebirths", "Power", "Wins"],
    "shop.tab{}": ["Offers", "Passes", "Products"],
}
for pattern, ids in families.items():
    if not ids:
        problems.append(f"could not read ids for {pattern}")
    for identifier in ids:
        key = pattern.format(identifier)
        for locale, keys in locales.items():
            if key not in keys:
                problems.append(f"missing {locale} string '{key}'")

# 6. Per-player tables are cleaned up
for path, text in code.items():
    if os.sep + "Services" + os.sep not in path:
        continue
    tables = re.findall(r"^local (\w+): \{ \[Player\]:", text, flags=re.M)
    for table in tables:
        cleaned = re.search(table + r"\[player\]\s*=\s*nil", text) or re.search(r"table\.clear\(" + table + r"\)", text)
        if not cleaned:
            problems.append(f"{rel(path)}: per-player table '{table}' is never cleared (leak on PlayerRemoving?)")

print(f"Audited {len(files)} files, {len(remotes)} remotes, {len(locales['ptBR'])} strings.")
if problems:
    print(f"{len(problems)} problem(s):")
    for problem in problems:
        print("  -", problem)
    sys.exit(1)
print("OK: no problems found.")
