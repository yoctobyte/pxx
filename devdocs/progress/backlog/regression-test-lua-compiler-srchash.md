---
prio: 70
track: C
blocked-by: [bug-c-labels-as-values-is-the-whole-of-the-lua-regression]
summary: "TRIAGED, not fixed: lua 5.4 turns its computed-goto interpreter loop on with a BARE `#if defined(__GNUC__)`, so 00ab464bf's GNU C 2.7 claim reaches ljumptab.h's `&&L_OP_MOVE` and lvm.c does not compile. Labels-as-values is the ONLY blocker — `-DLUA_USE_JUMPTABLE=0` and `-U__GNUC__` each build the runner and it passes 6/6 lua programs. Blocked on the feature; do NOT add the -D to the recipe."
---

> **Track guessed as C from the FAILING STEP** — line 2 of 2, `if [ ! -f "library_candidates/lua/src/lua.h" ]; then \ echo "test-lua: SKIP — no lua tree at library_candidates/lua/src `, which names `test/lua/runner.c`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 3 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-lua#src:tools/compiler_srchash.sh at 1236bf31f930 in step 2/2, `if [ ! -f "library_candidates/lua/src/lua.h" ]; then \ echo "test-lua: SKIP — no lua tree at library_candidates/lua/src…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5ea286a98481`).
  Untriaged.
- **Found:** 2026-09-01T23:38:25Z
- **Test source:** tools/compiler_srchash.sh compiler/.pascal26.fixedpoint +1
- **Failing step:** line 2 of 2 of the job's recipe; it names `test/lua/runner.c`.
  ```
  if [ ! -f "library_candidates/lua/src/lua.h" ]; then \ echo "test-lua: SKIP — no lua tree at library_candidates/lua/src (fetch lua 5.4 there to run)"; \ exit 0; \ fi; \ echo "compiling lua runner ..."; \ wd="$(mktemp -d)"; trap 'rm -rf "$wd"' EXIT; \ ./compiler/pascal26 -g -Ilib/crtl/include -Ilib/c
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-lua#src:tools/compiler_srchash.sh'` at 1236bf31f93084fe322e626880cc6132a33cf64a

## Range
> **The named sha `1236bf31f930` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `1236bf31f930`, last good `8e12236502be`, 10 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:28: error: expected C expression
(tail)
self-host fixedpoint: verified — 1 round(s), 0f1d03315f4e (stamp read back; sources match it)
compiling lua runner ...
pascal26:4: warning: "/*" within comment
pascal26:28: error: expected C expression
  in: library_candidates/lua/src/lvm.c
  near:       >>>  L_OP_MOVE  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Triaged (frankZ, plexus, 2026-09-02) — one construct, and it is the only one

Reproduced at binary `7ef59bc560b4b9fc` with the recipe's own flags, byte-identical
to the log tail above. Cause, both counter-tests, and the 6/6 corpus run that
proves nothing is behind the gap:
[[bug-c-labels-as-values-is-the-whole-of-the-lua-regression]].

Same root as the five `test_c_gtk*` reds — `00ab464bf`'s GNU C 2.7 claim, seven
jobs between them. The gtk five are fixed; these two need the feature.

**Do not add `-DLUA_USE_JUMPTABLE=0` to the recipe to close this.** It would go
green while hiding the gap and while no longer testing what a real lua build
does on a GNU-announcing compiler.
