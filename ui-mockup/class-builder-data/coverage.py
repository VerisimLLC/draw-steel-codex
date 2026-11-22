# Coverage of the class builder against the 11 core classes and their subclasses: which feature types,
# modifier behaviours, fields and conditions appear, and which the builder can't make yet.
import yaml, re, os, json, collections
D = "/home/user/verisimllc/draw-steel-data/objectTables"
L = yaml.CSafeLoader
def load(p):
    t = open(p, encoding="utf-8").read(); t = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', ' ', t)
    return yaml.load(t, Loader=L)
CORE = ["beastheart", "censor", "conduit", "elementalist", "fury", "null", "shadow", "summoner", "tactician", "talent", "troubadour"]
SUPPORTED_BEH = {"attribute", "power", "resistance", "conditionimmunity", "proficiency", "resource", "kitaccess", "activated", "trigger", "modifyability", "movementtext", "growingresources", "powertabletrigger", "triggerdisplay"}
SUPPORTED_FEAT = {"CharacterFeature", "CharacterFeatureChoice", "CharacterFeatureList", "CharacterSkillChoice", "CharacterFeatChoice", "CharacterSubclassChoice"}
feat_types = collections.Counter(); beh = collections.Counter(); beh_ex = {}; feat_ex = {}
class_fields = collections.Counter(); lanes = collections.Counter(); fields_by_beh = collections.defaultdict(collections.Counter)
cond_words = collections.Counter(); attr_ids = collections.Counter(); power_fields = collections.Counter()
subs = []
for fn in os.listdir(os.path.join(D, "subclasses")):
    if fn.endswith(".yaml") and not fn.startswith("_"):
        d = load(os.path.join(D, "subclasses", fn))
        if isinstance(d, dict) and not d.get("hidden"): subs.append(("sub:" + fn[:-5], d))
recs = [("class:" + c, load(os.path.join(D, "classes", c + ".yaml"))) for c in CORE] + subs
def walk(o, src, feat):
    if isinstance(o, dict):
        t = o.get("__typeName")
        if t and t.startswith("Character") and t != "CharacterModifier":
            feat_types[t] += 1; feat_ex.setdefault(t, (src, o.get("name")))
            feat = o.get("name") or feat
        if t == "CharacterModifier":
            b = o.get("behavior"); beh[b] += 1; beh_ex.setdefault(b, []).append((src, feat, o.get("name")))
            for k in o:
                if k not in ("name", "description", "__typeName", "behavior", "source", "sourceguid", "guid", "domains"): fields_by_beh[b][k] += 1
            for k in ("filterCondition", "activationCondition", "displayCondition"):
                v = o.get(k)
                if isinstance(v, str) and v.strip() not in ("", "1", "true"):
                    for w in re.findall(r'[A-Za-z][A-Za-z ]+?(?=\s*(?:>=|<=|=|>|<|\bhas\b|\band\b|\bor\b|\)|$))', v): cond_words[w.strip().lower()] += 1
            if b == "attribute": attr_ids[o.get("attribute")] += 1
        for v in o.values(): walk(v, src, feat)
    elif isinstance(o, list):
        for v in o: walk(v, src, feat)
for src, d in recs:
    for k in d:
        if k not in ("levels",): class_fields[(src.split(":")[0], k)] += 1
    for lk, lv in (d.get("levels") or {}).items():
        if (lv or {}).get("features"): lanes[re.sub(r"\d+", "N", lk)] += 1
        walk(lv, src, None)
print("== feature types (unsupported marked *)")
for t, n in feat_types.most_common(): print(("  * " if t not in SUPPORTED_FEAT else "    ") + t, n, feat_ex[t])
print("== modifier behaviours (unsupported marked *)")
for b, n in beh.most_common(): print(("  * " if b not in SUPPORTED_BEH else "    ") + str(b), n, beh_ex[b][:3])
print("== lanes with features"); print(dict(lanes))
print("== class/subclass fields"); print(sorted(class_fields.items()))
print("== power modifier fields"); print(fields_by_beh["power"].most_common(30))
print("== attribute modifier fields"); print(fields_by_beh["attribute"].most_common())
print("== trigger fields"); print(fields_by_beh["trigger"].most_common())
print("== condition words"); print(cond_words.most_common(45))
