# Every trigger (CharacterModifier "trigger" / "powertabletrigger") in class, subclass, kit, title, ancestry
# and monster data, with its Triggered Ability Display (matched by name in the same file, as the engine
# matches a display to its live partner) and printed text where it can be found.
import yaml, re, os, json, collections, sys
sys.path.insert(0, "../poll2")
D = "/home/user/verisimllc/draw-steel-data"
L = yaml.CSafeLoader
def load(p):
    t = open(p, encoding="utf-8").read(); t = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', ' ', t)
    return yaml.load(t, Loader=L)
# printed text helpers from the second poll
src2 = open("../poll2/sample2.py").read()
pre = src2.split("sample = []")[0]
pre = pre.replace('mon = json.load(open("monsters_all.json"))', 'mon = []').replace('cls = json.load(open("../poll/all.json"))', 'cls = []').replace('first = {r["name"] for r in json.load(open("../poll/sample.json"))}', 'first = set()')
pre = pre.replace('open("../poll/sample.py")', 'open("../poll/sample.py")')
os.chdir("../poll2"); exec(pre); os.chdir("../poll3")
out = []
for folder in ("objectTables/classes", "objectTables/subclasses", "objectTables/kits", "objectTables/titles", "objectTables/races", "monsters"):
    for fn in sorted(os.listdir(os.path.join(D, folder))):
        if not fn.endswith(".yaml") or fn.startswith("_"): continue
        try: d = load(os.path.join(D, folder, fn))
        except Exception: continue
        if not isinstance(d, dict): continue
        owner = d.get("name") or d.get("description") or fn
        trigs, disps = [], {}
        def walk(o):
            if isinstance(o, dict):
                if o.get("__typeName") == "CharacterModifier":
                    b = o.get("behavior")
                    if b in ("trigger", "powertabletrigger"): trigs.append(o)
                    elif b == "triggerdisplay": disps.setdefault(str((o.get("ability") or {}).get("name") or o.get("name") or "").strip().lower(), o)
                for v in o.values(): walk(v)
            elif isinstance(o, list):
                for v in o: walk(v)
        walk(d)
        for t in trigs:
            nm = (t.get("triggeredAbility") or {}).get("name") if t.get("behavior") == "trigger" else t.get("name")
            nm = str(nm or t.get("name") or "").strip()
            disp = disps.get(nm.lower())
            book = None
            if folder == "monsters": book = mon_book(owner, nm)
            else: book = booktext(nm)
            out.append({"folder": folder.split("/")[-1], "owner": str(owner), "name": nm, "kind": t.get("behavior"), "rec": t, "display": disp, "book": book})
json.dump(out, open("triggers_all.json", "w"), default=str)
c = collections.Counter((r["folder"], r["kind"]) for r in out)
print(len(out), dict(c)); print("with display", sum(1 for r in out if r["display"]), "with book", sum(1 for r in out if r["book"]))
