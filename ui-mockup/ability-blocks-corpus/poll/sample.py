# Stratified random sample: per class, one ability from each level band plus one triggered ability.
import json, random, re, os, yaml
random.seed(20261121)
ROOT = "/home/user/verisimllc/draw-steel-data/objectTables"
rows = json.load(open("all.json"))
# subclass -> class name
ids = {}
for fn in os.listdir(ROOT + "/classes"):
    if fn.endswith(".yaml") and not fn.startswith("_"):
        t = open(ROOT + "/classes/" + fn).read(); m = re.search(r'^id: (\S+)', t, re.M); n = re.search(r'^name: (.+)', t, re.M)
        if m and n: ids[m.group(1)] = n.group(1).strip()
subcls = {}
for fn in os.listdir(ROOT + "/subclasses"):
    if fn.endswith(".yaml") and not fn.startswith("_"):
        t = open(ROOT + "/subclasses/" + fn).read(); m = re.search(r'primaryClassId: (\S+)', t); n = re.search(r'^name: (.+)', t, re.M)
        if m and n: subcls[n.group(1).strip()] = ids.get(m.group(1), "?")
for r in rows:
    r["cls"] = (r["cls"] or "").strip('"')
for k in list(ids): ids[k] = ids[k].strip('"')
for k in list(subcls): pass
subcls = {k.strip('"'): v.strip('"') for k, v in subcls.items()}
for r in rows:
    r["klass"] = subcls.get(r["cls"], "?") if r["sub"] else r["cls"]
    r["from"] = r["cls"]
# Book text
book = open("/home/user/draw-steel-codex/ClaudeBridge/ClaudeRefHeroes.lua", encoding="utf-8").read().split("\n")
clean = []
i = 0
while i < len(book):
    if re.match(r'^--- Page \d+ ---$', book[i]): i += 3; continue   # page marker + running header + page number
    clean.append(book[i]); i += 1
ACT = re.compile(r'^(Main action|Maneuver|Free maneuver|Triggered action|Free triggered action|No action)\s*$', re.I)
def booktext(name):
    if not name: return None
    pat = re.compile(r'^' + re.escape(name) + r'(\s*\(\d+ [A-Za-z]+\))?\s*$', re.I)
    for k, l in enumerate(clean):
        if pat.match(l) and any(ACT.match(x) for x in clean[k+1:k+6]):
            out = [l]; j = k + 1
            kw_seen = False
            while j < len(clean) and j < k + 40:
                if ACT.match(clean[j]):
                    if kw_seen and j - k > 4: out = out[:-3]; break   # next ability's name, flavor, keywords already taken
                    kw_seen = True
                if re.match(r'^\d+-[A-Za-z]+ Ability$|^Signature Ability$|^Level \d+ Features?$', clean[j]): break
                out.append(clean[j]); j += 1
            return "\n".join(out)
    return None
MD = open("/home/user/draw-steel-codex/beastheart-reference.md", encoding="utf-8").read().split("\n")
def mdtext(name):
    if not name: return None
    for k, l in enumerate(MD):
        if l.startswith("**" + name.strip() + " (") or l.startswith("**" + name.strip() + "**"):
            out = []
            for x in MD[k:k+30]:
                if x.strip() == "---" or (out and x.startswith("**") and " -- " in x): break
                out.append(x)
            return "\n".join(out)
    return None
band = lambda lv: 0 if lv == 1 else 1 if lv in (2, 3) else 2 if lv in (4, 5, 6) else 3
sample = []
for klass in sorted({r["klass"] for r in rows if r["klass"] != "?"}):
    pool = [r for r in rows if r["klass"] == klass]
    for b in range(4):
        cand = [r for r in pool if r["kind"] == "ability" and r["level"] and band(r["level"]) == b and r["cat"] != "Trigger"]
        if cand: sample.append(random.choice(cand))
    # Player-facing triggers, not the "gain your Heroic Resource" bookkeeping features.
    RES = re.compile(r'^(wrath|ferocity|piety|essence|discipline|insight|focus|clarity|drama|.* piety)$', re.I)
    trig = [r for r in pool if (r["kind"] != "ability" or r["cat"] == "Trigger") and not RES.match((r["name"] or "").strip())]
    if trig: sample.append(random.choice(trig))
for r in sample:
    nm = r["name"]
    if r["kind"] != "ability": nm = (r["rec"].get("triggeredAbility") or {}).get("name") or r["rec"].get("name")
    r["book"] = booktext(nm) or mdtext(nm)
json.dump(sample, open("sample.json", "w"), default=str, indent=0)
for r in sample: print(r["klass"], "|", r["from"], "| L", r["level"], "|", r["cat"], "|", r["name"], "| book" if r["book"] else "| NO BOOK")
print(len(sample), sum(1 for r in sample if r["book"]))
