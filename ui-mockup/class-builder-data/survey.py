# Survey modifier records in class/subclass/kit/ancestry/title data: per behaviour, the common field
# sets and values, so the class builder writes records shaped like real content.
import yaml, re, os, json, collections, sys
D = "/home/user/verisimllc/draw-steel-data/objectTables"
L = yaml.CSafeLoader
def load(p):
    t = open(p, encoding="utf-8").read(); t = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', ' ', t)
    return yaml.load(t, Loader=L)
mods = []
def walk(o):
    if isinstance(o, dict):
        if o.get("__typeName") == "CharacterModifier": mods.append(o)
        for v in o.values(): walk(v)
    elif isinstance(o, list):
        for v in o: walk(v)
for tbl in ("classes", "subclasses", "kits", "races", "titles", "feats"):
    for fn in os.listdir(os.path.join(D, tbl)):
        if fn.endswith(".yaml") and not fn.startswith("_"): walk(load(os.path.join(D, tbl, fn)))
by = collections.defaultdict(list)
for m in mods: by[m.get("behavior")].append(m)
SKIP = {"name", "description", "__typeName", "behavior", "source", "sourceguid", "guid", "domains"}
out = {}
for b, ms in sorted(by.items(), key=lambda x: -len(x[1])):
    keys = collections.Counter(k for m in ms for k in m if k not in SKIP)
    vals = {}
    for k, n in keys.most_common(14):
        c = collections.Counter(json.dumps(m[k], sort_keys=True)[:80] for m in ms if k in m)
        vals[k] = [n, c.most_common(8)]
    out[b] = {"count": len(ms), "fields": vals}
json.dump(out, open("survey.json", "w"), indent=1)
for b in list(out)[:24]: print(b, out[b]["count"], list(out[b]["fields"])[:12])
