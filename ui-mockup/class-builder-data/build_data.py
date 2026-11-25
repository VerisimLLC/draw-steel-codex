# Builds the class builder's lookup tables from the compendium export (draw-steel-data):
#   ../class-builder/tables.js   names and ids the sentences pick from (skills, languages, conditions...)
import yaml, re, os, json
D = "/home/user/verisimllc/draw-steel-data/objectTables"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "class-builder")
L = getattr(yaml, "CSafeLoader", yaml.SafeLoader)
def load(p):
    t = open(p, encoding="utf-8").read(); t = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', ' ', t)
    return yaml.load(t, Loader=L)
def rows(tbl):
    for fn in sorted(os.listdir(os.path.join(D, tbl))):
        if fn.endswith(".yaml") and not fn.startswith("_"):
            d = load(os.path.join(D, tbl, fn))
            if isinstance(d, dict) and not d.get("hidden"): yield d
tables = {
    "skills": sorted([[r["id"], r["name"], r.get("category", "")] for r in rows("skills")], key=lambda x: x[1]),
    "languages": sorted([[r["id"], r["name"]] for r in rows("languages")], key=lambda x: x[1]),
    "conditions": sorted([[r["id"], r["name"]] for r in rows("charconditions")], key=lambda x: x[1]),
    "damageTypes": sorted([r["name"].lower() for r in rows("damagetypes") if r["name"].lower() != "untyped"]),
    "customAttributes": sorted([[r["id"], r["name"], r.get("category", "")] for r in rows("customattributes")], key=lambda x: x[1]),
    # Ongoing effects, for "has the [ ] effect" tests (searched by name; 1,000+ of them).
    "effects": sorted({r["name"]: [r.get("id", ""), r["name"]] for r in rows("characterongoingeffects") if r.get("name")}.values(), key=lambda x: x[1].lower()),
    "resources": sorted([[r["id"], r["name"], r.get("grouping", "")] for r in rows("characterresources")], key=lambda x: x[1]),
    # Classes and their subclasses, so a class can list and link the subclasses that point at it.
    "classes": sorted([[r["id"], r["name"]] for r in rows("classes")], key=lambda x: x[1]),
    "subclasses": sorted([[r["id"], r["name"], r.get("primaryClassId", "")] for r in rows("subclasses")], key=lambda x: x[1]),
}
# Core classes the builder can open (records exactly as the compendium stores them), with every
# subclass that names them as parent. Opening one reads the records back into blocks.
CORE_CLASSES = ["Fury"]
core = {"classes": [], "subclasses": []}
for c in rows("classes"):
    if c.get("name") in CORE_CLASSES:
        core["classes"].append(c)
        core["subclasses"] += [x for x in rows("subclasses") if x.get("primaryClassId") == c["id"]]
open(os.path.join(OUT, "core-classes.js"), "w").write("window.CB_CORE = " + json.dumps(core, separators=(",", ":")) + ";\n")
print("core classes:", [c["name"] for c in core["classes"]], "subclasses:", [x["name"] for x in core["subclasses"]])
# Loaded with a <script> tag (works from a file:// page too): window.CB_TABLES = {...}
open(os.path.join(OUT, "tables.js"), "w").write("window.CB_TABLES = " + json.dumps(tables, separators=(",", ":")) + ";\n")
print({k: len(v) for k, v in tables.items()})
