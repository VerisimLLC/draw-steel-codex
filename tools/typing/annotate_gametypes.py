"""Give every `X = RegisterGameType("X"[, "Base"])` in the codex a `--- @class X: Parent`
line whose parent chain ends at GameType.

    python tools/typing/annotate_gametypes.py            # add what is missing
    python tools/typing/annotate_gametypes.py --check    # exit 1 if anything is missing
    python tools/typing/annotate_gametypes.py <codex-dir>  # another checkout

- an existing `--- @class X` with no parent gets `: GameType` (or `: Base` when the
  registration names a base)
- a registration with no @class block gets one inserted directly above it
- existing parents are left alone
- every @class block gets `--- @field new fun(o?: table): X` directly under the @class
  line, unless the block already declares `new`. GameType.new is dot-called, so its
  stub can only return `any`; this per-class field is what makes `X.new{...}` (and
  every `CreateNew` that returns one) a typed X
- bare `RegisterGameType("X")` calls (no assignment) are NOT touched; turn them into
  `X = RegisterGameType("X")` first, then re-run

Annotation lines only: the script never changes code, and it preserves each file's
line-ending convention. Re-runnable; a second run is a no-op.
"""
import re, glob, os, sys, collections

check = '--check' in sys.argv
args = [a for a in sys.argv[1:] if a != '--check']
root = args[0] if args else os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
os.chdir(root)
reg = re.compile(r'''^(\s*)(local\s+)?([A-Za-z_][\w.]*)\s*=\s*RegisterGameType\(\s*(["'])([^"']+)\4\s*(?:,\s*(["'])([^"']+)\6)?\s*\)''')
cls = re.compile(r'^(\s*---?\s*@class\s+)([\w.]+)(\s*:\s*[\w., ]+)?(.*)$')
newfield = re.compile(r'^\s*---?\s*@field\s+new\b')
stats = collections.Counter()


def ensure_new_field(L, j, typename, indent):
    """Insert the typed `new` under the @class line at L[j] unless the comment lines
    that follow it already declare one. Returns 1 if a line was inserted."""
    k = j + 1
    while k < len(L) and L[k].lstrip().startswith('--'):
        if newfield.match(L[k]):
            return 0
        k += 1
    L.insert(j + 1, f'{indent}--- @field new fun(o?: table): {typename}')
    return 1


touched = []

for f in sorted(glob.glob('**/*.lua', recursive=True)):
    # tests/ holds mocks of engine globals; annotating them retypes the real ones.
    if f.startswith(('Definitions', 'tools', 'tests')) or '.claude' in f or '.agents' in f:
        continue
    raw = open(f, 'rb').read()
    crlf = b'\r\n' in raw
    nl = '\r\n' if crlf else '\n'
    L = raw.decode('utf-8').split(nl)
    changed = False
    i = 0
    while i < len(L):
        m = reg.match(L[i])
        if not m:
            i += 1
            continue
        indent, _, var, _, typename, _, base = m.groups()
        parent = base or 'GameType'
        j = i - 1
        found = None
        while j >= 0 and L[j].lstrip().startswith('--'):
            cm = cls.match(L[j])
            if cm:
                found = (j, cm)
                break
            j -= 1
        if found:
            j, cm = found
            if cm.group(2) != typename:
                stats['SKIPPED: @class name differs from type'] += 1
                print(f'  skip {f}:{i + 1}: @class {cm.group(2)} annotates {typename}')
            else:
                if cm.group(3):
                    stats['already has parent'] += 1
                else:
                    L[j] = cm.group(1) + typename + ': ' + parent + cm.group(4)
                    stats['parent added to existing @class'] += 1
                    changed = True
                if ensure_new_field(L, j, typename, indent):
                    stats['typed new added'] += 1
                    changed = True
                    i += 1
        else:
            L.insert(i, f'{indent}--- @class {typename}: {parent}')
            L.insert(i + 1, f'{indent}--- @field new fun(o?: table): {typename}')
            i += 2
            stats['@class inserted'] += 1
            stats['typed new added'] += 1
            changed = True
        i += 1
    if changed:
        if not check:
            open(f, 'wb').write(nl.join(L).encode('utf-8'))
        touched.append(f)

for k, n in stats.most_common():
    print(f'{n:5d} {k}')
print(('files needing annotations' if check else 'files touched'), len(touched))
for f in touched:
    print('  ', f)
if check and touched:
    print('run python tools/typing/annotate_gametypes.py to add them')
    sys.exit(1)
