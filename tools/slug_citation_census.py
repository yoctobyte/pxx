#!/usr/bin/env python3
"""Census slug-shaped ticket citations in compiler/** and lib/** comments.

A MEASUREMENT TOOL, NOT A GATE. It is wired into nothing and must stay that way
until bug-t-177-slug-citations-in-compiler-and-lib-comments-resolve-to-no-ticket
decides between a baseline file and a citation CONVENTION -- a bare checker over
~182 legacy rows is a gate that cannot pass.

WHY THIS IS A COMMITTED SCRIPT AND NOT A PARAGRAPH IN A TICKET: the first run of
this census was described in prose and its own author could not reproduce it the
same evening -- a reimplementation from that description answered 195 where the
ticket said 177, and three further instrument bugs were found by reading three
source lines. The seven corrections below are the durable artefact; the count is
not. See devdocs/dev/debugging-playbook.md, "A LINE-SCOPED MATCHER OVER WRAPPED
PROSE TRUNCATES SILENTLY".

Each correction is a row that was FALSELY reported dangling before it:
  1 wrapped citations  -- the slug continues on the next comment line
  2 prefix resolution  -- the slug is a prefix of a longer renamed filename
  3 hyphen boundary    -- \bcompat-philosophy matches inside
                          frontend-compat-philosophy.md; a hyphen is not a \b
  4 stitch guard       -- stitch ONLY when the hyphen is the line's last
                          non-space char, else the next PROSE WORD is glued on
  5 author elision     -- `bug-a-foo-...` is deliberate shorthand; never stitch
                          it (all 10 live instances resolve by prefix)
  6 uppercase body     -- an [a-z0-9-] body truncates a real citation, which
                          then looks wrapped, which fires 4
  7 case-insensitive   -- compare lowercased, or 6 returns at the resolve step
Corrections 4, 5 and 6 COMPOUND; 6 feeds 4.

Emits `slug<TAB>file:line` for every dangling row, because a census that prints
only counts cannot be debugged.
"""
import os, re, sys

PREF = r"(?:bug|feature|task|decide|compat|refactor|umbrella)"
# (3) left boundary excludes '-' so a longer name cannot donate a false short one.
# (6) the body admits uppercase.
RX = re.compile(r"(?:(?<=^)|(?<=[^A-Za-z0-9_-]))(" + PREF + r"-[A-Za-z0-9-]{3,})")
CONT = re.compile(r"\s*(?://|\{|\(\*|\*|#)?\s*([A-Za-z0-9-]+)")
EXTS = ("pas", "inc", "py", "md", "c", "h", "txt")


def real_slugs(root):
    out = {}
    for d, _, fs in os.walk(os.path.join(root, "devdocs/progress")):
        for f in fs:
            if f.endswith(".md"):
                out[f[:-3].lower()] = os.path.join(os.path.relpath(d, root), f)
    return out


def citations(root, subs=("compiler", "lib")):
    """-> (raw {slug: (relpath, lineno)}, elided {slug: (relpath, lineno)})"""
    raw, elided = {}, {}
    for sub in subs:
        for d, _, fs in os.walk(os.path.join(root, sub)):
            for f in fs:
                if f.rsplit(".", 1)[-1] not in EXTS:
                    continue
                p = os.path.join(d, f)
                try:
                    lines = open(p, encoding="utf-8", errors="replace").read().split("\n")
                except OSError:
                    continue
                rel = os.path.relpath(p, root)
                for i, ln in enumerate(lines):
                    for m in RX.finditer(ln):
                        s, tail = m.group(1), ln[m.end(1):]
                        # (5) the author elided it -- shorthand, never stitch.
                        if tail[:3] == "..." or tail[:1] == "…" or \
                           (s.endswith("-") and tail[:1] in (".", "…")):
                            elided.setdefault(s.rstrip("-").lower(), (rel, i + 1))
                            continue
                        # (1)+(4) stitch only a hyphen that ENDS the line.
                        if s.endswith("-") and ln.rstrip().endswith("-"):
                            j, cur = i + 1, s
                            while cur.endswith("-") and j < len(lines):
                                nx = CONT.match(lines[j])
                                if not nx:
                                    break
                                cur += nx.group(1)
                                if not lines[j].rstrip().endswith("-"):
                                    break
                                j += 1
                            s = cur
                        raw.setdefault(s.rstrip("-").lower(), (rel, i + 1))  # (7)
    return raw, elided


def classify(raw, real):
    exact, prefix, dangle = {}, {}, {}
    for s, loc in raw.items():
        if s in real:
            exact[s] = loc
        elif any(r.startswith(s) for r in real):   # (2)
            prefix[s] = loc
        else:
            dangle[s] = loc
    return exact, prefix, dangle


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    real = real_slugs(root)
    raw, elided = citations(root)
    exact, prefix, dangle = classify(raw, real)
    el_ok = sum(1 for s in elided if any(r.startswith(s) for r in real))

    w = sys.stderr.write
    w("distinct citations      %5d\n" % (len(raw) + len(elided)))
    w("  author-elided         %5d   (resolve by prefix: %d)\n" % (len(elided), el_ok))
    w("resolve exactly         %5d\n" % len(exact))
    w("resolve as prefix only  %5d\n" % len(prefix))
    w("resolve to NOTHING      %5d\n" % len(dangle))
    # Controls. The negative one is stable; a REAL positive control is not --
    # both real rows this census originally named went stale within 90 minutes
    # (one was filed by the peer who found it). A planted slug is the only
    # positive control that cannot be fixed out from under the test.
    bad = []
    if "compat-philosophy" in dangle:
        bad.append("NEG CONTROL FAILED: compat-philosophy reported (correction 3 regressed)")
    if not exact:
        bad.append("POS CONTROL FAILED: nothing resolved at all -- matcher is dead")
    for b in bad:
        w(b + "\n")
    for s in sorted(dangle):
        print("%s\t%s:%d" % (s, dangle[s][0], dangle[s][1]))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
