#!/usr/bin/env python3
"""Track T devtest: `check` notices a body Status line that contradicts its folder.

bug-t-check-does-not-notice-a-status-line-that-contradicts-the-folder. The
FOLDER is the lock — working/ means an agent is on it right now — and the
`- **Status:** X` body line duplicates that, so it drifts whenever a ticket moves
without the prose being edited. Twenty tickets once claimed `working` while
working/ was empty, and `check --strict` reported 555 findings, none of them this.

The interesting half is what it must NOT report. A naive folder-vs-line equality
check produced 179 hits on the live board of which 3 were real; burying three
findings under 176 cosmetic ones is how this drifted in the first place.
"""
import os
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
fails = []


def check(name, got, want):
    if got != want:
        fails.append("%s\n     got:  %r\n     want: %r" % (name, got, want))
    else:
        print("  ok  %s" % name)


def board(entries):
    """entries: (folder, slug, status_line or None) -> a scratch progress tree.

    progress.py takes its ROOT from `Path(__file__).parents[1]`, NOT from cwd —
    so the script has to be COPIED into the scratch tree or it cheerfully checks
    the real board instead. The first version of this devtest ran it from cwd
    and every negative case passed vacuously against a board that happened to be
    clean, which is worse than no test.
    """
    import shutil
    d = tempfile.mkdtemp()
    os.makedirs(os.path.join(d, "tools"))
    shutil.copy(os.path.join(REPO, "tools", "progress.py"),
                os.path.join(d, "tools", "progress.py"))
    root = os.path.join(d, "devdocs", "progress")
    for folder, slug, status in entries:
        os.makedirs(os.path.join(root, folder), exist_ok=True)
        body = "---\ntrack: T\nprio: 50\n---\n\n# %s\n\n" % slug
        if status:
            body += "- **Status:** %s\n" % status
        open(os.path.join(root, folder, slug + ".md"), "w").write(body)
    return d


def drift_lines(entries):
    d = board(entries)
    r = subprocess.run([sys.executable, os.path.join(d, "tools", "progress.py"),
                        "check"], cwd=d, capture_output=True, text=True)
    return sorted(l.split()[1] for l in (r.stdout + r.stderr).splitlines()
                  if l.startswith("STATUS-DRIFT:"))


# --- must REPORT: a lock-ish claim that contradicts the folder ---------------
check("backlog ticket claiming 'working' is reported",
      drift_lines([("backlog", "bug-a-stale-claim", "working")]),
      ["bug-a-stale-claim"])
check("unfinished ticket claiming 'working' is reported",
      drift_lines([("unfinished", "bug-b-parked", "working")]),
      ["bug-b-parked"])
check("a ticket IN working/ claiming 'backlog' is reported too (other direction)",
      drift_lines([("working", "bug-c-live", "backlog")]),
      ["bug-c-live"])

# --- must STAY SILENT --------------------------------------------------------
check("agreeing line is silent",
      drift_lines([("backlog", "bug-d-ok", "backlog")]), [])
check("no Status line at all is silent",
      drift_lines([("backlog", "bug-e-none", None)]), [])
check("PROSE that is not a folder name is silent ('documented, not fixed')",
      drift_lines([("backlog", "bug-f-prose", "documented, not fixed")]), [])
check("experimental/ saying 'backlog' is accurate parking, not drift",
      drift_lines([("experimental", "feature-x-parked", "backlog")]), [])
check("backlog/ saying 'unfinished' is cosmetic, not lock-ish — silent",
      drift_lines([("backlog", "bug-g-cosmetic", "unfinished")]), [])

# --- archives are history and must never be flagged --------------------------
for folder in ("done", "rejected", "decided"):
    check("%s/ is an archive — never flagged (rewriting it falsifies history)" % folder,
          drift_lines([(folder, "bug-h-archived-%s" % folder, "working")]), [])

# --- and it reports rather than repairs -------------------------------------
d = board([("backlog", "bug-i-untouched", "working")])
p = os.path.join(d, "devdocs", "progress", "backlog", "bug-i-untouched.md")
before = open(p).read()
subprocess.run([sys.executable, os.path.join(d, "tools", "progress.py"), "check"],
               cwd=d, capture_output=True, text=True)
check("check does NOT rewrite the prose it complains about",
      open(p).read(), before)

print()
if fails:
    print("FAIL (%d):" % len(fails))
    for f in fails:
        print("  - " + f)
    sys.exit(1)
print("devtest_status_drift: all checks pass")
