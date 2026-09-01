#!/usr/bin/env python3
"""The resolve line the tool ACTUALLY WRITES, read back off disk.

Every other guard around this machinery tests the DETECTOR (does PENDING_RE
match?) and the FILL (does sync.sh rewrite it?). Nothing tested the WORDING, and
a fixture cannot: on 2026-09-01 a version of this line that printed "carried the
**resolved**" -- past tense used as a noun -- passed all 39 citation guards,
because the regex fixture beside them was a line a human had TYPED, saying
"resolve", which is what its author meant rather than what the code produced. It
surfaced only when someone ran `resolve` on a throwaway ticket and read the file
back.

So this guard does exactly that and nothing else: run the real `cmd_resolve`
against a throwaway board, read the file, and assert on the bytes. A fixture is
not allowed anywhere in it -- the whole failure mode is a fixture agreeing with
its author.

It also exercises BOTH branches. `decide-*` slugs take the `decided` path, which
is the one an author fixing the `done` path would ship unread.
"""
import argparse, importlib.util, re, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("pg", HERE / "progress.py")
pg = importlib.util.module_from_spec(spec)
sys.modules["pg"] = pg          # dataclasses resolve types via sys.modules
spec.loader.exec_module(pg)

fails = []


def check(name, cond, detail=""):
    print("  %-4s %s%s" % ("ok" if cond else "FAIL", name,
                           "" if cond else " — " + detail))
    if not cond:
        fails.append(name)


def resolve_and_read(slug, commit=None):
    """Run the real cmd_resolve in a scratch board; return the written text."""
    tmp = Path(tempfile.mkdtemp(prefix="resolve-wording-"))
    for b in ("backlog", "done", "decided"):
        (tmp / b).mkdir(parents=True)
    (tmp / "backlog" / f"{slug}.md").write_text(
        "---\nstatus: backlog\nprio: 50\n---\n\n# scratch\n", encoding="utf-8")
    old = pg.PROG
    pg.PROG = tmp
    try:
        args = argparse.Namespace(slug=slug, commit=commit, agent=None,
                                  note=None, force=False)
        try:
            pg.cmd_resolve(args)
        except SystemExit as e:          # non-zero rc is a failure to report
            if e.code:
                return None, "cmd_resolve exited %r" % (e.code,)
        for b in ("done", "decided"):
            p = tmp / b / f"{slug}.md"
            if p.exists():
                return p.read_text(encoding="utf-8"), ""
        return None, "no resolved ticket was written"
    finally:
        pg.PROG = old


def line_of(text):
    for ln in text.splitlines():
        if "PENDING-COMMIT" in ln:
            return ln
    return ""


print("the written resolve line, read back off disk")
for slug, branch in (("chore-scratch-wording-probe", "done"),
                     ("decide-scratch-wording-probe", "decided")):
    text, err = resolve_and_read(slug)
    if text is None:
        check("%s branch writes a ticket" % branch, False, err)
        continue
    ln = line_of(text)
    check("%s: a pending line was written" % branch, bool(ln), repr(text[-200:]))
    if not ln:
        continue
    # 1. it must still round-trip through the detector the fill keys on
    check("%s: PENDING_RE matches what was written" % branch,
          bool(pg.PENDING_RE.search(ln.strip())), repr(ln))
    # 2. the tense bug, stated as the shape rather than as the one instance
    doubled = re.search(r"\bthe (resolved|decided)\b", ln)
    check("%s: no past-tense verb used as a noun" % branch,
          not doubled, repr(doubled.group(0)) if doubled else "")
    # 3. the placeholder must stay at end of line -- PENDING_RE anchors on it
    check("%s: placeholder is last on the line" % branch,
          ln.rstrip().rstrip(".").endswith("PENDING-COMMIT"), repr(ln))

# A hand-supplied --commit names the change deliberately, so it carries no
# disclaimer and no placeholder. Asserted because it is the branch a change to
# the pending wording is most likely to break without noticing.
text, err = resolve_and_read("chore-scratch-wording-explicit", commit="deadbeef1")
check("explicit --commit still writes a ticket", text is not None, err)
if text:
    check("explicit --commit leaves no placeholder",
          "PENDING-COMMIT" not in text, repr(line_of(text)))

print("resolve wording: %s" % ("all checks passed" if not fails
                               else "BROKEN — %d" % len(fails)))
sys.exit(1 if fails else 0)
