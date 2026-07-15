#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""twatch_web — read-only web view over the Track T watcher state.

Two faces, one set of renderers:

  * live Flask UI (`--serve`, the default) — the running-daemon dashboard with
    a self-refreshing progress bar, recent runs, regressions and reports, plus
    server-rendered /bench and /conformance pages.
  * static export (`--static --out DIR`) — writes self-contained dashboard.html,
    bench.html and conformance.html into DIR (normally tstate/), so the results
    are viewable straight from git without the daemon, and the watcher can
    commit them per SHA.

Data sources, all under tstate/:
    runs-<host>.ndjson    per-run history
    <host>.json           open regressions
    reports/<utc>.md      published per-SHA reports
    bench.tsv             tracked benchmark timings (incl. the `fpc` level)
    conformance.tsv       per-test FPC-suite results (status/category/tag)
    TSTATE.md             human index

No mutations, no auth — the Flask face binds 127.0.0.1 by default.
"""

import argparse
import html
import json
import os

TSTATE = "devdocs/progress/tstate"
CLONE = "."

STYLE = """
 body{font-family:system-ui,sans-serif;margin:1.5em;max-width:72em;
      background:#111;color:#ddd}
 h1{font-size:1.3em} h2{font-size:1.05em;margin-top:1.6em}
 a{color:#8cf} code{color:#8cf} .dim{color:#888}
 table{border-collapse:collapse;width:100%;font-size:.9em;margin-top:.4em}
 td,th{padding:.25em .6em;border-bottom:1px solid #333;text-align:left}
 th{color:#aaa}
 .GREEN,.pass{color:#4c4} .RED,.fail{color:#f55;font-weight:bold}
 .skip{color:#c93} .auto{color:#777}
 .num{text-align:right;font-variant-numeric:tabular-nums}
 nav{margin:.3em 0 1em;font-size:.95em} nav a{margin-right:1.2em}
 .card{display:inline-block;border:1px solid #333;border-radius:6px;
       padding:.7em 1.1em;margin:.3em .6em .3em 0;background:#181818}
 .big{font-size:1.4em;font-weight:bold} .tag{font-size:.8em;padding:0 .4em;
       border-radius:3px;background:#333}
 .bar{display:inline-block;height:.8em;background:#4c4;border-radius:2px;
      vertical-align:middle}
 .barf{background:#69f} .win{color:#4c4} .lose{color:#f80}
 input{background:#222;color:#ddd;border:1px solid #444;padding:.2em .4em}
"""

NAV = ('<nav><a href="{d}">Dashboard</a><a href="{b}">Benchmarks</a>'
       '<a href="{c}">FPC conformance</a><a href="{board}">Board</a></nav>')


# ------------------------------------------------------------- data readers ---

def _rj(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def read_runs(tdir):
    runs, regs, reports = [], [], []
    if os.path.isdir(tdir):
        for fn in sorted(os.listdir(tdir)):
            p = os.path.join(tdir, fn)
            if fn.startswith("runs-") and fn.endswith(".ndjson"):
                with open(p) as f:
                    runs += [json.loads(ln) for ln in f if ln.strip()]
            elif fn.endswith(".json"):
                regs += _rj(p).get("open_regressions", [])
        rdir = os.path.join(tdir, "reports")
        if os.path.isdir(rdir):
            reports = sorted(os.listdir(rdir))
    runs.sort(key=lambda r: r.get("date", ""))
    return runs, regs, reports


CROSS_TARGETS = ("i386", "arm32", "aarch64", "riscv32", "riscv64",
                 "arm", "xtensa", "riscv")


def read_jobs(tdir):
    """The last full tier's per-job status map from <host>.json, grouped by job
    family (the part before '#'). Returns {host: {family: Counter(verdict)}}
    plus the recorded last_full meta. Lets the dashboard show that `full` really
    spans the cross matrix — and flag a target that silently drops to ~0 jobs."""
    out, meta = {}, {}
    if not os.path.isdir(tdir):
        return out, meta
    for fn in sorted(os.listdir(tdir)):
        if not fn.endswith(".json"):
            continue
        d = _rj(os.path.join(tdir, fn))
        jobs = d.get("jobs")
        if not isinstance(jobs, dict) or not jobs:
            continue
        host = d.get("host") or fn[:-5]
        fam = {}
        for k, v in jobs.items():
            g = k.split("#")[0]
            fam.setdefault(g, {})
            fam[g][v] = fam[g].get(v, 0) + 1
        out[host] = fam
        meta[host] = d.get("last_full") or {}
    return out, meta


def read_bench(tdir):
    """bench.tsv -> list of {date,host,sha,workload,level,ms}."""
    rows = []
    try:
        with open(os.path.join(tdir, "bench.tsv")) as f:
            for ln in f:
                if ln.startswith("#") or not ln.strip():
                    continue
                c = ln.rstrip("\n").split("\t")
                if len(c) >= 6:
                    try:
                        ms = float(c[5])
                    except ValueError:
                        continue
                    rows.append({"date": c[0], "host": c[1], "sha": c[2],
                                 "workload": c[3], "level": c[4], "ms": ms})
    except OSError:
        pass
    return rows


def read_conf(tdir):
    """conformance.tsv -> list of {status,name,category,tag,reason}."""
    rows = []
    try:
        with open(os.path.join(tdir, "conformance.tsv")) as f:
            for ln in f:
                if ln.startswith("#") or not ln.strip():
                    continue
                c = ln.rstrip("\n").split("\t")
                if len(c) >= 4:
                    rows.append({"status": c[0], "name": c[1], "category": c[2],
                                 "tag": c[3], "reason": c[4] if len(c) > 4 else ""})
    except OSError:
        pass
    return rows


def _page(title, body, links):
    return ("<!doctype html><html><head><meta charset='utf-8'>"
            "<meta name='viewport' content='width=device-width,initial-scale=1'>"
            "<title>%s</title><style>%s</style></head><body>%s%s</body></html>"
            % (html.escape(title), STYLE, NAV.format(**links), body))


# --------------------------------------------------------------- renderers ---

def render_dashboard(tdir, links):
    runs, regs, reports = read_runs(tdir)
    last = runs[-1] if runs else {}
    verdict = last.get("verdict", "?")
    host = last.get("host") or "?"
    cards = [
        "<div class=card><div class=dim>host</div><div class=big>%s</div></div>"
        % html.escape(host),
        "<div class=card><div class=dim>last verdict</div>"
        "<div class='big %s'>%s</div><div class=dim>%s (%s)</div></div>"
        % (verdict, verdict, html.escape(last.get("sha", "")[:12]),
           html.escape(last.get("tier", "?"))),
        "<div class=card><div class=dim>last tested</div><div>%s</div></div>"
        % html.escape(last.get("date", "?")),
    ]
    reg_html = ("none" if not regs else "<br>".join(
        "<span class=RED>%s</span> bad <code>%s</code>"
        % (html.escape(r.get("job", "?")), html.escape(r.get("bad", "")[:12]))
        for r in regs))
    runtab = ("<tr><th>date<th>sha<th>tier<th>verdict<th>wall"
              "<th>new red<th>fixed</tr>")
    for r in reversed(runs[-40:]):
        runtab += ("<tr><td>%s<td><code>%s</code><td>%s<td class=%s>%s"
                   "<td class=num>%ss<td class=RED>%s<td class=GREEN>%s</tr>" % (
                       html.escape(r.get("date", "")),
                       html.escape(r.get("sha", "")[:12]),
                       html.escape(r.get("tier", "")), r.get("verdict", "?"),
                       r.get("verdict", "?"), r.get("wall", ""),
                       html.escape(" ".join(r.get("new_red", []))),
                       html.escape(" ".join(r.get("fixed", [])))))
    rep_html = "<br>".join(
        "<a href='reports/%s'>%s</a>" % (html.escape(n), html.escape(n))
        for n in reversed(reports[-30:])) or "none"
    cov = render_coverage(tdir)
    body = ("<h1>Track T dashboard</h1>%s"
            "<h2>Open regressions</h2><div>%s</div>"
            "%s"
            "<h2>Recent runs</h2><table>%s</table>"
            "<h2>Reports</h2><div>%s</div>"
            % ("".join(cards), reg_html, cov, runtab, rep_html))
    return _page("Track T dashboard", body, links)


def render_coverage(tdir):
    """`full` tier per-target job coverage — proves it spans the cross matrix
    and surfaces a target that has silently dropped to near-zero jobs."""
    jobs, meta = read_jobs(tdir)
    if not jobs:
        return ""
    out = []
    for host in sorted(jobs):
        fam = jobs[host]

        def bucket(g):
            for t in CROSS_TARGETS:
                if ("-%s" % t) in g or g.endswith(t):
                    return "cross"
            return "native"
        # core per-arch suites (test-i386, test-aarch64, …) — the ones that
        # should carry the fuller Pascal battery. Flag one "thin" only relative
        # to its peers, so a target silently dropping stands out; the 1-job aux
        # checks (sqlite-threads-<arch>) are cross but never peer-comparable.
        core = {g: sum(fam[g].values()) for g in fam
                if bucket(g) == "cross" and "sqlite" not in g}
        core_max = max(core.values()) if core else 0
        rows = ""
        ntot = ctot = 0
        for g in sorted(fam, key=lambda g: (bucket(g) == "native", g)):
            v = fam[g]
            n = sum(v.values())
            b = bucket(g)
            if b == "cross":
                ctot += n
            else:
                ntot += n
            bad = v.get("fail", 0) + v.get("red", 0)
            cls = "fail" if bad else "pass"
            thin = " ⚠ thin" if g in core and core_max and n < core_max / 4 else ""
            rows += ("<tr><td><code>%s</code><td>%s<td class='num %s'>%d"
                     "<td class=dim>%s%s</tr>" % (
                         html.escape(g), b, cls, n,
                         html.escape(", ".join("%s:%d" % (k, v[k])
                                     for k in sorted(v))), thin))
        m = meta.get(host, {})
        out.append(
            "<h2>Tier coverage — %s <span class=dim>(last full %s, %ss, %s)</span></h2>"
            "<p class=dim>native jobs %d · cross jobs %d across the qemu matrix. "
            "A cross target dropping to ~0 (or ⚠ thin) means it stopped being "
            "exercised.</p>"
            "<table><tr><th>job family<th>kind<th class=num>jobs<th>verdicts</tr>"
            "%s</table>" % (
                html.escape(host), html.escape(m.get("sha", "")[:12]),
                m.get("wall", "?"), m.get("verdict", "?"), ntot, ctot, rows))
    return "".join(out)


def render_bench(tdir, links):
    rows = read_bench(tdir)
    # latest ms per (workload, level), preserving first-seen workload order.
    latest, order = {}, []
    for r in rows:
        if r["workload"] not in order:
            order.append(r["workload"])
        latest[(r["workload"], r["level"])] = r
    levels = ["-O0", "-O2", "-O3", "fpc"]
    head = "<tr><th>workload" + "".join("<th>%s" % l for l in levels)
    head += "<th>-O3 vs -O0<th>pxx-O2 vs fpc</tr>"
    tab = head
    for w in order:
        cells = ["<td><code>%s</code>" % html.escape(w)]
        vals = {}
        for l in levels:
            r = latest.get((w, l))
            if r:
                vals[l] = r["ms"]
                cells.append("<td class=num>%.1f" % r["ms"])
            else:
                cells.append("<td class=dim>—")
        o3 = ("%.2fx" % (vals["-O0"] / vals["-O3"])
              if "-O0" in vals and "-O3" in vals and vals["-O3"] else "—")
        if "-O2" in vals and "fpc" in vals and vals["fpc"]:
            ratio = vals["-O2"] / vals["fpc"]
            cls = "win" if ratio <= 1.0 else "lose"
            fpc = "<span class=%s>%.2fx</span>" % (
                cls, ratio) if ratio >= 1 else "<span class=win>%.2fx faster</span>" % (
                1 / ratio)
        else:
            fpc = "—"
        cells.append("<td class=num>%s" % o3)
        cells.append("<td class=num>%s" % fpc)
        tab += "<tr>" + "".join(cells) + "</tr>"
    # history (last 60 rows)
    hist = "<tr><th>date<th>sha<th>workload<th>level<th>ms</tr>"
    for r in rows[-60:][::-1]:
        hist += ("<tr><td>%s<td><code>%s</code><td>%s<td>%s<td class=num>%.1f</tr>"
                 % (html.escape(r["date"]), html.escape(r["sha"][:12]),
                    html.escape(r["workload"]), html.escape(r["level"]), r["ms"]))
    note = ("<p class=dim>ms = min wall over repeated runs, same host. "
            "<code>-O3 vs -O0</code> = pxx speedup; <code>pxx-O2 vs fpc</code> "
            "compares pxx -O2 against FPC -O2 on the same source "
            "(&gt;1x = slower than FPC). Only FPC-comparable workloads carry an "
            "<code>fpc</code> column.</p>")
    body = ("<h1>Benchmarks</h1>%s<h2>Latest per workload</h2><table>%s</table>"
            "<h2>History</h2><table>%s</table>" % (note, tab, hist))
    return _page("Track T benchmarks", body, links)


def render_conf(tdir, links):
    rows = read_conf(tdir)
    if not rows:
        body = ("<h1>FPC conformance</h1><p class=dim>No conformance.tsv yet — "
                "the watcher writes it once the FPC test suite is installed "
                "(<code>tools/install_lib_candidates.sh fpc-testsuite</code>) "
                "and an idle run publishes it.</p>")
        return _page("Track T FPC conformance", body, links)
    tot = {}
    for r in rows:
        tot[r["status"]] = tot.get(r["status"], 0) + 1
    tags = {}
    for r in rows:
        if r["status"] == "skip":
            tags[r["tag"]] = tags.get(r["tag"], 0) + 1
    npass = tot.get("pass", 0)
    nfail = tot.get("fail", 0)
    nskip = tot.get("skip", 0)
    nauto = tot.get("auto", 0)
    wontfix = tags.get("wontfix", 0)
    # adjusted rate: exclude auto-gated and wontfix (can never pass by design).
    denom = npass + nfail + nskip - wontfix
    rate = (100.0 * npass / denom) if denom else 0.0
    cards = [
        "<div class=card><div class=dim>pass</div><div class='big pass'>%d</div></div>" % npass,
        "<div class=card><div class=dim>fail</div><div class='big fail'>%d</div></div>" % nfail,
        "<div class=card><div class=dim>skip</div><div class='big skip'>%d</div>"
        "<div class=dim>gap %d · wontfix %d · untriaged %d</div></div>" % (
            nskip, tags.get("gap", 0), wontfix, tags.get("untriaged", 0)),
        "<div class=card><div class=dim>auto-gated</div><div class='big auto'>%d</div></div>" % nauto,
        "<div class=card><div class=dim>pass rate (excl. wontfix/auto)</div>"
        "<div class=big>%.1f%%</div></div>" % rate,
    ]
    # per-category breakdown
    cats = {}
    for r in rows:
        c = cats.setdefault(r["category"], {"pass": 0, "fail": 0, "skip": 0, "auto": 0})
        c[r["status"]] = c.get(r["status"], 0) + 1
    ctab = "<tr><th>category<th class=num>pass<th class=num>fail<th class=num>skip<th class=num>auto</tr>"
    for c in sorted(cats):
        v = cats[c]
        ctab += ("<tr><td><code>%s</code><td class='num pass'>%d<td class='num fail'>%d"
                 "<td class='num skip'>%d<td class='num auto'>%d</tr>" % (
                     html.escape(c), v.get("pass", 0), v.get("fail", 0),
                     v.get("skip", 0), v.get("auto", 0)))
    # full listing (filterable)
    listing = ("<input id=f placeholder='filter…' oninput=\"flt()\">"
               "<table id=lt><tr><th>status<th>name<th>category<th>tag<th>reason</tr>")
    for r in sorted(rows, key=lambda r: (r["status"], r["category"], r["name"])):
        listing += ("<tr><td class=%s>%s<td><code>%s</code><td>%s<td>"
                    "<span class=tag>%s</span><td class=dim>%s</tr>" % (
                        r["status"], r["status"], html.escape(r["name"]),
                        html.escape(r["category"]),
                        html.escape(r["tag"]) if r["tag"] != "-" else "",
                        html.escape(r["reason"])))
    listing += "</table>"
    js = ("<script>function flt(){var q=document.getElementById('f').value"
          ".toLowerCase(),t=document.getElementById('lt').rows;for(var i=1;i<t.length;"
          "i++){t[i].style.display=t[i].textContent.toLowerCase().indexOf(q)>=0?'':'none'}}"
          "</script>")
    note = ("<p class=dim>FPC's own test suite run against the pascal26 Pascal "
            "frontend. <b>wontfix</b> = probes FPC internals / intentional "
            "divergence (never counts against us); <b>gap</b> = real "
            "unimplemented feature; <b>untriaged</b> = skip-listed, not yet "
            "classified; <b>auto-gated</b> = needs suite infra/other targets we "
            "don't model.</p>")
    body = ("<h1>FPC conformance</h1>%s%s<h2>By category</h2><table>%s</table>"
            "<h2>All tests</h2>%s%s" % (
                note, "".join(cards), ctab, listing, js))
    return _page("Track T FPC conformance", body, links)


# ------------------------------------------------------------------ static ---

def export_static(clone, out):
    tdir = os.path.join(clone, TSTATE)
    os.makedirs(out, exist_ok=True)
    # BOARD.html is gitignored (generated); BOARD.md is the tracked, always-present
    # board that GitHub renders — link that so the static dashboard never 404s.
    links = {"d": "dashboard.html", "b": "bench.html",
             "c": "conformance.html", "board": "../BOARD.md"}
    pages = {"dashboard.html": render_dashboard,
             "bench.html": render_bench,
             "conformance.html": render_conf}
    for fn, fn_render in pages.items():
        with open(os.path.join(out, fn), "w") as f:
            f.write(fn_render(tdir, links))
    print("twatch_web: wrote %s" % ", ".join(sorted(pages)))


# -------------------------------------------------------------------- serve ---

def serve(clone, host, port):
    from flask import Flask, jsonify, abort, Response
    app = Flask(__name__)
    tdir = os.path.join(clone, TSTATE)
    links = {"d": "/", "b": "/bench", "c": "/conformance",
             "board": "/board"}

    LIVE = """<!doctype html><html><head><meta charset="utf-8">
<title>Track T</title><style>%s
 #bar{background:#333;height:1em;width:100%%;border-radius:3px;margin:.4em 0}
 #fill{background:#4c4;height:100%%;width:0;border-radius:3px}
</style></head><body>%s
<h1>Track T — <span id=host></span> <span id=phase class=dim></span></h1>
<div id=pubwarn style="display:none;background:#822;color:#fff;padding:.5em .7em;border-radius:4px;margin:.4em 0"></div>
<div id=run style="display:none">
 <div id=bar><div id=fill></div></div>
 <div class=dim><span id=pct></span>%%%% — <span id=njobs></span> jobs,
 <span id=elapsed></span>s elapsed, eta ~<span id=eta></span>s —
 <span id=sha></span> (<span id=tier></span>)</div>
 <div id=reds class=RED></div></div>
<h2>Open regressions</h2><div id=regs>none</div>
<!--COVERAGE-->
<h2>Recent runs</h2><table id=runs></table>
<h2>Reports</h2><div id=reports></div>
<script>
async function j(u){return (await fetch(u)).json()}
function esc(s){const d=document.createElement('i');d.textContent=s;return d.innerHTML}
async function tick(){
  const l=await j('/api/live');
  host.textContent=l.watch.host||'?';phase.textContent=l.watch.phase||'daemon off';
  const p=l.pubhealth||{};
  if(p.consec_drops){pubwarn.style.display='block';
    pubwarn.textContent='⚠ PUBLISHING BLOCKED — '+p.consec_drops+
      ' consecutive drop'+(p.consec_drops==1?'':'s')+' (last: '+(p.last_reason||'conflict')+')'+
      (p.behind?'; '+p.behind+' behind origin':'')+
      ' — stale verdicts discarded each cycle; usually a human edit to a co-edited tstate file, clears on its own.';}
  else{pubwarn.style.display='none';}
  const t=l.watch.phase=='testing'&&l.live.ts;run.style.display=t?'block':'none';
  if(t){const v=l.live;fill.style.width=v.pct+'%%';pct.textContent=v.pct;
    njobs.textContent=v.done+'/'+v.total;elapsed.textContent=v.elapsed;
    eta.textContent=v.eta||'?';sha.textContent=(l.watch.sha||'').slice(0,12);
    tier.textContent=v.tier;reds.textContent=v.red&&v.red.length?('RED: '+v.red.join(', ')):'';}
}
async function once(){
  const h=await j('/api/history');
  regs.innerHTML=h.open_regressions.length?h.open_regressions.map(r=>
    '<span class=RED>'+esc(r.job)+'</span> bad <code>'+r.bad.slice(0,12)+'</code>').join('<br>'):'none';
  runs.innerHTML='<tr><th>date<th>sha<th>tier<th>verdict<th>wall<th>new red<th>fixed</tr>'+
    h.runs.slice(-40).reverse().map(r=>'<tr><td>'+esc(r.date)+'</td><td><code>'+
      r.sha.slice(0,12)+'</code></td><td>'+esc(r.tier)+'</td><td class='+r.verdict+'>'+
      r.verdict+'</td><td>'+r.wall+'s</td><td class=RED>'+esc((r.new_red||[]).join(' '))+
      '</td><td class=GREEN>'+esc((r.fixed||[]).join(' '))+'</td></tr>').join('');
  reports.innerHTML=h.reports.slice(-30).reverse().map(r=>'<a href="/reports/'+r+'">'+r+'</a>').join('<br>');
}
tick();once();setInterval(tick,2000);setInterval(once,30000);
</script></body></html>""" % (STYLE, NAV.format(**links))

    @app.route("/")
    def index():
        # inject the tier-coverage table fresh each load (the rest is live JS)
        return LIVE.replace("<!--COVERAGE-->", render_coverage(tdir))

    @app.route("/bench")
    def bench():
        return render_bench(tdir, links)

    @app.route("/conformance")
    def conformance():
        return render_conf(tdir, links)

    @app.route("/board")
    def board():
        # BOARD.html is gitignored/generated — build it on demand if missing,
        # then serve it; fall back to the tracked BOARD.md as text.
        import subprocess
        p = os.path.join(clone, "devdocs/progress/BOARD.html")
        if not os.path.exists(p):
            try:
                subprocess.run(["sh", os.path.join(clone, "tools/progress.sh"),
                                "board-md"], cwd=clone, capture_output=True,
                               timeout=30)
            except (OSError, subprocess.SubprocessError):
                pass
        if os.path.exists(p):
            with open(p, errors="replace") as f:
                return Response(f.read(), mimetype="text/html")
        md = os.path.join(clone, "devdocs/progress/BOARD.md")
        if os.path.exists(md):
            with open(md, errors="replace") as f:
                return Response(f.read(), mimetype="text/plain")
        abort(404)

    @app.route("/api/live")
    def api_live():
        return jsonify({
            "watch": _rj(os.path.join(clone, ".testmgr", "watch.json")),
            "live": _rj(os.path.join(clone, ".testmgr", "live.json")),
            "pubhealth": _rj(os.path.join(clone, ".testmgr", "pubhealth.json"))})

    @app.route("/api/history")
    def api_history():
        runs, regs, reports = read_runs(tdir)
        return jsonify({"runs": runs[-1000:], "open_regressions": regs,
                        "reports": reports})

    @app.route("/reports/<name>")
    def report(name):
        if "/" in name or ".." in name or not name.endswith(".md"):
            abort(404)
        p = os.path.join(tdir, "reports", name)
        if not os.path.exists(p):
            abort(404)
        with open(p, errors="replace") as f:
            return Response(f.read(), mimetype="text/plain")

    app.run(host=host, port=port)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--clone", default=".")
    ap.add_argument("--static", action="store_true",
                    help="write static dashboard.html/bench.html/conformance.html")
    ap.add_argument("--out", help="output dir for --static (default <clone>/%s)" % TSTATE)
    ap.add_argument("--port", type=int, default=8377)
    ap.add_argument("--host", default="127.0.0.1",
                    help="bind address for the live server (default loopback)")
    a = ap.parse_args()
    clone = os.path.abspath(os.path.expanduser(a.clone))
    if a.static:
        export_static(clone, a.out or os.path.join(clone, TSTATE))
    else:
        serve(clone, a.host, a.port)


if __name__ == "__main__":
    main()
