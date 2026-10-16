"""Turn a lua-language-server --check result into a CI verdict and GitHub annotations.

    python3 .github/scripts/luals_report.py <check.json> <workspace> <logpath> <workers>

Prints each problem as a GitHub Actions `::error` annotation (shown inline on the pull
request's Files tab) and a summary table, and exits 1 when there is any problem -- the
codex's rule is zero (TYPING.md).

It also fails when the result is incomplete. With more than one worker, LuaLS writes each
worker's result to <logpath>/check-partial-<n>.json and merges whatever partials exist
without saying so, so a worker killed for running out of memory would otherwise read as
its files checking clean.
"""
import json, os, sys, urllib.parse
from collections import Counter

check_path, workspace, logpath, workers = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])


def fail(msg):
    print(f'::error title=Lua type check::{msg}')
    sys.exit(1)


if workers > 1:
    missing = [n for n in range(1, workers + 1)
               if not os.path.exists(os.path.join(logpath, f'check-partial-{n}.json'))]
    if missing:
        fail(f'LuaLS worker(s) {missing} of {workers} produced no result (out of memory?); '
             'the check is incomplete. Lower LUALS_WORKERS in the workflow.')
if not os.path.exists(check_path):
    fail('lua-language-server wrote no result; see the step above.')

data = json.load(open(check_path, encoding='utf-8')) or {}  # a clean run is `[]`
root = workspace.replace('\\', '/').rstrip('/') + '/'

problems = []
for uri, diags in data.items():
    path = urllib.parse.unquote(uri.split('://', 1)[-1])
    if path.startswith('/') and path[2:3] == ':':  # file:///c:/... on Windows
        path = path[1:]
    if path.lower().startswith(root.lower()):
        path = path[len(root):]
    for d in diags:
        problems.append((path, d['range']['start']['line'] + 1, d['range']['start']['character'] + 1,
                         d.get('code', '?'), d['message'].splitlines()[0]))

problems.sort()
for path, line, col, code, msg in problems:
    msg = msg.replace('%', '%25').replace('\r', '').replace('\n', ' ')
    print(f'::error file={path},line={line},col={col},title={code}::{msg}')

summary = os.environ.get('GITHUB_STEP_SUMMARY')
if summary:
    with open(summary, 'a', encoding='utf-8') as out:
        if not problems:
            out.write('### Lua type check: clean\n\nZero problems.\n')
        else:
            out.write(f'### Lua type check: {len(problems)} problem(s)\n\n'
                      'Fix them, or suppress one line with `---@diagnostic disable-next-line: <code>` '
                      'and a comment saying why. See TYPING.md.\n\n| File | Line | Code | Problem |\n|---|---|---|---|\n')
            for path, line, col, code, msg in problems[:200]:
                out.write(f'| {path} | {line} | {code} | {msg.replace("|", "/")} |\n')
            if len(problems) > 200:
                out.write(f'\n...and {len(problems) - 200} more.\n')

counts = Counter(p[3] for p in problems)
print(f'{len(problems)} problem(s) in {len({p[0] for p in problems})} file(s)'
      + (': ' + ', '.join(f'{c} {k}' for k, c in counts.most_common()) if problems else ''))
sys.exit(1 if problems else 0)
