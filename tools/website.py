#!/usr/bin/env python3
"""Build the website's shared parts.

Every page in website/ keeps only its own content between <!-- content --> and <!-- /content -->; this script
rewrites everything around it (head, header and tabs, sidebar, footer) from one template, and generates
website/packages.html from the ports tree. Run it after changing a page, the ports or VERSION:

    tools/website.py
"""
import html, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB = os.path.join(ROOT, 'website')
# the release the website offers for download (the one published on GitHub)
RELEASE = os.environ.get('SITE_RELEASE') or open(os.path.join(WEB, 'release')).read().strip()
GH = 'https://github.com/tortr-rs/systemLinux'
ISO = f'{GH}/releases/download/v{RELEASE}/systemLinux-{RELEASE}-x86_64.iso'

# file, tab label, page title, has the sidebar
PAGES = [
    ('index.html', 'Home', 'A small source-based GNU/Linux distribution', True),
    ('news.html', 'News', 'News', True),
    ('about.html', 'About', 'About', True),
    ('download.html', 'Download', 'Download', True),
    ('handbook.html', 'Handbook', 'Handbook', False),
    ('get.html', 'get', 'The get package tool', True),
    ('packages.html', 'Packages', 'Packages', False),
    ('packaging.html', 'Packaging', 'Packaging guide', False),
    ('system.html', 'System', 'System', True),
]

# The Handbook: one page per chapter (website/handbook-SLUG.html, content only), in reading order, by part.
# handbook.html is its table of contents.
HANDBOOK = [
    ('Installing systemLinux', [
        ('about', 'About the installation'),
        ('media', 'Getting and writing the ISO'),
        ('boot', 'Booting the live system'),
        ('network', 'Getting online'),
        ('disks', 'Preparing the disks'),
        ('stage', 'Installing the stage'),
        ('config', 'Configuring the system'),
        ('kernel', 'The kernel and the initramfs'),
        ('bootloader', 'The bootloader'),
        ('finish', 'Users and the first boot'),
        ('installer', 'The automatic installer'),
    ]),
    ('Working with systemLinux', [
        ('services', 'Services with dinit'),
        ('get', 'Installing software with get'),
        ('users', 'Users, groups and sudo'),
        ('networking', 'Networking'),
        ('hardware', 'Firmware, graphics and sound'),
        ('desktop', 'A desktop: sway or i3'),
        ('maintenance', 'Keeping the system up to date'),
        ('troubleshooting', 'Troubleshooting and recovery'),
    ]),
    ('Reference', [
        ('cmdline', 'Boot options'),
        ('files', 'Where things are'),
    ]),
]
HB_ORDER = [(slug, title) for _, chapters in HANDBOOK for slug, title in chapters]

def hb_number(slug):
    return [s for s, _ in HB_ORDER].index(slug) + 1

def hb_nav(current):
    out = ['<nav class="hb-nav">']
    for part, chapters in HANDBOOK:
        out.append(f'<h3>{part}</h3><ol start="{hb_number(chapters[0][0])}">')
        for slug, title in chapters:
            on = ' class="on"' if slug == current else ''
            out.append(f'<li><a href="handbook-{slug}.html"{on}>{title}</a></li>')
        out.append('</ol>')
    out.append('</nav>')
    return '\n'.join(out)

def hb_toc():
    out = ['<h1>The systemLinux Handbook</h1>',
           '<p class="sub">How to install systemLinux by hand, step by step, and how to use it afterwards. Read the '
           'installation part in order; the second part is a reference you come back to.</p>',
           '<div class="note">Short on time? The <a href="handbook-installer.html">automatic installer</a> does every '
           'installation step for you. The chapters still explain what it did.</div>']
    for part, chapters in HANDBOOK:
        out.append(f'<h2>{part}</h2><ol class="hb-toc" start="{hb_number(chapters[0][0])}">')
        for slug, title in chapters:
            out.append(f'<li><a href="handbook-{slug}.html">{title}</a></li>')
        out.append('</ol>')
    return '\n'.join(out)

def hb_page(slug, content):
    i = [s for s, _ in HB_ORDER].index(slug)
    prev = f'<a href="handbook-{HB_ORDER[i-1][0]}.html">&larr; {HB_ORDER[i-1][1]}</a>' if i > 0 else '<a href="handbook.html">&larr; Contents</a>'
    nxt = f'<a href="handbook-{HB_ORDER[i+1][0]}.html">{HB_ORDER[i+1][1]} &rarr;</a>' if i + 1 < len(HB_ORDER) else '<a href="handbook.html">Contents &rarr;</a>'
    pager = f'<div class="hb-pager">{prev}{nxt}</div>'
    return f'<div class="handbook">\n{hb_nav(slug)}\n<article>\n{content}\n{pager}\n</article>\n</div>'

def header(current):
    on = ' class="on"'
    tabs = ''.join(f'<a href="{f}"{on if f == current else ""}>{label}</a>' for f, label, _, _ in PAGES)
    return f'''<!-- header -->
<header class="masthead"><div class="wrap">
<a class="brand" href="index.html"><img src="logo.svg" alt="" width="40" height="40">systemLinux</a>
<div class="tagline">source-based &middot; dinit &middot; no systemd<br>owned by everyone who uses it</div>
</div></header>
<nav class="tabs"><div class="wrap">{tabs}<a href="{GH}">Source</a></div></nav>
<!-- /header -->'''

def sidebar():
    return f'''<!-- side -->
<aside class="side">
<div class="box"><h3>Get systemLinux {RELEASE}</h3><div class="in">
<p style="margin:.2em 0 .6em"><a class="btn" href="{ISO}">Download the ISO</a></p>
<p class="small muted" style="margin:0">x86_64, UEFI and legacy BIOS. <a href="download.html">Checksums and notes</a></p>
</div></div>
<div class="box"><h3>Documentation</h3><div class="in"><ul>
<li><a href="handbook.html">Handbook</a>: installing</li>
<li><a href="get.html">get</a>: installing software</li>
<li><a href="packaging.html">Packaging guide</a>: writing ports</li>
<li><a href="system.html">System</a>: services and limits</li>
<li><a href="{GH}/blob/main/CHANGELOG.md">Changelog</a></li>
</ul></div></div>
<div class="box"><h3>Get involved</h3><div class="in"><ul>
<li><a href="{GH}">Source on GitHub</a></li>
<li><a href="{GH}/issues">Report a bug</a></li>
<li><a href="{GH}/tree/main/ports">Ports tree</a></li>
<li><a href="packaging.html">Add a port</a></li>
</ul></div></div>
</aside>
<!-- /side -->'''

FOOTER = f'''<!-- footer -->
<footer><div class="wrap">
<span>systemLinux {RELEASE}</span><span>Owned by everyone who uses it.</span><span>Tux by Larry Ewing and The GIMP (<a href="about.html#mascot">credits</a>)</span>
<a href="{GH}">Source</a><a href="{GH}/issues">Issues</a><a href="{GH}/releases">Releases</a>
</div></footer>
<!-- /footer -->'''

def content_of(text):
    m = re.search(r'<!-- content -->\n?(.*?)\n?<!-- /content -->', text, re.S)
    if m: return m.group(1)
    # the old page layout: content sits between the <hr> after the menu and the <hr> before the footer
    body = text.split('<hr>', 1)[1]
    return body.rsplit('<hr>', 1)[0].strip()

def render(fname, label, title, side, content, tab=None):
    full_title = 'systemLinux' if fname == 'index.html' else f'{title} - systemLinux'
    if fname == 'index.html': full_title = f'systemLinux: {title.lower()}'
    hero = ''
    if fname == 'index.html':
        hero = f'''<section class="hero"><div class="wrap">
<img src="tux.svg" alt="Tux, the systemLinux mascot" width="110" style="float:right;margin-left:1em">
<h1>systemLinux</h1>
<p class="lead">A small x86_64 GNU/Linux distribution: dinit instead of systemd, the newest kernel, and software
built from source with <code>get</code>, from a ports tree of over a thousand recipes. Nobody owns it and nobody profits
from it.</p>
<div class="actions"><a class="btn" href="{ISO}">Download {RELEASE}</a><a class="btn ghost" href="handbook.html">Read the handbook</a><a class="btn ghost" href="packages.html">Browse packages</a></div>
</div></section>'''
    return f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{full_title}</title>
<link rel="icon" type="image/svg+xml" href="logo.svg">
<link rel="stylesheet" href="style.css">
</head>
<body>
{header(tab or fname)}
{hero}
<div class="wrap page">
<main class="main">
<!-- content -->
{content}
<!-- /content -->
</main>
{sidebar() if side else ''}
</div>
{FOOTER}
</body>
</html>
'''

def recipe(path):
    d = {}
    for line in open(path, errors='replace'):
        m = re.match(r'([a-z_]+)\s*=\s*(.*)', line.rstrip('\n'))
        if m and m.group(1) not in d: d[m.group(1)] = m.group(2).strip().strip('"')
    return d

def packages_content():
    ports = os.path.join(ROOT, 'ports')
    rows = []
    for cat in sorted(os.listdir(ports)):
        cdir = os.path.join(ports, cat)
        if not os.path.isdir(cdir): continue
        for name in sorted(os.listdir(cdir)):
            r = os.path.join(cdir, name, 'recipe')
            if not os.path.isfile(r): continue
            d = recipe(r)
            if not d.get('version') and d.get('url'):  # older recipes: take it from the file name
                m = re.search(r'[-_v](\d+(?:\.\d+)+[a-z]?)(?:[-_.](?:src|source|stable|orig))?\.(?:tar|tgz|tbz|txz|zip)', d['url'].rsplit('/', 1)[-1])
                if m: d['version'] = m.group(1)
            tags = ''
            if name.endswith('-bin'): tags += '<span class="tag">bin</span>'
            if os.path.isdir(os.path.join(cdir, name, 'dinit')): tags += '<span class="tag">service</span>'
            if not d.get('url'): tags += '<span class="tag">meta</span>'
            rows.append(f'<tr><td><span class="cat">{cat}/</span><a href="{GH}/tree/main/ports/{cat}/{name}"><b>{html.escape(name)}</b></a>{tags}</td>'
                        f'<td>{html.escape(d.get("version", ""))}</td><td>{html.escape(d.get("description", ""))}</td></tr>')
    return f'''<h1>Packages</h1>
<p>The ports tree has <b>{len(rows)}</b> packages. Install any of them with <code>get install NAME</code>; dependencies are
built first. <span class="tag">bin</span> ports install the project's own official build instead of compiling it,
<span class="tag">service</span> ports come with a dinit service and <span class="tag">meta</span> ports only pull in other
packages. Missing something? <a href="packaging.html">Write a port</a>.</p>
<input class="search" id="q" type="search" placeholder="Search {len(rows)} packages by name or description" autofocus>
<table class="pkgs"><thead><tr><th>Package</th><th>Version</th><th>Description</th></tr></thead>
<tbody id="rows">
{chr(10).join(rows)}
</tbody></table>
<p class="muted small" id="count"></p>
<script>
(function () {{
  var q = document.getElementById('q'), rows = document.getElementById('rows').rows, count = document.getElementById('count');
  function filter() {{
    var words = q.value.toLowerCase().split(/\\s+/).filter(Boolean), shown = 0;
    for (var i = 0; i < rows.length; i++) {{
      var t = rows[i].textContent.toLowerCase(), ok = words.every(function (w) {{ return t.indexOf(w) >= 0; }});
      rows[i].style.display = ok ? '' : 'none'; if (ok) shown++;
    }}
    count.textContent = words.length ? shown + ' of ' + rows.length + ' packages' : '';
  }}
  q.addEventListener('input', filter);
  if (location.hash.length > 1) {{ q.value = decodeURIComponent(location.hash.slice(1)); filter(); }}
}})();
</script>'''

def main():
    for fname, label, title, side in PAGES:
        path = os.path.join(WEB, fname)
        if fname == 'packages.html':
            content = packages_content()
        elif fname == 'handbook.html':
            content = hb_toc()
        else:
            content = content_of(open(path).read())
        open(path, 'w').write(render(fname, label, title, side, content))
        print('wrote', fname)
    for slug, title in HB_ORDER:
        path = os.path.join(WEB, f'handbook-{slug}.html')
        body = content_of(open(path).read())
        # the page keeps only its own chapter text; the navigation is generated around it
        m = re.search(r'<article>\n(.*)\n<div class="hb-pager">', body, re.S)
        if m: body = m.group(1)
        n = hb_number(slug)
        text = f'<h1><span class="hb-n">{n}.</span> {html.escape(title)}</h1>\n' + re.sub(r'^<h1>.*?</h1>\n?', '', body.strip(), flags=re.S)
        open(path, 'w').write(render(f'handbook-{slug}.html', 'Handbook', f'Handbook: {title}', False, hb_page(slug, text), tab='handbook.html'))
    print('wrote', len(HB_ORDER), 'handbook chapters')

if __name__ == '__main__':
    main()
