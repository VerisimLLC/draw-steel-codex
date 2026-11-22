import yaml, re, os, json, collections
exec(open("coverage.py").read().split('print("== feature types')[0].replace("for src, d in recs:", "for src, d in []:"))
def find(pred, n=3):
    out = []
    def walk(o, src, feat):
        if isinstance(o, dict):
            if o.get("__typeName", "").startswith("Character") and o.get("__typeName") != "CharacterModifier": feat = o.get("name") or feat
            if pred(o): out.append((src, feat, o))
            for v in o.values(): walk(v, src, feat)
        elif isinstance(o, list):
            for v in o: walk(v, src, feat)
    for src, d in recs: walk(d.get("levels"), src, None)
    return out
def show(title, pred, n=2, keys=None, w=420):
    r = find(pred); print("==", title, len(r))
    for src, feat, o in r[:n]:
        oo = {k: v for k, v in o.items() if k not in ("domains", "guid", "sourceguid", "source", "classid", "display", "iconid")} if keys is None else {k: o.get(k) for k in keys}
        print("   ", src, "|", feat, "|", json.dumps(oo, default=str)[:w])
show("CharacterPrerequisite", lambda o: o.get("__typeName") == "CharacterPrerequisite", 3)
c = collections.Counter(json.dumps({k: v for k, v in o.items() if k in ("prereqType", "type", "attribute", "skill")}) for s, f, o in find(lambda o: o.get("__typeName") == "CharacterPrerequisite")); print("   kinds:", c.most_common(6))
show("CharacterOngoingEffect", lambda o: o.get("__typeName") == "CharacterOngoingEffect", 2, ["name", "description", "durationType", "modifiers"], 300)
show("CharacterAttribute", lambda o: o.get("__typeName") == "CharacterAttribute", 2)
show("CharacterResource", lambda o: o.get("__typeName") == "CharacterResource", 2, None, 300)
show("CharacterDeityChoice", lambda o: o.get("__typeName") == "CharacterDeityChoice", 1, None, 300)
show("CharacterCompanionChoice", lambda o: o.get("__typeName") == "CharacterCompanionChoice", 1, None, 300)
for b in ["aura", "modcompanion", "routine", "abilityimprovement", "modsummoner", "modifytrigger", "modifyresourcechecklist", "suppressabilities", "forcedmovement", "bestowcondition", "powertableadditional"]:
    show("behavior " + b, lambda o, b=b: o.get("__typeName") == "CharacterModifier" and o.get("behavior") == b, 1, None, 360)
rr = collections.Counter(o.get("resourceRefreshType") for s, f, o in find(lambda o: o.get("__typeName") == "CharacterModifier" and o.get("resourceRefreshType"))); print("== resourceRefreshType", rr)
rc = collections.Counter((o.get("resourceCostType"), o.get("resourceCostAmount")) for s, f, o in find(lambda o: o.get("behavior") == "power" and o.get("resourceCostType"))); print("== power resourceCost", rc.most_common(8))
mt = collections.Counter(o.get("modtype") for s, f, o in find(lambda o: o.get("behavior") == "power")); print("== power modtypes", mt.most_common())
rt = collections.Counter(o.get("rollType") for s, f, o in find(lambda o: o.get("behavior") == "power")); print("== power rollTypes", rt.most_common())
print("== abilityCategoryNames", [ (s, d.get("abilityCategoryNames")) for s, d in recs if d.get("abilityCategoryNames")][:3])
print("== subclass top fields", sorted({k for s, d in recs if s.startswith("sub:") for k in d}))
