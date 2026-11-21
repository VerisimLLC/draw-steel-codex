# Second poll: a fresh, stratified sample of monster abilities, class abilities not in the first poll,
# and player-facing triggers, each with its printed text for the book check.
import json, random, re, collections
random.seed(20261122)
mon = json.load(open("monsters_all.json"))
cls = json.load(open("../poll/all.json"))
first = {r["name"] for r in json.load(open("../poll/sample.json"))}
RES_TRIG = {"b9bc06dd-80f1-4f33-bc55-25c114e3300c", "5e551b7d-17fb-4099-a303-bafb3c146f98"}   # Trigger, Free Triggered Action
def is_player_trigger(r):
    m = r["rec"]
    if r["kind"] == "powertabletrigger": return m.get("type") in ("trigger", "free")
    ta = m.get("triggeredAbility") or {}
    return ta.get("actionResourceId") in RES_TRIG
lv = lambda x: float(x) if x not in (None, "", "None") else 0
band = lambda l: 0 if l <= 3 else 1 if l <= 6 else 2 if l <= 9 else 3
# --- monster book text
MD = open("/home/user/draw-steel-codex/monster-reference.md", encoding="utf-8").read().split("\n")
def mon_book(monster, name):
    name = (name or "").strip()
    heads = [i for i, l in enumerate(MD) if l.startswith("### ") and re.sub(r"\s*\(.*?\)\s*$", "", l[4:]).strip().lower() == name.lower()]
    if not heads: return None
    # prefer the heading inside this monster's section
    best = heads[0]
    for i in heads:
        j = i
        while j > 0 and not MD[j].startswith("## "): j -= 1
        if MD[j][3:].strip().lower() == str(monster).strip().lower(): best = i; break
    out = [MD[best]]
    for l in MD[best + 1: best + 40]:
        if l.startswith("### ") or l.startswith("## "): break
        out.append(l)
    return "\n".join(out).strip()
# --- class book text (functions from the first poll)
exec(open("../poll/sample.py").read().split("band = lambda")[0].split("for r in rows:\n    r[\"cls\"]")[0].split("rows = json.load")[0])
src = open("../poll/sample.py").read()
book = open("/home/user/draw-steel-codex/ClaudeBridge/ClaudeRefHeroes.lua", encoding="utf-8").read().split("\n")
clean = []; i = 0
while i < len(book):
    if re.match(r'^--- Page \d+ ---$', book[i]): i += 3; continue
    clean.append(book[i]); i += 1
ACT = re.compile(r'^(Main action|Maneuver|Free maneuver|Triggered action|Free triggered action|No action)\s*$', re.I)
def booktext(name):
    if not name: return None
    pat = re.compile(r'^' + re.escape(name.strip()) + r'(\s*\(\d+ [A-Za-z]+\))?\s*$', re.I)
    for k, l in enumerate(clean):
        if pat.match(l) and any(ACT.match(x) for x in clean[k+1:k+6]):
            out = [l]; j = k + 1; kw_seen = False
            while j < len(clean) and j < k + 40:
                if ACT.match(clean[j]):
                    if kw_seen and j - k > 4: out = out[:-3]; break
                    kw_seen = True
                if re.match(r'^\d+-[A-Za-z]+ Ability$|^Signature Ability$|^Level \d+ Features?$|^\d+(st|nd|rd|th)-Level', clean[j]): break
                out.append(clean[j]); j += 1
            return "\n".join(out)
    return None
sample = []
# monsters: 25 abilities across level bands, one per monster at most
mab = [r for r in mon if r["kind"] == "ability"]
random.shuffle(mab)
seen_mon = set(); per = collections.Counter()
for r in mab:
    b = band(lv(r["level"]))
    if per[b] >= 7 or r["monster"] in seen_mon: continue
    r["book"] = mon_book(r["monster"], r["name"]); r["source"] = "monster"; r["levelBand"] = b
    sample.append(r); seen_mon.add(r["monster"]); per[b] += 1
    if sum(per.values()) >= 25: break
# classes: 25 not in the first poll
cab = [r for r in cls if r["kind"] == "ability" and r["name"] not in first and r["level"]]
random.shuffle(cab)
per = collections.Counter()
for r in cab:
    b = band(r["level"])
    if per[b] >= 7: continue
    r["book"] = booktext(r["name"]); r["source"] = "class"; sample.append(r); per[b] += 1
    if sum(per.values()) >= 25: break
# triggers: 5 class + 5 monster, player-facing
ct = [r for r in cls if r["kind"] != "ability" and is_player_trigger(r) and r["name"] not in first]
mt = [r for r in mon if r["kind"] != "ability" and is_player_trigger(r)]
random.shuffle(ct); random.shuffle(mt)
for r in ct[:5]:
    nm = (r["rec"].get("triggeredAbility") or {}).get("name") or r["name"]; r["book"] = booktext(nm); r["source"] = "class"; sample.append(r)
for r in mt[:5]:
    r["book"] = mon_book(r["monster"], r["name"]); r["source"] = "monster"; sample.append(r)
json.dump(sample, open("sample2.json", "w"), default=str)
c = collections.Counter((r["source"], r["kind"]) for r in sample)
print(c, "with book:", sum(1 for r in sample if r["book"]))
for r in sample: print(r["source"], r["kind"], "|", r.get("monster") or r.get("cls"), "| L", r["level"], "|", r["name"], "|", "book" if r["book"] else "-")
