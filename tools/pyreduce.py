#!/usr/bin/env python3
"""AST-guided statement reduction of a NilPy/Python module against a FIXED
error substring.

    tools/pyreduce.py <root> <rel/path.py> "<error substring>" <compiler> <outbin>

<root> is the directory the compiler is invoked FROM, so a module inside a
package reduces with its imports intact.  <rel/path.py> is rewritten IN PLACE
-- point it at a copy, never at the user's tree.

Two properties, both of them the point:

1. The interestingness test is the error SUBSTRING, never the exit code.  A
   reduction keyed on rc != 0 accepts ANY refusal, so it converges happily on a
   DIFFERENT, smaller bug and hands you a minimal repro of something you were
   not chasing -- a reducer manufacturing its own equivalence class, the same
   shape as a census that greps for `error:` and scores a segfault CLEAN.

2. The best-known-good text is CHECKPOINTED to <rel>.reduced after every
   successful removal.  A reducer holds a candidate in the file while it tests
   it, so the file on disk is a FAILED candidate most of the time -- kill the
   process and what is left does not reproduce, and the good state, which lived
   only in memory, is gone with it.  Measured 2026-09-10: 35 minutes of
   reduction lost to exactly that, and the loss was silent -- the file was
   still there, still smaller, and simply no longer interesting.

3. Slots are addressed by POSITION in a freshly-parsed list, never by node
   identity.  Two ast.parse() calls over the same text yield different node
   OBJECTS, so `slots.index(node)` raises and the pass silently ends after its
   first successful removal.  That was this script's first cut: it removed
   exactly one statement per round with no error and a plausible log.  **A
   reducer that is merely slow and one that is broken look identical** -- the
   tell is a removal count that does not FALL.  devdocs/dev/debugging-playbook.md
"""

import ast, subprocess, sys, os

ROOT, REL, WANT, PX, OUT = sys.argv[1:6]
SRC = os.path.join(ROOT, REL)


def interesting():
    r = subprocess.run([PX, REL, OUT], cwd=ROOT, capture_output=True, text=True)
    return WANT in (r.stdout + r.stderr)


def slots(tree):
    out = []
    for n in ast.walk(tree):
        for f in ('body', 'orelse', 'finalbody'):
            b = getattr(n, f, None)
            if isinstance(b, list) and b and isinstance(b[0], ast.stmt):
                for i in range(len(b)):
                    out.append((n, f, i))
    return out


cur = open(SRC).read()
assert interesting(), "the ORIGINAL is not interesting -- wrong WANT?"

rounds = 0
while True:
    rounds += 1
    removed = 0
    k = len(slots(ast.parse(cur))) - 1
    while k >= 0:
        t2 = ast.parse(cur)
        s2 = slots(t2)
        if k >= len(s2):
            k -= 1
            continue
        holder, field, idx = s2[k]
        b = getattr(holder, field)
        if len(b) == 1:
            b[idx] = ast.Pass()
        else:
            del b[idx]
        try:
            cand = ast.unparse(ast.fix_missing_locations(t2))
        except Exception:
            k -= 1
            continue
        open(SRC, 'w').write(cand)
        if interesting():
            cur = cand
            removed += 1
            # Checkpoint: see (2) in the docstring. Written on every success,
            # not once per round -- a round here can take twenty minutes.
            open(SRC + '.reduced', 'w').write(cur)
        else:
            open(SRC, 'w').write(cur)
        k -= 1
    print(f'round {rounds}: removed {removed}, {len(cur.splitlines())} lines',
          file=sys.stderr, flush=True)
    if removed == 0:
        break

open(SRC, 'w').write(cur)
print(cur)
