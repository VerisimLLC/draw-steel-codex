"""Checks the Block Editor's UI module knows no game types or block ids.

The decision (BLOCK_EDITOR_FRAMEWORK.md ledger): every block, host and type is
declared beside the game types on the Block registries, and the UI in
"Block Editor/" only reads them. So its code (comments aside) must not name:
  * a game type registered with RegisterGameType (ActivatedAbility, ...);
  * a block, wrapper or host id registered with Block.Register... outside
    DMHub Utils/Block.lua (which holds the framework's own colour groups).
BlockEditorText.lua is skipped: it is only the words the UI shows.

Run from the codex root: python tools/block_editor/check_ui.py
Exits 1 and lists each line that names one.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
UI = ROOT / "Block Editor"
FRAMEWORK = ROOT / "DMHub Utils" / "Block.lua"
#game types that are engine services the UI is meant to use, not content.
ALLOWED_TYPES = {"ThemeEngine"}
SKIPPED = {"BlockEditorText.lua"}


def code_only(line):
    """The line without its comment (a -- outside a string)."""
    out, quote = [], None
    i = 0
    while i < len(line):
        ch = line[i]
        if quote:
            if ch == "\\":
                out.append(line[i:i + 2])
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
        elif line.startswith("--", i):
            break
        out.append(ch)
        i += 1
    return "".join(out)


def strip_block_comments(text):
    return re.sub(r"--\[(=*)\[.*?\]\1\]", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)


def main():
    type_names, ids = set(), set()
    for path in ROOT.rglob("*.lua"):
        if UI in path.parents or "Definitions" in path.parts or "tests" in path.parts:
            continue
        text = path.read_text(encoding="latin-1")
        type_names.update(re.findall(r'RegisterGameType\(\s*"([A-Za-z_][A-Za-z0-9_]*)"', text))
        if path == FRAMEWORK:
            continue
        for match in re.finditer(r"Block\.Register(\w*)\s*\{", text):
            found = re.search(r'\bid\s*=\s*"([^"]+)"', text[match.end():match.end() + 2000])
            #dotted ids are blocks and wrappers ("ability.damage"); hosts are flagged by any id.
            if found and ("." in found.group(1) or match.group(1) == "Host"):
                ids.add(found.group(1))
    type_names -= ALLOWED_TYPES
    type_pattern = re.compile(r"\b(" + "|".join(sorted(map(re.escape, type_names), key=len, reverse=True)) + r")\b")
    problems = []
    for path in sorted(UI.glob("*.lua")):
        if path.name in SKIPPED:
            continue
        lines = strip_block_comments(path.read_text(encoding="latin-1")).split("\n")
        for number, line in enumerate(lines, 1):
            code = code_only(line)
            for literal in re.findall(r'"([^"\\]*)"', code):
                if literal in ids:
                    problems.append(f'{path.relative_to(ROOT)}:{number}: names the registered id "{literal}"')
            for name in type_pattern.findall(re.sub(r'"[^"\\]*"', '""', code)):
                problems.append(f"{path.relative_to(ROOT)}:{number}: names the game type {name}")
            for literal in re.findall(r'"([^"\\]*)"', code):
                if literal in type_names:
                    problems.append(f'{path.relative_to(ROOT)}:{number}: names the game type "{literal}"')
    for problem in problems:
        print(problem)
    print(f"check_ui: {len(type_names)} game types and {len(ids)} block ids known; {len(problems)} problem(s) in Block Editor/")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
