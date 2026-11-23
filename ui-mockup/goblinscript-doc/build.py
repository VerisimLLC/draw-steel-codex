"""Builds ui-mockup/goblinscript.html from the repo's GoblinScript_Guide.md, so the block editors'
"Type a formula instead" box can open a GoblinScript reference with no outside site.
Run from the repo root:  python ui-mockup/goblinscript-doc/build.py"""
import html, re, os
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
src = open(os.path.join(ROOT, "GoblinScript_Guide.md"), encoding="utf-8").read()
# The guide opens with a note that it is written for AI tools; readers of this page don't need it.
src = re.sub(r'^> \*\*Note:\*\*.*?(?:\n>.*)*\n', '', src, flags=re.M)

def slug(t): return re.sub(r'[^a-z0-9 -]', '', t.lower()).strip().replace(' ', '-')
def inline(t):
    parts = re.split(r'(`[^`]*`)', t); out = []
    for p in parts:
        if p.startswith('`') and p.endswith('`') and len(p) > 1: out.append('<code>' + html.escape(p[1:-1]) + '</code>'); continue
        p = html.escape(p, quote=False)
        p = re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', p)
        p = re.sub(r'(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])', r'<i>\1</i>', p)
        p = re.sub(r'\[([^\]]+)\]\((#[^)]+)\)', r'<a href="\2">\1</a>', p)
        p = re.sub(r'\[([^\]]+)\]\(([^)#][^)]*)\)', r'\1', p)   # links to repo files: keep the words
        out.append(p)
    return ''.join(out)

lines = src.split('\n'); out = []; i = 0
while i < len(lines):
    l = lines[i]
    if l.startswith('```'):
        j = i + 1; buf = []
        while j < len(lines) and not lines[j].startswith('```'): buf.append(lines[j]); j += 1
        out.append('<pre><code>' + html.escape('\n'.join(buf)) + '</code></pre>'); i = j + 1; continue
    m = re.match(r'^(#{1,4}) (.*)', l)
    if m:
        n = len(m.group(1)); t = m.group(2)
        out.append('<h%d id="%s">%s</h%d>' % (n, slug(t), inline(t), n)); i += 1; continue
    if l.startswith('|'):
        rows = []
        while i < len(lines) and lines[i].startswith('|'): rows.append(lines[i]); i += 1
        cells = lambda r: [c.strip() for c in r.strip().strip('|').split('|')]
        h = cells(rows[0]); body = [r for r in rows[1:] if not re.match(r'^\|[\s:|-]+\|?$', r)]
        out.append('<table><thead><tr>' + ''.join('<th>' + inline(c) + '</th>' for c in h) + '</tr></thead><tbody>' +
                   ''.join('<tr>' + ''.join('<td>' + inline(c) + '</td>' for c in cells(r)) + '</tr>' for r in body) + '</tbody></table>')
        continue
    if re.match(r'^\s*([-*]|\d+\.) ', l):
        ordered = bool(re.match(r'^\s*\d+\. ', l)); items = []
        while i < len(lines) and re.match(r'^\s*([-*]|\d+\.) ', lines[i]):
            items.append(re.sub(r'^\s*([-*]|\d+\.) ', '', lines[i])); i += 1
        tag = 'ol' if ordered else 'ul'
        out.append('<%s>%s</%s>' % (tag, ''.join('<li>' + inline(x) + '</li>' for x in items), tag)); continue
    if l.startswith('>'):
        buf = []
        while i < len(lines) and lines[i].startswith('>'): buf.append(lines[i].lstrip('> ')); i += 1
        out.append('<blockquote>' + inline(' '.join(buf)) + '</blockquote>'); continue
    if l.strip() == '---': out.append('<hr>'); i += 1; continue
    if not l.strip(): i += 1; continue
    buf = []
    while i < len(lines) and lines[i].strip() and not re.match(r'^(#|\||```|>|\s*([-*]|\d+\.) |---)', lines[i]): buf.append(lines[i]); i += 1
    out.append('<p>' + inline(' '.join(buf)) + '</p>')

page = '''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>GoblinScript Reference</title>
<style>
:root { --bg: #121110; --fg: #ede5d5; --dim: #a3998a; --line: #3b352b; --panel: #24211c; --gold: #cca350; }
@media (prefers-color-scheme: light) { :root:not([data-theme="dark"]) { --bg: #fbf8f2; --fg: #221e18; --dim: #6b6258; --line: #ddd3c2; --panel: #f1ebdf; --gold: #8a6a20; } }
:root[data-theme="light"] { --bg: #fbf8f2; --fg: #221e18; --dim: #6b6258; --line: #ddd3c2; --panel: #f1ebdf; --gold: #8a6a20; }
body { margin: 0; background: var(--bg); color: var(--fg); font: 14px/1.5 "Inter", system-ui, sans-serif; }
main { max-width: 900px; margin: 0 auto; padding: 16px 16px 48px; }
h1 { font-size: 22px; margin: 8px 0 12px; } h2 { font-size: 17px; margin: 28px 0 8px; color: var(--gold); } h3 { font-size: 14.5px; margin: 20px 0 6px; } h4 { font-size: 13.5px; margin: 16px 0 6px; }
a { color: var(--gold); }
code { font: 12.5px "JetBrains Mono", ui-monospace, monospace; background: var(--panel); border-radius: 3px; padding: 0 3px; }
pre { background: var(--panel); border: 1px solid var(--line); border-radius: 4px; padding: 8px 10px; overflow-x: auto; } pre code { padding: 0; background: none; }
table { border-collapse: collapse; width: 100%; margin: 8px 0; display: block; overflow-x: auto; }
th, td { border: 1px solid var(--line); padding: 4px 8px; text-align: left; vertical-align: top; } th { background: var(--panel); }
blockquote { margin: 8px 0; padding: 6px 12px; border-left: 3px solid var(--gold); color: var(--dim); }
hr { border: none; border-top: 1px solid var(--line); margin: 20px 0; }
</style></head><body><main>
''' + '\n'.join(out) + '\n</main></body></html>\n'
open(os.path.join(ROOT, "ui-mockup", "goblinscript.html"), "w", encoding="utf-8").write(page)
print("wrote ui-mockup/goblinscript.html", len(page))
