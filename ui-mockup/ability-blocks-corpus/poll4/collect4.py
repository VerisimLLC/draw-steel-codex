# Steel Compendium markdown for every class and kit ability (SteelCompendium/data-md, Rules/Abilities),
# paired by name with the same ability in our compendium data (draw-steel-data), where one exists.
import os, re, json, sys, yaml
MD = sys.argv[1] if len(sys.argv) > 1 else "data-md"
ROOT = "/home/user/verisimllc/draw-steel-data/objectTables"
L = yaml.CSafeLoader
def load(p):
    t = open(p, encoding="utf-8").read(); t = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', ' ', t)
    return yaml.load(t, Loader=L)
ours = {}
def walk(o, where):
    if isinstance(o, dict):
        if o.get("__typeName") == "ActivatedAbility" and o.get("name"):
            ours.setdefault(norm(o["name"]), []).append(dict(where=where, rec=o)); return
        for v in o.values(): walk(v, where)
    elif isinstance(o, list):
        for v in o: walk(v, where)
def norm(n): return re.sub(r'[^a-z0-9]', '', n.lower().replace("’", "'"))
for tbl in ("classes", "subclasses", "kits"):
    for fn in sorted(os.listdir(os.path.join(ROOT, tbl))):
        if fn.endswith(".yaml") and not fn.startswith("_"):
            d = load(os.path.join(ROOT, tbl, fn))
            if isinstance(d, dict) and not d.get("hidden"): walk(d, tbl + "/" + fn)
out = []
base = os.path.join(MD, "Rules", "Abilities")
for dp, _, fns in os.walk(base):
    for fn in sorted(fns):
        if not fn.endswith(".md"): continue
        p = os.path.join(dp, fn); text = open(p, encoding="utf-8").read()
        fm = yaml.load(text.split("---")[1], Loader=L) if text.startswith("---") else {}
        name = fm.get("file_basename") or fn[:-3]
        mine = ours.get(norm(name), [])
        out.append(dict(file=os.path.relpath(p, base), name=name, cls=fm.get("class"), level=fm.get("level"),
                        md=text, ours=mine[0]["rec"] if mine else None, oursWhere=mine[0]["where"] if mine else None, oursCount=len(mine)))
json.dump(out, open("md_all.json", "w"), default=str)
print(len(out), "pages;", sum(1 for r in out if r["ours"]), "matched to our data")
