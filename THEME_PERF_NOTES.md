# Theme Engine Performance Notes

Bookmark for a future perf pass. Do not act on this without re-reading first; some of the data is from one observation session and the conclusions may shift after we get more samples.

## The symptom

Class compendium editor takes roughly 2x as long to load after the ThemeEngine migration than it did before. One specific class is the biggest offender; smaller classes load near-instantly. The user noticed it; instrumentation confirmed the bottleneck is *not* in `ThemeEngine.GetStyles` or `ThemeEngine.MergeStyles` themselves -- both have healthy call patterns. The cost is downstream, in engine-side panel construction (Unity-side, opaque to us).

## Instrumentation we left in place

In `DMHub Core UI/ThemeEngine.lua`:

- `_getStylesHits` / `_getStylesMisses` counters around the cache lookup in `GetStyles`.
- Periodic print every 50 calls: `THC:: GETSTYLECACHE:: total=N hits=H misses=M (hit rate X.X%)`.
- `_mergeStylesCalls` / `_mergeStylesHashCounts` counters in `MergeStyles`. Identity key is the customStyles table reference itself (NOT `tostring`, which would invoke a `__tostring` metamethod that serializes the whole table).
- `/themecache` slash command (devmode only) dumps both counters plus the top 5 most-frequently-passed customStyles tables by call count.

Strip this when we ship if it isn't useful by then. Until then it's harmless.

## What the data said (one class-editor open)

```
THC:: GETSTYLECACHE:: total=78 hits=77 misses=1 (hit rate 98.7%)
THC:: MERGESTYLES:: total=16 unique=9 (repeat rate 43.8%)
```

- **GetStyles cache is healthy.** 98%+ hit rate. Not the bottleneck.
- **MergeStyles call volume is small.** 16 calls per class load, 43.8% repeat by table identity. Caching MergeStyles by identity might save ~7 of the 16 calls; not enough to account for "2x slowdown."

## The smoking gun: DefaultStyles.lua growth

Apples-to-apples comparison of the array each panel actually walks:

| | Legacy `Styles.Default` (DMHub Titlescreen/Styles.lua, L220-880) | New main array (DMHub Core UI/DefaultStyles.lua, L208-2081) |
|---|---|---|
| Lines | 661 | 1,874 (~2.8x) |
| Rules | 87 | 284 (~3.3x) |
| Compound selectors | 32 | 161 (~5x) |

Pre-migration, callers spliced à la carte: `styles = { Styles.Default, Styles.Panel, Styles.ImplementationIcon, ... }`. Each panel only walked the rules its authors opted into. Many specialized rules lived outside `Styles.Default` and only entered the cascade for panels that needed them.

Post-migration, callers do `styles = ThemeEngine.GetStyles()` which returns the entire 284-rule array. Every panel under a `GetStyles` surface walks all 284. The panel construction cost scales with rule count and selector complexity (compound selectors are more expensive to evaluate than single-name).

The user-perceived 2x is roughly consistent with the rule-count growth, modulated by however much the engine indexes-by-first-selector internally (which we can't see).

This was reinforced this session when we moved `Styles.ImplementationIcon` (6 rules, with compound selectors) out of its standalone table and into DefaultStyles.lua so callers no longer have to opt in. That's correct for theme cohesion -- and exactly the move that grew the per-panel cost.

## Remediation options, ranked

### 1. Audit and trim DefaultStyles.lua (low-risk, do first)

With 284 rules and 161 compound, almost certainly 30-50 are redundant, dead, or feature-specific that snuck in. Each rule trimmed reduces *every* panel construction in the entire app.

Approach: enumerate every selector class in DefaultStyles.lua, grep the codebase for actual users, flag rules with zero or one caller. Decide per-rule whether to delete, fold into another rule, or move out into a feature-scoped pack.

Bounded, low-risk. Should be the first move.

### 2. Re-introduce optional packs for niche rule families (reversal of recent consolidation)

Niche rules that only appear in compendium UI (table-row primitives, `spellImplementationIcon`, etc.) could move to a `ThemeEngine.GetStyles("compendium")` variant. Compendium panels opt in; everything else stays cheap.

Cost: callers think about which pack to use again. Benefit: top-level UI rule-count drops back toward legacy levels.

This is a partial reversal of the move-into-DefaultStyles consolidation we just did. The signal is now saying monolithic was the wrong default.

### 3. Tiered cascade (engine permitting)

A "core" pack everyone gets (panel / label / button / input / dropdown defaults -- ~80 rules) plus opt-in packs for `forms`, `cards`, `tables`, `compendium`. Bigger refactor; would need to verify the engine supports the layered apply.

### 4. Lazy-expand featureCard bodies (panel-count fix, not per-panel)

Today every featureCard builds its full body upfront and hides via `collapsed-anim`. Body content is built but never seen until a click. Pattern would be: empty body until first expand; on click, build content, then toggle.

This is the original #1 idea before we measured. Still a real win, but the data shifted the diagnosis -- cost-per-panel matters more than panel count for this regression. Lazy expand is a clean architectural change for *unrelated* reasons (responsiveness, fewer hangs on giant classes) and worth doing eventually.

## Other levers we considered

- **Replace compound selectors with single-class composition.** Single-name selectors are cheaper to evaluate. Worth a 30-minute experiment: take 1-2 of the heaviest compound selectors, split them, time a class load, see if the needle moves before designing around it.
- **Defer building level cards that are off-screen.** Class editor renders all 10 levels + 4 tutorial encounters at once. Most are scrolled out of view. Engine support unclear (would need to check what `gui.Scrollable` exposes for visibility-aware deferred build).
- **Reduce per-feature chrome.** Each feature row has 8 panels (tri / name / points / imported / delete / settings / impl status / etc.). Could consolidate into a context menu. User-visible behavior change; not free.

## Recommended sequence when we come back

1. Decide whether the perf is still worth fixing (one class is bad, others are fine -- maybe target that one specifically).
2. Run the audit (option 1). Bounded, no risk.
3. If audit isn't enough, do option 2 -- move niche packs back out.
4. Lazy expand (option 4) regardless, on its own merits.
5. Engine indexing experiment (compound vs single) only if 1-3 don't recover the gap.

## Files implicated

- `DMHub Core UI/DefaultStyles.lua` -- the monolithic array. Grew from absorbing `Styles.Panel`, `Styles.ImplementationIcon`, etc.
- `DMHub Core UI/ThemeEngine.lua` -- holds the instrumentation. `GetStyles` and `MergeStyles` are the two entry points.
- `DMHub Titlescreen/Styles.lua` -- still present for legacy callers (`Styles.Default`, `Styles.Panel`, etc.). The migration is folding callers off of it; not all are migrated yet.
- `Draw Steel UI/DSClassEditor.lua` -- the class editor. Heavy panel construction; the visible site of the symptom.
