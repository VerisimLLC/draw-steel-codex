"""Type-check the codex with lua-language-server (LuaLS), the way CI does.

    python tools/typing/check.py                 # the .lua files you changed (git), ~1 minute
    python tools/typing/check.py A.lua "B/C.lua" # just these files
    python tools/typing/check.py --staged        # what your next commit holds
    python tools/typing/check.py --all           # the whole codex, exactly as CI runs it

Run it from anywhere; paths are relative to the codex root. Needs Python 3 and LuaLS:
it uses --server if given, else $LUALS, else `lua-language-server` on PATH, else the one
bundled with the VS Code (or VSCodium / Cursor) "Lua" extension. See TYPING.md.

Every problem is printed as `path:line:col: code: message`, and the exit code is 1 when
there is any (the rule is zero), 2 when the check itself could not run.

How the changed-files mode works: LuaLS gives no diagnostics for files under
`workspace.library`, so the files being checked are copied into a scratch workspace, and
the rest of the codex is loaded as that library. Cross-file classes and globals still
resolve, and only your files are diagnosed. The limit: an edit that breaks typing in a
file you did NOT change shows only in a full run (--all, or CI).
"""
import argparse, glob, json, os, re, shutil, subprocess, sys, tempfile, urllib.parse
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
CODEX = os.path.normpath(os.path.join(HERE, '..', '..'))
CONFIG = os.path.join(CODEX, '.luarc.json')
WORKFLOW = os.path.join(CODEX, '.github', 'workflows', 'lua-typecheck.yml')
# Never diagnosed: engine stubs, editor/agent worktrees, data. Matches check.ps1.
SKIP_PREFIXES = ('Definitions/', '.claude/', '.agents/', 'compendium/')


def die(msg, code=2):
    print(msg, file=sys.stderr)
    sys.exit(code)


def git(*args, check=True):
    r = subprocess.run(['git', *args], cwd=CODEX, capture_output=True, text=True)
    if check and r.returncode != 0:
        die(f'git {" ".join(args)} failed: {r.stderr.strip()}')
    return r.stdout


def find_server(explicit):
    exe = 'lua-language-server.exe' if os.name == 'nt' else 'lua-language-server'
    for cand in (explicit, os.environ.get('LUALS'), shutil.which('lua-language-server')):
        if cand and os.path.isfile(cand):
            return cand
    home = os.path.expanduser('~')
    found = []
    for editor in ('.vscode', '.vscode-insiders', '.vscode-oss', '.cursor', '.windsurf'):
        for ext in glob.glob(os.path.join(home, editor, 'extensions', 'sumneko.lua-*')):
            path = os.path.join(ext, 'server', 'bin', exe)
            m = re.search(r'sumneko\.lua-(\d+)\.(\d+)\.(\d+)', ext)
            if os.path.isfile(path) and m:
                found.append((tuple(int(x) for x in m.groups()), path))
    if found:
        return max(found)[1]
    die('lua-language-server not found. Install the VS Code "Lua" extension (sumneko.lua), or a\n'
        'LuaLS release from https://github.com/LuaLS/lua-language-server/releases, then pass\n'
        '--server <path to the lua-language-server binary> or set LUALS. See TYPING.md.')


def check_version(server):
    want = None
    if os.path.exists(WORKFLOW):
        m = re.search(r'LUALS_VERSION:\s*([\d.]+)', open(WORKFLOW, encoding='utf-8').read())
        want = m and m.group(1)
    try:
        have = subprocess.run([server, '--version'], capture_output=True, text=True,
                              timeout=60).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        have = ''
    if want and have and want not in have:
        print(f'note: LuaLS {have} here, CI uses {want}; results can differ slightly.\n')


def changed_files(staged):
    if staged:
        rel = git('diff', '--cached', '--name-only', '--diff-filter=ACMR', '--', '*.lua').split('\n')
    else:
        rel = git('diff', '--name-only', 'HEAD', '--', '*.lua').split('\n')
        rel += git('ls-files', '--others', '--exclude-standard', '--', '*.lua').split('\n')
    return rel


def select(paths):
    rel = []
    for p in paths:
        p = p.strip().replace('\\', '/')
        if not p:
            continue
        if os.path.isabs(p):
            p = os.path.relpath(p, CODEX).replace('\\', '/')
        if p.startswith(SKIP_PREFIXES) or not p.endswith('.lua'):
            continue
        if os.path.isfile(os.path.join(CODEX, p)):
            rel.append(p)
    rel = sorted(set(rel))
    if rel:
        # Gitignored files (e.g. a nested repository) are not part of the codex.
        ignored = set(git('check-ignore', '--', *rel, check=False).split('\n'))
        rel = [p for p in rel if p not in ignored]
    return rel


def run_luals(server, target, config, workers, out):
    log = tempfile.mkdtemp(prefix='luals-log-')
    try:
        r = subprocess.run([server, '--check', target, '--configpath', config,
                            '--checklevel=Warning', f'--num_threads={workers}',
                            '--logpath', log, '--check_out_path', out],
                           capture_output=True, text=True)
        # A worker that dies (usually out of memory) leaves no partial result, and LuaLS
        # merges what is there without saying so -- which would read as files coming clean.
        if workers > 1:
            missing = [n for n in range(1, workers + 1)
                       if not os.path.exists(os.path.join(log, f'check-partial-{n}.json'))]
            if missing:
                die(f'LuaLS worker(s) {missing} of {workers} produced no result (out of memory?); '
                    'the check is incomplete. Retry with fewer --threads.')
        if not os.path.exists(out):
            die('lua-language-server wrote no result:\n' + (r.stdout + r.stderr)[-2000:])
    finally:
        shutil.rmtree(log, ignore_errors=True)


def read_problems(out, root):
    data = json.load(open(out, encoding='utf-8')) or {}   # a clean run is `[]`
    root = root.replace('\\', '/').rstrip('/') + '/'
    problems = []
    for uri, diags in data.items():
        path = urllib.parse.unquote(uri.split('://', 1)[-1])
        if path.startswith('/') and path[2:3] == ':':   # file:///c:/... on Windows
            path = path[1:]
        if path.lower().startswith(root.lower()):
            path = path[len(root):]
        for d in diags:
            s = d['range']['start']
            problems.append((path, s['line'] + 1, s['character'] + 1, d.get('code', '?'),
                             d['message'].strip()))
    return sorted(problems)


def check_files(server, rel, staged, threads, scratch):
    ws = os.path.join(scratch, 'codex')
    for p in rel:
        dst = os.path.join(ws, p)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if staged:
            blob = subprocess.run(['git', 'show', f':{p}'], cwd=CODEX, capture_output=True).stdout
            open(dst, 'wb').write(blob)
        else:
            shutil.copyfile(os.path.join(CODEX, p), dst)

    # The codex as library: each top-level folder that holds no checked file whole, and the
    # rest file by file WITHOUT the checked files -- with both copies loaded, everything a
    # checked file declares would be reported as a duplicate.
    cfg = json.load(open(CONFIG, encoding='utf-8'))
    ignore = set(cfg.get('workspace.ignoreDir', []))
    checked = {os.path.normcase(os.path.join(CODEX, p)) for p in rel}
    lib = []
    for name in sorted(os.listdir(CODEX)):
        full = os.path.join(CODEX, name)
        if os.path.isdir(full):
            if name in ignore or name.startswith('.'):
                continue
            prefix = os.path.normcase(full) + os.sep
            if any(c.startswith(prefix) for c in checked):
                for dirpath, dirnames, filenames in os.walk(full):
                    dirnames[:] = [d for d in dirnames if d not in ignore and not d.startswith('.')]
                    for fn in filenames:
                        f = os.path.join(dirpath, fn)
                        if fn.endswith('.lua') and os.path.normcase(f) not in checked:
                            lib.append(f.replace('\\', '/'))
            else:
                lib.append(full.replace('\\', '/'))
        elif name.endswith('.lua') and os.path.normcase(full) not in checked:
            lib.append(full.replace('\\', '/'))
    cfg['workspace.library'] = lib
    cfg_path = os.path.join(scratch, 'luarc.json')
    json.dump(cfg, open(cfg_path, 'w', encoding='utf-8'), indent=1)

    out = os.path.join(scratch, 'check.json')
    workers = max(1, min(threads, -(-len(rel) // 25)))   # one worker per 25 files
    run_luals(server, ws, cfg_path, workers, out)
    return read_problems(out, ws)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter,
                                 epilog=__doc__.split('\n\n', 1)[1])
    ap.add_argument('files', nargs='*', help='codex .lua files to check (default: git-changed ones)')
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument('--staged', action='store_true', help='check the staged content of staged files')
    mode.add_argument('--all', action='store_true', help='check the whole codex, as CI does')
    ap.add_argument('--threads', type=int, default=4,
                    help='LuaLS worker processes (default 4). Each holds the whole codex in '
                         'memory, ~2 GB; use fewer on a smaller machine')
    ap.add_argument('--server', help='path to the lua-language-server binary')
    args = ap.parse_args()

    server = find_server(args.server)
    check_version(server)
    scratch = tempfile.mkdtemp(prefix='codex-typecheck-')
    try:
        if args.all:
            print(f'Checking the whole codex on {args.threads} worker(s); a few minutes...')
            out = os.path.join(scratch, 'check.json')
            run_luals(server, CODEX, CONFIG, args.threads, out)
            problems = read_problems(out, CODEX)
        else:
            if args.files and args.staged:
                die('give files or --staged, not both')
            rel = select(args.files or changed_files(args.staged))
            if not rel:
                print('No changed codex .lua files to check.' if not args.files
                      else 'None of those are codex .lua files that get checked.')
                return 0
            print(f'Checking {len(rel)} file(s), with the rest of the codex as library:')
            for p in rel:
                print(f'   {p}')
            problems = check_files(server, rel, args.staged, args.threads, scratch)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    print()
    for path, line, col, code, msg in problems:
        first, *rest = msg.splitlines()
        print(f'{path}:{line}:{col}: {code}: {first}')
        for r in rest:
            print(f'    {r}')
    if not problems:
        print('Clean: zero problems.')
        return 0
    counts = Counter(p[3] for p in problems)
    print(f'\n{len(problems)} problem(s) in {len({p[0] for p in problems})} file(s): '
          + ', '.join(f'{c} {k}' for k, c in counts.most_common()))
    print('Fix them (TYPING.md has the usual causes), or suppress one line with\n'
          '`---@diagnostic disable-next-line: <code>` and a comment saying why.')
    return 1


if __name__ == '__main__':
    sys.exit(main())
