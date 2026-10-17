#!/usr/bin/env python3
"""AI CONTEXT: Export the in-app Wireless Support guide to kevmarl.com; never deploy.
Adapted from Autohop's Scripts/export_support_website.py. Swift evaluates the real
WirelessSupportGuide model with a display-only Color shim, so the website mirrors
Wireless/SupportContent.swift exactly. Keep every WirelessSupportBlock case covered.
Use --exclude for sections that describe features not yet in a released build.

Usage: python3 Scripts/export_support_website.py /path/to/kevmarl-site [--exclude id,id]
Then run `node build.js` in the site folder and preview before deploying.
"""
import argparse, html, json, re, subprocess, tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('site', type=Path)
parser.add_argument('--exclude', default='', help='comma-separated section ids to omit')
args = parser.parse_args()
excluded = {s for s in args.exclude.split(',') if s}

source = (root/'Wireless/SupportContent.swift').read_text().replace('import SwiftUI', '''import Foundation
struct Color {
 init(red: Double, green: Double, blue: Double) {}
 static let purple = Color(red: 0, green: 0, blue: 0)
}''')
source += '''
func block(_ b: WirelessSupportBlock) -> [String: Any] {
 switch b {
 case .paragraph(let s): return ["kind":"p", "text":s]
 case .heading(let s): return ["kind":"h3", "text":s]
 case .bullets(let a): return ["kind":"ul", "items":a]
 case .steps(let a): return ["kind":"ol", "items":a]
 case .callout(let style, let s):
  let name: String
  switch style { case .tip: name = "tip"; case .note: name = "note"; case .warning: name = "warning" }
  return ["kind":"aside", "style":name, "text":s]
 case .table(let r): return ["kind":"table", "rows":r]
 }
}
let data = WirelessSupportGuide.sections.map { ["id":$0.id, "title":$0.title, "summary":$0.summary, "blocks":$0.blocks.map(block)] as [String:Any] }
print(String(data: try JSONSerialization.data(withJSONObject:data, options:[.sortedKeys]), encoding:.utf8)!)
'''
with tempfile.TemporaryDirectory() as d:
    p = Path(d)/'export.swift'
    p.write_text(source)
    sections = json.loads(subprocess.check_output(['swift', str(p)], text=True))

unknown = excluded - {s['id'] for s in sections}
if unknown:
    raise SystemExit(f'Unknown section id(s): {", ".join(sorted(unknown))}')
sections = [s for s in sections if s['id'] not in excluded]

def text(s):
    s = html.escape(s, quote=False)
    s = re.sub(r'\*\*(.*?)\*\*', r'<strong>\1</strong>', s)
    s = re.sub(r'\[([^\]]+)\]\((https?://[^)\s]+)\)', r'<a href="\2">\1</a>', s)
    return s.replace('\n', '<br>')

LABELS = {'tip': 'Tip', 'note': 'Note', 'warning': 'Important'}
def render(b):
    k = b['kind']
    if k in ('p', 'h3'):
        return f'<{k}>{text(b["text"])}</{k}>'
    if k == 'aside':
        body = text(b['text'])
        if not body.startswith('<strong>'):
            body = f'<strong>{LABELS[b["style"]]}:</strong> {body}'
        return f'<aside class="callout callout-{b["style"]}">{body}</aside>'
    if k in ('ul', 'ol'):
        return f'<{k}>' + ''.join(f'<li>{text(i)}</li>' for i in b['items']) + f'</{k}>'
    if k == 'table':
        return '<table><tbody>' + ''.join('<tr>' + ''.join(f'<td>{text(x)}</td>' for x in r) + '</tr>' for r in b['rows']) + '</tbody></table>'
    raise ValueError(k)

sidebar = ''.join(f'<li><a href="#{s["id"]}" class="section-link">{text(s["title"])}</a></li>' for s in sections)
topics = ' · '.join(f'<a href="#{s["id"]}">{text(s["title"])}</a>' for s in sections)
body = '\n'.join(
    f'    <section class="doc-section" id="{s["id"]}"><h2>{text(s["title"])}</h2>\n'
    f'<p class="section-summary">{text(s["summary"])}</p>\n'
    + '\n'.join(render(b) for b in s['blocks']) + '\n</section>'
    for s in sections)

page_path = args.site/'wireless-support.html'
page = page_path.read_text()
def replace_region(page, name, content):
    start, end = f'<!-- {name}_START -->', f'<!-- {name}_END -->'
    i, j = page.index(start) + len(start), page.index(end)
    return page[:i] + '\n' + content + '\n' + page[j:]
page = replace_region(page, 'WIRELESS_SIDEBAR', '      ' + sidebar)
page = replace_region(page, 'WIRELESS_GUIDE',
    '    <!-- GENERATED from Wireless/SupportContent.swift by Wireless/Scripts/export_support_website.py. Do not hand-edit. -->\n'
    f'    <nav class="guide-topics" aria-label="Guide topics">{topics}</nav>\n' + body)
page_path.write_text(page)
print(f'Exported {len(sections)} sections to {page_path}' + (f' (omitted: {", ".join(sorted(excluded))})' if excluded else ''))
