# Every monster ability (top level, not nested follow-ups) and every monster trigger modifier.
import yaml, re, os, json
ROOT = "/home/user/verisimllc/draw-steel-data/monsters"
out = []
def load(p):
    t = open(p, encoding="utf-8").read(); t = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', ' ', t)
    return yaml.load(t, Loader=yaml.CSafeLoader)
for fn in sorted(os.listdir(ROOT)):
    if not fn.endswith(".yaml"): continue
    try: d = load(os.path.join(ROOT, fn))
    except Exception as e: continue
    if not isinstance(d, dict): continue
    info = d.get("info") or {}
    props = info.get("properties") or {}
    mname = d.get("description") or info.get("name") or props.get("monster_type") or fn
    level = props.get("cr") or props.get("level")
    def walk(o, path):
        if isinstance(o, dict):
            t = o.get("__typeName")
            if t == "ActivatedAbility":
                if o.get("name") not in (None, "", "New Ability", "Invoked Ability") and o.get("categorization") != "Hidden":
                    out.append(dict(monster=str(mname), level=level, file=fn, kind="ability", name=o.get("name"), rec=o))
                return
            if t == "CharacterModifier" and o.get("behavior") in ("trigger", "powertabletrigger"):
                ta = o.get("triggeredAbility") or {}
                out.append(dict(monster=str(mname), level=level, file=fn, kind=o.get("behavior"), name=o.get("name") or ta.get("name"), rec=o)); return
            for k, v in o.items(): walk(v, path + "/" + str(k))
        elif isinstance(o, list):
            for i, v in enumerate(o): walk(v, path + "[%d]" % i)
    walk(d, "")
json.dump(out, open("monsters_all.json", "w"), default=str)
import collections
print(len(out), collections.Counter(r["kind"] for r in out))
print(collections.Counter(str(r["level"]) for r in out).most_common(12))
print([ (r['monster'], r['name']) for r in out[:8]])
