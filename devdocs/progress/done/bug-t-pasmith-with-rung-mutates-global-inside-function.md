---
prio: 40
---

# pasmith: wide rungs (`with`/`reccopy`/…) mutate a GLOBAL inside a function body → order-dependent program

- **Track:** T (fuzzing tool — `tools/pasmith.py`).
- **Found:** 2026-07-16, seed 27863 (ledger sig `pxx-vs-fpc_trace-length`).
- **Class:** generator manufacturing false signal (impl-defined operand order),
  same family as `bug-t-pasmith-order-dependent-programs`. pxx is NOT wrong.

## Symptom

Fuzzer flagged a pxx-vs-FPC divergence on seed 27863. Root-caused to:

```pascal
g3 := word(not word(r0g.r0f0 xor f0(pv0^.r0n.r0i0, g6)));
```

`f0` (a generated `fN` function, called mid-expression as a binop operand) wrote
the GLOBAL `r0g.r0f0` in its body (`with r0g do r0f0 := ...`, 778→810). The
sibling leaf `r0g.r0f0` reads the same global. Operand evaluation order is
unspecified in Pascal — pxx evaluates left-to-right (reads 778), FPC
right-to-left (reads 810) — so the checksums differ with neither compiler at
fault.

## Root cause

`gen_func` intentionally restricts `assignable` to locals so a mid-expression
call stays pure (comment at pasmith.py ~1845). But `wide_stmt`'s `with` /
`reccopy` / `ptrwalk` rungs hardcode a **global** record `r%dg` and write its
fields, bypassing `assignable`. Reachable from a function body via
`stmt → wide_stmt`, they made `fN` global-mutating.

## Fix (landed)

`self.in_func` flag, set True while `gen_func` builds a body; `wide_stmt` returns
`None` when it's set. Functions stay scalar/pure (locals only); top-level/main,
procedures and methods are unaffected — a method is only ever called as the sole
`Mix()` argument, never beside a global-reading operand.

## Verification

- seed 27863: 0 divergences (was NEW).
- `--check 150`: FPC accepts 100%.
- differential sweep seeds 27800–27950: 151 programs, 0 divergences.

Ledger sig `pxx-vs-fpc_trace-length` → dodged (root-caused in generator; no
compiler change).

## Log
- 2026-07-16 — resolved, commit e48592cc.
