#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""twatch_web — read-only Flask UI over the Track T watcher state.

Serves the same facts as `trackt status/watch`, plus browsable history:
recent runs (runs-<host>.ndjson), regression frequency, open regressions,
and the published per-SHA reports.  No mutations, no auth — binds
127.0.0.1 by default; put a reverse proxy in front if you must expose it.

Spawned by `trackt web on` / `trackt start` (web=true in twatch.conf).
"""

import argparse
import json
import os

from flask import Flask, jsonify, abort, Response

app = Flask(__name__)
CLONE = "."
TSTATE = "devdocs/progress/tstate"

PAGE = """<!doctype html><html><head><meta charset="utf-8">
<title>Track T</title><style>
 body{font-family:system-ui,sans-serif;margin:1.5em;max-width:70em;
      background:#111;color:#ddd}
 h1{font-size:1.3em} h2{font-size:1.05em;margin-top:1.6em}
 table{border-collapse:collapse;width:100%%;font-size:.9em}
 td,th{padding:.25em .6em;border-bottom:1px solid #333;text-align:left}
 .GREEN{color:#4c4} .RED{color:#f55;font-weight:bold} .dim{color:#888}
 #bar{background:#333;height:1em;width:100%%;border-radius:3px}
 #fill{background:#4c4;height:100%%;width:0;border-radius:3px}
 code{color:#8cf} a{color:#8cf}
</style></head><body>
<h1>Track T — <span id=host></span> <span id=phase class=dim></span></h1>
<div id=run style="display:none">
 <div id=bar><div id=fill></div></div>
 <div class=dim><span id=pct></span>% — <span id=njobs></span> jobs,
 <span id=elapsed></span>s elapsed, eta ~<span id=eta></span>s —
 <span id=sha></span> (<span id=tier></span>)</div>
 <div id=reds class=RED></div>
</div>
<h2>Open regressions</h2><div id=regs>none</div>
<h2>Recent runs</h2><table id=runs></table>
<h2>Regression finds per day</h2><table id=freq></table>
<h2>Reports</h2><div id=reports></div>
<script>
async function j(u){return (await fetch(u)).json()}
function esc(s){const d=document.createElement('i');d.textContent=s;return d.innerHTML}
async function tick(){
  const l=await j('/api/live');
  document.getElementById('host').textContent=l.watch.host||'?';
  document.getElementById('phase').textContent=l.watch.phase||'daemon off';
  const t=l.watch.phase=='testing'&&l.live.ts;
  document.getElementById('run').style.display=t?'block':'none';
  if(t){const v=l.live;
    document.getElementById('fill').style.width=v.pct+'%';
    document.getElementById('pct').textContent=v.pct;
    document.getElementById('njobs').textContent=v.done+'/'+v.total;
    document.getElementById('elapsed').textContent=v.elapsed;
    document.getElementById('eta').textContent=v.eta||'?';
    document.getElementById('sha').textContent=(l.watch.sha||'').slice(0,12);
    document.getElementById('tier').textContent=v.tier;
    document.getElementById('reds').textContent=v.red.length?('RED: '+v.red.join(', ')):'';}
}
async function once(){
  const h=await j('/api/history');
  document.getElementById('regs').innerHTML=h.open_regressions.length?
    h.open_regressions.map(r=>'<span class=RED>'+esc(r.job)+'</span> bad <code>'+
      r.bad.slice(0,12)+'</code> ('+(r.range||[]).length+' in range)').join('<br>'):'none';
  document.getElementById('runs').innerHTML=
    '<tr><th>date</th><th>sha</th><th>tier</th><th>verdict</th><th>wall</th><th>new red</th><th>fixed</th></tr>'+
    h.runs.slice(-40).reverse().map(r=>'<tr><td>'+esc(r.date)+'</td><td><code>'+
      r.sha.slice(0,12)+'</code></td><td>'+esc(r.tier)+'</td><td class='+r.verdict+'>'+
      r.verdict+'</td><td>'+r.wall+'s</td><td class=RED>'+esc((r.new_red||[]).join(' '))+
      '</td><td class=GREEN>'+esc((r.fixed||[]).join(' '))+'</td></tr>').join('');
  const per={};h.runs.forEach(r=>{const d=r.date.slice(0,10);
    per[d]=per[d]||{runs:0,red:0};per[d].runs++;per[d].red+=(r.new_red||[]).length});
  document.getElementById('freq').innerHTML='<tr><th>day</th><th>runs</th><th>new regressions</th></tr>'+
    Object.keys(per).sort().reverse().map(d=>'<tr><td>'+d+'</td><td>'+per[d].runs+
      '</td><td>'+per[d].red+'</td></tr>').join('');
  document.getElementById('reports').innerHTML=h.reports.slice(-30).reverse()
    .map(r=>'<a href="/reports/'+r+'">'+r+'</a>').join('<br>');
}
tick();once();setInterval(tick,2000);setInterval(once,30000);
</script></body></html>"""


def rj(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


@app.route("/")
def index():
    return PAGE


@app.route("/api/live")
def api_live():
    return jsonify({
        "watch": rj(os.path.join(CLONE, ".testmgr", "watch.json")),
        "live": rj(os.path.join(CLONE, ".testmgr", "live.json"))})


@app.route("/api/history")
def api_history():
    tdir = os.path.join(CLONE, TSTATE)
    runs, regs, reports = [], [], []
    if os.path.isdir(tdir):
        for fn in sorted(os.listdir(tdir)):
            if fn.startswith("runs-") and fn.endswith(".ndjson"):
                with open(os.path.join(tdir, fn)) as f:
                    runs += [json.loads(ln) for ln in f if ln.strip()]
            elif fn.endswith(".json"):
                regs += rj(os.path.join(tdir, fn)).get("open_regressions", [])
        rdir = os.path.join(tdir, "reports")
        if os.path.isdir(rdir):
            reports = sorted(os.listdir(rdir))
    runs.sort(key=lambda r: r.get("date", ""))
    return jsonify({"runs": runs[-1000:], "open_regressions": regs,
                    "reports": reports})


@app.route("/reports/<name>")
def report(name):
    if "/" in name or ".." in name or not name.endswith(".md"):
        abort(404)
    p = os.path.join(CLONE, TSTATE, "reports", name)
    if not os.path.exists(p):
        abort(404)
    with open(p, errors="replace") as f:
        return Response(f.read(), mimetype="text/plain")


def main():
    global CLONE
    ap = argparse.ArgumentParser()
    ap.add_argument("--clone", required=True)
    ap.add_argument("--port", type=int, default=8377)
    ap.add_argument("--host", default="127.0.0.1",
                    help="bind address (default loopback only)")
    a = ap.parse_args()
    CLONE = os.path.abspath(os.path.expanduser(a.clone))
    app.run(host=a.host, port=a.port)


if __name__ == "__main__":
    main()
