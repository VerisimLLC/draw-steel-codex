import yaml, os, json, collections, sys
ROOT=sys.argv[1]; L=getattr(yaml,"CSafeLoader",yaml.SafeLoader)
abil=[]
def walk(o,f):
    if isinstance(o,dict):
        if o.get("__typeName")=="ActivatedAbility":
            abil.append((f,[b.get("__typeName") for b in (o.get("behaviors") or []) if isinstance(b,dict)]))
        for v in o.values(): walk(v,f)
    elif isinstance(o,list):
        for v in o: walk(v,f)
for d in ("monsters","objectTables","objects"):
    for dp,_,fns in os.walk(os.path.join(ROOT,d)):
      for fn in fns:
        if fn.endswith(".yaml"):
            try: walk(yaml.load(open(os.path.join(dp,fn),encoding="utf-8"),Loader=L), os.path.relpath(dp,ROOT))
            except Exception: pass
P="ActivatedAbility"
S0={P+"PowerRollBehavior",P+"DrawSteelCommandBehavior",P+"DamageBehavior",P+"HealBehavior",P+"InvokeAbilityBehavior"}
S1=S0|{P+"ApplyOngoingEffectBehavior",P+"RelocateCreatureBehavior",P+"ApplyAbilityDurationEffect"}
S2=S1|{P+"ModifyPowerRollBehavior",P+"ReplenishBehavior",P+"ApplyRidersBehavior",P+"PurgeEffectsBehavior",P+"AugmentedAbilityBehavior",P+"SummonBehavior",P+"AuraBehavior"}
abil=[a for a in abil if a[1]]  # abilities with no behaviours are text-only or nested shells
n=len(abil)
for name,S in (("5 core steps",S0),("+ ongoing effect, relocate, duration effect (8)",S1),("+ 7 more (15)",S2)):
    full=sum(all(b in S for b in bs) for f,bs in abil)
    print(f"{name}: {full}/{n} abilities need no Advanced block ({100*full/n:.0f}%)")
print("abilities with behaviours:", n, " heroes/items (objectTables):", sum(1 for f,_ in abil if f.startswith("objectTables")))
