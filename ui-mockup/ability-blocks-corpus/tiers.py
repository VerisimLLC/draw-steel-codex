# Classify each power-roll tier segment against the simple editor's tier steps.
import json, re, collections
COND = "bleeding|dazed|frightened|grabbed|prone|restrained|slowed|taunted|weakened"
pot = r"(?:[MARIP]\s*<\s*(?:\d+|weak|average|strong)\s*,?\s*)?"
pats = {
  "damage": re.compile(r"^" + pot + r"[\d\sd+\-\w]*?\s*(?:\w+\s)?damage$", re.I),
  "condition": re.compile(r"^" + pot + r"(?:the target is\s+)?(?:" + COND + r")(?:\s*(?:and can't stand)?)?(?:\s*\((?:save ends|eot|until the end of (?:their|its|your) next turn)\))?$", re.I),
  "forced": re.compile(r"^" + pot + r"(?:vertical\s+)?(?:push|pull|slide|shift)\s+\d+(?:\s+squares?)?$", re.I),
}
rows = [json.loads(l) for l in open("tiers.jsonl")]
seg_kind = collections.Counter(); full = 0; total = 0; other = collections.Counter(); has_comment = 0; potency_seg = 0
for r in rows:
    t = r["text"]
    if not isinstance(t, str) or not t.strip(): continue
    total += 1
    if "#" in t: has_comment += 1
    t = re.sub(r"#[^;]*", "", t)
    ok = True
    for seg in [s.strip() for s in t.split(";") if s.strip()]:
        if re.match(r"^[MARIP]\s*<", seg): potency_seg += 1
        k = next((k for k, p in pats.items() if p.match(seg)), None)
        if k: seg_kind[k] += 1
        else:
            ok = False; seg_kind["other"] += 1
            other[re.sub(r"\d+", "N", seg.lower())[:60]] += 1
    full += ok
print(f"tier strings: {total}, fully modelled: {full} ({100*full/total:.0f}%), with # comments: {has_comment}, potency segments: {potency_seg}")
print(dict(seg_kind))
print("\n".join(f"{n:4} {k}" for k, n in other.most_common(25)))
