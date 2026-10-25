"""Validate the development mod without launching or changing Civilization VI."""

from __future__ import annotations

import argparse
import json
from pathlib import Path, PurePosixPath
import re
import sys
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "HLS_Dev"
DEFAULT_GAME = Path(r"C:\Program Files (x86)\Steam\steamapps\common\Sid Meier's Civilization VI")
DEPENDENCIES = {"4873eb62-8ccc-4574-b784-dda455e74e68", "8424840c-92ef-4426-a9b4-b4e0cb818049"}
ENGINE_ROOTS = {
    "Game", "GameInfo", "Players", "PlayerManager", "UnitManager", "GameConfiguration",
    "PlayerConfigurations", "Locale", "UI", "UIManager", "ContextPtr", "Controls",
    "Events", "LuaEvents", "GameEvents", "Modding", "Input", "UnitPropertyKeys",
    "InstanceManager", "Keys", "Mouse", "KeyEvents", "CityManager",
}
CALL = re.compile(r"\b([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)([:.])([A-Za-z_]\w*)\s*\(")
LOC = re.compile(r"\bLOC_HLS_[A-Za-z0-9_]+\b")


def strip_lua_comments_and_strings(source: str) -> str:
    """Preserve newlines while hiding quoted strings and Lua comments for call scanning."""
    token = re.compile(r"--\[(=*)\[.*?\]\1\]|--[^\n]*|'(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\"|\[(=*)\[.*?\]\2\]", re.S)
    return token.sub(lambda match: "\n" * match.group(0).count("\n") + " ", source)


def engine_calls(source: str) -> set[str]:
    clean = strip_lua_comments_and_strings(source)
    calls = {":" + method for method in re.findall(r":\s*([A-Za-z_]\w*)\s*\(", clean)}
    for match in CALL.finditer(clean):
        receiver, separator, method = match.groups()
        if separator == "." and receiver.split(".")[0] in ENGINE_ROOTS:
            calls.add(receiver + "." + method)
    return calls


def validate(game_root: Path) -> list[str]:
    errors: list[str] = []
    lua_files = sorted(MOD.rglob("*.lua"))
    if not lua_files:
        errors.append("No development Lua payload found.")
    try:
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True)
        compile_lua = lua.eval("function(code,name) local fn,err=loadstring(code,name); return fn ~= nil,err end")
        for path in lua_files:
            valid, error = compile_lua(path.read_text(encoding="utf-8-sig"), "@" + path.as_posix())
            if not valid:
                errors.append(f"Lua 5.1 syntax {path.relative_to(ROOT)}: {error}")
    except ImportError:
        errors.append("Install lupa with Lua 5.1 support (python -m pip install lupa); lupa.lua51 is required.")

    xml_files = sorted(MOD.rglob("*.xml")) + sorted(MOD.glob("*.modinfo"))
    parsed: dict[Path, ET.Element] = {}
    for path in xml_files:
        try:
            parsed[path] = ET.parse(path).getroot()
        except ET.ParseError as exc:
            errors.append(f"XML {path.relative_to(ROOT)}: {exc}")
    manifest_path = MOD / "HLS_Dev.modinfo"
    manifest = parsed.get(manifest_path)
    if manifest is None:
        errors.append("HLS_Dev/HLS_Dev.modinfo is missing or invalid.")
    else:
        if manifest.findtext("Properties/AffectsSavedGames") != "0":
            errors.append("Development kit must declare the chosen AffectsSavedGames=0 opt-out; runtime S4 remains separate.")
        dependencies = {node.get("id", "").lower() for node in manifest.findall("Dependencies/Mod")}
        if dependencies != DEPENDENCIES:
            errors.append("Manifest dependencies must exactly name the installed Babylon and Gathering Storm IDs.")
        entries = [(node.text or "").strip().replace("\\", "/") for node in manifest.findall("Files/File")]
        if len(entries) != len(set(name.lower() for name in entries)):
            errors.append("Manifest contains duplicate payload paths (case insensitive).")
        for name in entries:
            rel = PurePosixPath(name)
            if not name or rel.is_absolute() or ".." in rel.parts or ":" in name:
                errors.append(f"Unsafe manifest path: {name!r}")
            elif not (MOD / name).is_file():
                errors.append(f"Missing manifest file: {name}")
        actual = {p.relative_to(MOD).as_posix() for p in MOD.rglob("*") if p.is_file() and p != manifest_path}
        if actual != set(entries):
            errors.append(f"Payload/manifest mismatch: unlisted={sorted(actual-set(entries))}, missing={sorted(set(entries)-actual)}")
        criteria = {node.get("id"): node for node in manifest.findall("ActionCriteria/Criteria")}
        for action in manifest.findall("InGameActions/*"):
            if action.tag not in {"ImportFiles", "AddUserInterfaces", "ReplaceUIScript", "UpdateText", "AddGameplayScripts"}:
                errors.append(f"Development kit contains unapproved action: {action.tag}")
            criterion = criteria.get(action.get("criteria"))
            if criterion is None:
                errors.append(f"Action {action.get('id')} must reference a mode/ruleset criterion.")
            else:
                mode = criterion.find("ConfigurationValueMatches")
                if criterion.findtext("RuleSetInUse") != "RULESET_EXPANSION_2" or mode is None or (
                    mode.findtext("Group"), mode.findtext("ConfigurationId"), mode.findtext("Value")
                ) != ("Game", "GAMEMODE_HEROES", "1"):
                    errors.append(f"Action criterion {action.get('criteria')} must require GS plus Heroes & Legends.")
            for node in action.findall("File"):
                if (node.text or "").strip().replace("\\", "/") not in entries:
                    errors.append(f"Action payload is not in Files: {node.text}")
            replacement = action.findtext("Properties/LuaReplace")
            if replacement and replacement.replace("\\", "/") not in entries:
                errors.append(f"LuaReplace is not in Files: {replacement}")

    declared = set()
    for tree in parsed.values():
        declared.update(node.get("id", "") for node in tree.findall("LocalizedText/Text"))
        declared.update(node.get("Tag", "") for node in tree.findall(".//LocalizedText/Row"))
        declared.update(node.findtext("Tag", "") for node in tree.findall(".//LocalizedText/Row"))
    referenced = set()
    for path in lua_files + xml_files:
        referenced.update(LOC.findall(path.read_text(encoding="utf-8-sig")))
    for key in sorted(referenced - declared):
        errors.append(f"Missing localization declaration: {key}")

    allowlist_path = ROOT / "tools" / "api_allowlist.json"
    if not allowlist_path.is_file():
        errors.append("tools/api_allowlist.json is missing.")
    else:
        evidence = json.loads(allowlist_path.read_text(encoding="utf-8"))
        all_calls = set().union(*(engine_calls(p.read_text(encoding="utf-8-sig")) for p in lua_files))
        for call in sorted(all_calls):
            records = evidence.get(call)
            if not records:
                errors.append(f"Engine API lacks source evidence: {call}")
                continue
            for record in records:
                if not all(record.get(field) for field in ("source", "line", "excerpt", "context")):
                    errors.append(f"Incomplete API evidence: {call}")
                    continue
                path = game_root / record["source"] if record.get("root", "game") == "game" else Path(record["source"])
                if not path.is_file():
                    errors.append(f"API evidence source missing for {call}: {path}")
                    continue
                lines = path.read_text(encoding="utf-8-sig", errors="replace").splitlines()
                line = record["line"]
                if not isinstance(line, int) or not 1 <= line <= len(lines) or record["excerpt"] not in lines[line - 1]:
                    errors.append(f"API evidence has drifted for {call}: {path}:{line}")
        print(f"API audit: {len(all_calls)} source-backed call signatures")
    print(f"Payload: {len(lua_files)} Lua files, {len(xml_files)} XML/manifest files")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-root", type=Path, default=DEFAULT_GAME)
    args = parser.parse_args()
    errors = validate(args.game_root)
    for error in errors:
        print("FAIL: " + error)
    if errors:
        return 1
    print("PASS: syntax, XML, manifest, localization and source evidence checks")
    return 0


if __name__ == "__main__":
    sys.exit(main())
