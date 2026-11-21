# Compare each card the editor shows with the printed text (monster-reference.md, the rulebook PDF text,
# the Beastheart reference). Fuzzy match: wording that differs only in spacing, case or punctuation counts.
import json, re, difflib, collections
R = json.load(open("roundtrip2.json"))
POT = {"w": "weak", "v": "average", "s": "strong"}
def norm(t):
    t = (t or "").lower().replace("≤", "<=").replace("’", "'").replace("–", "-")
    t = re.sub(r"\b([marip])\s*<\s*(w|v|s)\b", lambda m: m.group(1) + "<" + POT[m.group(2)], t)   # PDF potency letters
    t = re.sub(r"([a-z])- ?\n?([a-z])", r"\1\2", t)
    t = re.sub(r"[\[\]\(\)*_,;:.!\"]", " ", t)
    t = re.sub(r"\b([marip]) ?< ?", r"\1<", t)
    return re.sub(r"\s+", " ", t).strip()
def sim(a, b): return difflib.SequenceMatcher(None, norm(a), norm(b)).ratio()
def parse_book(src, txt):
    b = {"dist": None, "target": None, "tiers": [], "effects": []}
    if not txt: return None
    lines = txt.split("\n")
    if src == "monster" or txt.startswith("**") or txt.startswith("### "):
        for l in lines:
            m = re.match(r"^\*([^*|]+?)\s*\|\s*([^*]+)\*$", l.strip())
            if m and b["dist"] is None: b["dist"], b["target"] = m.group(1).strip(), m.group(2).strip(); continue
            m = re.match(r"^- \*\*Tier \d.*?:\*\*\s*(.*)$", l.strip())
            if m: b["tiers"].append(m.group(1)); continue
            m = re.match(r"^\|\s*(<=\s*11|12-16|17\+)\s*\|\s*(.*?)\s*\|$", l.strip())
            if m: b["tiers"].append(m.group(2)); continue
            m = re.match(r"^-?\s*Distance:\s*(.*?)\s*\|\s*Target:\s*(.*)$", l.strip())
            if m: b["dist"], b["target"] = m.group(1), m.group(2); continue
            m = re.match(r"^-?\s*\*\*([^*]+?):\*\*\s*(.*)$", l.strip()) or re.match(r"^- (Effect|Trigger|Special|Strained):\s*(.*)$", l.strip())
            if m: b["effects"].append([m.group(1), m.group(2)]); continue
            if b["effects"] and l.strip() and not l.startswith(("|", "#", "*")): b["effects"][-1][1] += " " + l.strip()
        return b
    # rulebook PDF text: icon letters o (distance), x (target), a/e/i (tiers)
    cur = None
    for l in lines[1:]:
        s = l.strip()
        if not s: continue
        m = re.match(r"^o\s+(.*?)\s*$", s)
        if m and b["dist"] is None: b["dist"] = m.group(1); cur = None; continue
        m = re.match(r"^x\s+(.*?)\s*$", s)
        if m and b["target"] is None: b["target"] = m.group(1); cur = None; continue
        m = re.match(r"^[aei]\s+(.*)$", s)
        if m and len(b["tiers"]) < 3 and not b["effects"]: b["tiers"].append(m.group(1)); cur = "tier"; continue
        m = re.match(r"^([A-Z][A-Za-z0-9 +]{1,30}):\s*(.*)$", s)
        if m and not re.match(r"^Power Roll", s): b["effects"].append([m.group(1), m.group(2)]); cur = "eff"; continue
        if re.match(r"^Power Roll", s): cur = None; continue
        if cur == "eff": b["effects"][-1][1] += " " + s
        elif cur == "tier" and b["tiers"]: b["tiers"][-1] += " " + s
    return b
out = []
stats = collections.Counter()
for r in R:
    if r.get("error") or not r.get("book"): continue
    bk = parse_book(r["source"], r["book"]); c = r["card"]
    issues = []
    if bk["dist"] is not None:
        stats["dist"] += 1
        if sim(bk["dist"], c["dist"]) >= .85: stats["dist_ok"] += 1
        else: issues.append(("distance", bk["dist"], c["dist"]))
    if bk["target"] is not None:
        stats["target"] += 1
        if sim(bk["target"], c["target"]) >= .85: stats["target_ok"] += 1
        else: issues.append(("target", bk["target"], c["target"]))
    for i, t in enumerate(bk["tiers"][:3]):
        stats["tiers"] += 1
        ct = c["tiers"][i] if i < len(c["tiers"]) else ""
        if sim(t, ct) >= .85: stats["tiers_ok"] += 1
        else: issues.append(("tier %d" % (i + 1), t, ct))
    for lab, txt in bk["effects"]:
        stats["effects"] += 1
        best = max([sim(txt, ct) for cl, ct in c["effects"]] or [0])
        if best >= .8: stats["effects_ok"] += 1
        else: issues.append(("effect " + lab, txt, " || ".join(cl + ": " + ct for cl, ct in c["effects"])))
    out.append({"name": r["name"], "source": r["source"], "kind": r["kind"], "issues": issues})
    if not issues: stats["cards_all_ok"] += 1
    stats["cards"] += 1
json.dump(out, open("bookcheck.json", "w"), indent=1)
print(dict(stats))
for o in out:
    if o["issues"]:
        print("\n##", o["source"], o["kind"], o["name"])
        for k, a, b in o["issues"]: print("   ", k, "| BOOK:", a[:150], "\n         CARD:", b[:150])
