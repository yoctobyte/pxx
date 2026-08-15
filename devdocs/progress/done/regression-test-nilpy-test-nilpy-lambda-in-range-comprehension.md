---
prio: 70
status: done
owner: agent-an-night
---

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_lambda_in_range_comprehension.npy red at 4c9da77f9368 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-15T08:39:52Z
- **Test source:** test/test_nilpy_lambda_in_range_comprehension.npy test/test_nilpy_lambda_in_range_comprehension.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_lambda_in_range_comprehension.npy'` at 4c9da77f9368ee00abe9614ae864cee612275db6

## Range
bad `unknown`, range **unknown** (first run covering this job at this tier, so there is no earlier passing sha to bound it) — **no idle bisect will happen**; this one needs hand-triage.

## Log tail
```
ok: /tmp/testmgr-scratch-2453462/test_nilpy_lamcomp26  [code=2275438B  data=44924B  bss=11396B  procs=1645]
--- test/test_nilpy_lambda_in_range_comprehension.expected	2026-08-15 07:32:04.884997473 +0200
+++ -	2026-08-15 10:33:43.422813313 +0200
@@ -2,7 +2,7 @@
 list [30, 30, 30]
 str ['c', 'c', 'c']
 pinned [0, 1, 2]
-genexpr [2, 2, 2]
+genexpr []
 dict [1, 1]
 step [9, 9, 9, 9]
 empty []

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Root cause (2026-08-15, reproduced at HEAD)

Only the `genexpr` row was wrong: `list(lambda: k for k in range(3))` gave
`[]` where CPython gives three closures. TWO sites, both keyed on the same
missing fact — **a lambda's `:` and a comprehension's `for` are boundaries of
each other**:

1. `PyBareGenExprAhead` Exits at a depth-0 `tkColon` (the statement-boundary
   guard from bug-nilpy-a-bare-genexpr-scan-runs-past-the-statement). The
   LAMBDA's own colon is at depth 0, so the scan bailed and answered False —
   the call never diverted to the comprehension desugar. Now a depth-0
   `lambda` pushes a pending colon (counted, so `lambda a: lambda b: ...`
   still leaves the last colon a real boundary).

2. The lambda body's token-span scan (PyParseLambdaStub) broke on a depth-0
   `,` `)` `]` / newline, but not on `for`. So the body ran on through
   `k for k in range ( 3 )`, the reconstructed pyeval source was a whole
   comprehension, and the genexpr had no `for` clause left to iterate. `for`
   lexes as a plain tkIdent in NilPy (PyParseFor uses PyIsIdent('for')), and
   no Python name can be spelled `for`, so the text test is exact. A trailing
   `if` needs no stop of its own — it can only be the comprehension's, which
   is already past the `for`.

Fixing either alone is not enough: (1) alone leaves the parse erroring with
"expected comma or close parenthesis", (2) alone leaves the empty list.

Verified: the test matches its .expected byte for byte. Swept 14 further
lambda/genexpr/key= shapes against CPython 3.12 — all agree except the
pre-existing `repr` of a function object (address and qualname format), which
this change does not touch. gate.sh quick + self-host fixedpoint GREEN.
- 2026-08-15 — resolved, commit PENDING-COMMIT.
