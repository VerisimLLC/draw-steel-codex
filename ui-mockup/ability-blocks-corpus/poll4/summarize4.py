# Counts only (no book text), for the design doc: how much of each pasted page the reader builds.
import json, collections
R = json.load(open("paste4.json"))
m = [r for r in R if "cmp" in r]
out = dict(pages=len(R), matchedToOurData=len(m),
    fullyBuilt=sum(r["full"] for r in R),
    everyTierResultBuilt=sum(1 for r in R if not r["steps"].get("tierTodos")),
    blocksBuilt=sum(r["steps"]["block"] for r in R),
    tierPiecesLeft=sum(len(r["steps"].get("tierTodos", [])) for r in R),
    effectSentencesLeft=sum(len(r["steps"]["todos"]) for r in R),
    headerAgreesWithOurData={k: sum(1 for r in m if r["cmp"][k] is True) for k in ["keywords", "action", "targetType", "range", "cost", "roll", "tiers"]},
    byClassFullyBuilt=dict(collections.Counter(r["file"].split("/")[0] for r in R if r["full"])))
json.dump(out, open("paste4-summary.json", "w"), indent=1); print(json.dumps(out, indent=1))
