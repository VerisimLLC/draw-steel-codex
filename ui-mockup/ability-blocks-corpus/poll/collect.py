# Collect every class/subclass ability with its class, level and kind.
import yaml, re, os, json, sys
ROOT = "/home/user/verisimllc/draw-steel-data/objectTables"
L = yaml.CSafeLoader
out = []
def load(p):
    t = open(p, encoding="utf-8").read(); t = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', ' ', t)
    return yaml.load(t, Loader=L)
def lvl(path):
    m = re.search(r'levels/(tutorial)?level-(\d+)', path); return int(m.group(2)) if m else None
def walk(o, path, cls, sub, fname):
    if isinstance(o, dict):
        t = o.get("__typeName")
        if t == "ActivatedAbility" and o.get("categorization") in ("Signature Ability", "Heroic Ability", "Ability", "Trigger"):
            out.append(dict(cls=cls, sub=sub, file=fname, level=lvl(path), kind="ability", cat=o.get("categorization"), name=o.get("name"), rec=o)); return
        if t == "CharacterModifier" and o.get("behavior") in ("trigger", "powertabletrigger"):
            ta = o.get("triggeredAbility") or {}
            nm = o.get("name") or ta.get("name")
            out.append(dict(cls=cls, sub=sub, file=fname, level=lvl(path), kind=o.get("behavior"), cat="Triggered", name=nm, rec=o)); return
        for k, v in o.items(): walk(v, path + "/" + str(k), cls, sub, fname)
    elif isinstance(o, list):
        for i, v in enumerate(o): walk(v, path + "[" + str(i) + "]", cls, sub, fname)
for tbl in ("classes", "subclasses"):
    for fn in sorted(os.listdir(os.path.join(ROOT, tbl))):
        if not fn.endswith(".yaml") or fn.startswith("_"): continue
        d = load(os.path.join(ROOT, tbl, fn))
        if not isinstance(d, dict): continue
        if d.get("hidden"): continue
        walk(d, "", d.get("name"), tbl == "subclasses", tbl + "/" + fn)
json.dump(out, open("all.json", "w"), default=str)
import collections
print(len(out)); print(collections.Counter((r["cls"] if not r["sub"] else "(sub)") for r in out)); print(collections.Counter(r["level"] for r in out)); print(collections.Counter(r["cat"] for r in out))
