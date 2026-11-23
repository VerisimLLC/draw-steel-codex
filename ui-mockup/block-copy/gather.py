import os, re, json
R = "/home/user/draw-steel-codex"
lua = {}
for dp, dn, fns in os.walk(R):
    if "/.git" in dp or "ui-mockup" in dp or "/Definitions" in dp: continue
    for f in fns:
        if f.endswith(".lua"): lua[os.path.relpath(os.path.join(dp, f), R)] = open(os.path.join(dp, f), encoding="utf-8", errors="replace").read()

# Behaviours: ActivatedAbility.RegisterType{ id = 'x', text = 'y', createBehavior = function() return Z.new
beh = {}
for path, s in lua.items():
    for m in re.finditer(r'ActivatedAbility\.RegisterType\s*\{?', s):
        chunk = s[m.end():m.end() + 900]
        idm = re.search(r'\bid\s*=\s*["\']([^"\']+)["\']', chunk); tx = re.search(r'\btext\s*=\s*["\']([^"\']+)["\']', chunk)
        cls = re.search(r'return\s+([A-Za-z_][A-Za-z0-9_]*)\.new', chunk)
        if idm: beh[idm.group(1)] = {"id": idm.group(1), "name": tx.group(1) if tx else "", "typeName": cls.group(1) if cls else "", "file": path}
# Modifiers
mods = {}; dereg = set()
for path, s in lua.items():
    for m in re.finditer(r'CharacterModifier\.RegisterType\s*\(\s*["\']([^"\']+)["\']\s*,\s*["\']([^"\']*)["\']', s):
        mods[m.group(1)] = {"id": m.group(1), "name": m.group(2), "file": path}
    for m in re.finditer(r'CharacterModifier\.DeregisterType\s*\(\s*["\']([^"\']+)["\']', s): dereg.add(m.group(1))
# Picker metadata
def meta(path, var):
    s = lua[path]; i = s.index(var); j = s.index("\n}", i); body = s[i:j]
    out = {}
    for m in re.finditer(r'\n\s{4}([A-Za-z_0-9]+)\s*=\s*\{(.*?)\n\s{4}\}', body, re.S):
        d = re.search(r'description\s*=\s*"((?:[^"\\]|\\.)*)"', m.group(2))
        out[m.group(1)] = d.group(1) if d else ""
    return out
bm = meta("Draw Steel Ability Editor/AbilityEditorBehaviorPicker.lua", "local BEHAVIOR_METADATA")
mm = meta("Draw Steel Ability Editor/AbilityEditorModifierPicker.lua", "local MODIFIER_METADATA")
# Prose templates and autoDescribe
gsp = set(re.findall(r'^BP\.([A-Za-z0-9_]+)\s*=', lua["DMHub Utils/GoblinScriptProse.lua"], re.M))
auto = set()
for path, s in lua.items():
    for m in re.finditer(r'CharacterModifier\.TypeInfo\.?\[?["\']?([A-Za-z_0-9]+)', s): pass
    for m in re.finditer(r'TypeInfo(?:\.|\[")([A-Za-z_0-9]+)"?\]?\s*=\s*\{(.*?)\n\}', s, re.S):
        if "autoDescribe" in m.group(2): auto.add(m.group(1))
json.dump({"beh": beh, "mods": mods, "dereg": sorted(dereg), "bm": bm, "mm": mm, "gsp": sorted(gsp), "auto": sorted(auto)}, open("lua.json", "w"), indent=1)
print(len(beh), "behaviours;", len(mods), "modifiers;", len(dereg), "deregistered;", len(bm), len(mm), "picker descs;", len(gsp), "prose;", len(auto), "autoDescribe", sorted(auto))
