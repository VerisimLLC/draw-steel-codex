import yaml, re, os, json, collections
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
for tbl in ("classes", "subclasses", "kits", "races", "titles"):
    for fn in os.listdir(os.path.join(D, tbl)):
        if fn.endswith(".yaml") and not fn.startswith("_"): walk(load(os.path.join(D, tbl, fn)))
def strip(o):
    if isinstance(o, dict): return {k: strip(v) for k, v in o.items() if k not in ("domains", "guid", "sourceguid", "source")}
    if isinstance(o, list): return [strip(x) for x in o]
    return o
def ex(pred, n=2):
    r = [strip(m) for m in mods if pred(m)][:n]
    for x in r: print(json.dumps(x)[:700])
print("--- power edge on tests w/ skills"); ex(lambda m: m.get("behavior") == "power" and m.get("rollType") == "test_power_roll" and m.get("modtype") == "edge" and m.get("skills"))
print("--- power damage"); ex(lambda m: m.get("behavior") == "power" and m.get("damageModifier") and m.get("modtype") == "none")
print("--- power bane enemy"); ex(lambda m: m.get("behavior") == "power" and m.get("rollType") == "enemy_ability_power_roll")
print("--- resistance"); ex(lambda m: m.get("behavior") == "resistance", 3)
print("--- language"); ex(lambda m: m.get("behavior") == "proficiency" and m.get("subtype") == "language", 1)
print("--- attribute speed"); ex(lambda m: m.get("behavior") == "attribute" and m.get("attribute") not in ("mgt","agl","rea","inu","prs"), 6)
print("--- modifyability range"); ex(lambda m: m.get("behavior") == "modifyability" and m.get("attributes"), 1)
attrs = collections.Counter(m.get("attribute") for m in mods if m.get("behavior") == "attribute")
print(attrs.most_common(40))
