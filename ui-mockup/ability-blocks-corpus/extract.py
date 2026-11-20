# Walk every YAML asset, find ability records, and emit each GoblinScript formula with the
# formula-box description ("docs") the simple editor would use for it.
import yaml, json, sys, os, collections
ROOT = sys.argv[1]
try:
    Loader = yaml.CSafeLoader
except AttributeError:
    Loader = yaml.SafeLoader
ABILITY_FIELDS = {"range": ("number","range"), "radius": ("number","range"), "lineDistance": ("number","range"),
    "proximityRange": ("number","range"), "numTargets": ("number","numTargets"), "resourceNumber": ("number","cost"),
    "maxChannel": ("number","cost"), "targetFilter": ("boolean","targetFilter")}
out = open("formulas.jsonl", "w")
beh = collections.Counter(); beh_abilities = collections.Counter(); ab_types = collections.Counter()
tiers = open("tiers.jsonl", "w")
n_ab = 0
def emit(**kw):
    v = kw["formula"]
    if v is None: return
    v = str(v).strip()
    if v == "" : return
    kw["formula"] = v
    out.write(json.dumps(kw) + "\n")
def is_ability(t):
    return t == "ActivatedAbility" or t == "TriggeredAbility" or (t.endswith("Ability") and not t.endswith("Behavior") and t not in ("TriggeredAbilityDisplay",))
def walk(o, f):
    global n_ab
    if isinstance(o, dict):
        t = o.get("__typeName", "")
        if isinstance(t, str) and is_ability(t):
            n_ab += 1; ab_types[t] += 1
            handle(o, t, f)
        for v in o.values(): walk(v, f)
    elif isinstance(o, list):
        for v in o: walk(v, f)
def handle(a, t, f):
    name = a.get("name", "?")
    base = dict(file=f, abType=t, ability=name)
    for k, (kind, docs) in ABILITY_FIELDS.items():
        if k in a and not isinstance(a[k], (dict, list)): emit(**base, field=k, kind=kind, docs=docs, formula=a[k])
    for k in ("abilityFilters", "reasonedFilters"):
        for flt in a.get(k) or []:
            if isinstance(flt, dict): emit(**base, field=k, kind="boolean", docs="requirement", formula=flt.get("formula"))
    for m in a.get("modeList") or []:
        if isinstance(m, dict):
            emit(**base, field="mode.condition", kind="boolean", docs="requirement", formula=m.get("condition"))
            emit(**base, field="mode.targetCondition", kind="boolean", docs="targetFilter", formula=m.get("targetCondition"))
    if t == "TriggeredAbility":
        emit(**base, field="conditionFormula", kind="boolean", docs="trigger", formula=a.get("conditionFormula"))
    seen = set()
    for b in a.get("behaviors") or []:
        if not isinstance(b, dict): continue
        bt = b.get("__typeName", "?")
        if t == "ActivatedAbility":
            beh[bt] += 1
            if bt not in seen: beh_abilities[bt] += 1; seen.add(bt)
        emit(**base, field=bt + ".filterTarget", kind="boolean", docs="stepIf", formula=b.get("filterTarget"))
        if bt in ("ActivatedAbilityDamageBehavior",): emit(**base, field=bt + ".roll", kind="roll", docs="damage", formula=b.get("roll"))
        if bt in ("ActivatedAbilityHealBehavior",): emit(**base, field=bt + ".roll", kind="roll", docs="heal", formula=b.get("roll"))
        if bt == "ActivatedAbilityPowerRollBehavior":
            emit(**base, field=bt + ".roll", kind="roll", docs="powerRoll", formula=b.get("roll"))
            for i, tier in enumerate(b.get("tiers") or []):
                tiers.write(json.dumps(dict(base, tier=i + 1, text=tier)) + "\n")
files = 0
for d in ("monsters", "objectTables", "objects"):
    for dp, _, fns in os.walk(os.path.join(ROOT, d)):
      for fn in fns:
        if not fn.endswith(".yaml"): continue
        try:
            with open(os.path.join(dp, fn), encoding="utf-8") as fh: doc = yaml.load(fh, Loader=Loader)
        except Exception as e:
            print("skip", fn, str(e)[:60], file=sys.stderr); continue
        files += 1
        walk(doc, os.path.relpath(os.path.join(dp, fn), ROOT))
json.dump({"files": files, "abilities": n_ab, "abilityTypes": ab_types, "behaviors": beh.most_common(), "behaviorsPerAbility": beh_abilities.most_common()}, open("stats.json", "w"), indent=1)
print(files, "files", n_ab, "abilities")
