# Ability Blocks corpus test

Runs every formula and power-roll tier in the draw-steel-data compendium through the
simple-editor prototype's parser and block mapping. Results are in ABILITY_BLOCKS_DESIGN.md, section 4d.

Run from an empty working folder (needs Python with PyYAML, and Node):

    python <this folder>/extract.py <path to draw-steel-data>   # writes formulas.jsonl, tiers.jsonl, stats.json
    python <this folder>/beh.py <path to draw-steel-data>       # behaviour coverage
    python <this folder>/tiers.py                               # tier text coverage
    python <this folder>/make-engine.py                         # engine.js from the prototype page
    node <this folder>/formula-test.js                          # parse, round trip, block coverage

formula-test.js expects engine.js and formulas.jsonl in the current folder.
