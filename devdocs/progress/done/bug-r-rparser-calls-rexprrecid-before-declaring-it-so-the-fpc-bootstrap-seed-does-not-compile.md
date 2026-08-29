---
track: R
prio: 80
type: bug
blocked-by: []
summary: "compiler/rparser.inc calls RExprRecId ~340 lines before it is declared and there is no forward, so FPC stops with `Identifier not found \"RExprRecId\"` and compiler.pas does not compile under FPC at all. pxx resolves names across the whole unit and is unaffected, which is why every green gate stayed green: the self-host loop never asks FPC anything. The FPC bootstrap seed is the one thing that build cannot verify, and it is the path a fresh checkout with no pinned binary must take. One-line fix: a forward declaration next to the five already at rparser.inc:63-67. Landed 2026-08-29 in 68dac6d2a."
status: done
owner: ""
---

# `rparser.inc` calls `RExprRecId` before declaring it — the FPC bootstrap seed does not compile

- **Type:** bug (bootstrap) — **Track R** (`compiler/rparser.inc`).
- **Filed:** 2026-08-29 by the wasm32 lane (branch `wasm`, at that point 79
  ahead / 370 behind and mid-merge; the merge is `467b73682`). Found by
  `test/wasm/check_forwards.sh` on the first run after merging `origin/master`,
  and then confirmed against FPC itself rather than against the checker.
- **Landed in:** `68dac6d2a` "feat(rust): expression scrutinees, `if let`,
  unwrap_or", 2026-08-29. Still present at `3dbdc6b63`.

## The measurement

```
$ fpc -Mobjfpc -Sh compiler/compiler.pas
rparser.inc(1416,12) Error: Identifier not found "RExprRecId"
compiler.pas(2121) Fatal: There were 1 errors compiling module, stopping
```

Exactly one error. The call sites are `rparser.inc:1416`, `:2314`, `:2846`;
the declaration is at `:1754`. The first call precedes it by ~340 lines and
there is no forward — `grep -c 'RExprRecId.*forward'` returns 0, against five
forwards already present at `:63-67` for exactly this reason.

## Why every gate stayed green

**pxx and FPC do not resolve names the same way.** pxx resolves across the
whole unit, so order does not matter to it; FPC resolves in source order and
requires the forward. `make compiler/pascal26` — which is the entire per-fix
loop and which doubles as the byte-identical self-host fixedpoint — compiles
`compiler.pas` **with pxx**. It therefore cannot see this class of defect at
all, and neither can any tier of `testmgr`, for the same reason.

So the property that broke is the one property the normal loop structurally
cannot check: *a fresh tree with no trusted binary can still be seeded.* That
is not a Rust-frontend property, it is a repo-wide one, which is why this is
p80 rather than ranked with the rest of Track R's queue.

## The fix

Add, next to the existing block at `rparser.inc:63-67`:

```pascal
function RExprRecId(node: Integer): Integer; forward;
```

Left to Track R rather than made here: this lane does not own `rparser.inc`,
and the one-line certainty of the fix is not a reason to cross a lane
boundary — it is the usual reason people do.

## The general shape, which is not Rust's

`check_forwards.sh` exists in `test/wasm/` because this lane hit the same thing
in its own backend on 2026-08-28: `WasmDataAddr` was called ~300 lines above
its declaration, `make compiler/pascal26` passed, and only the FPC seed would
have failed. That was caught by the check on the day it was written. This one
is the same defect in a different file, found by the same check.

**The check is generic — it reads `compiler/*.inc` and knows nothing about
wasm — and it is sitting in a wasm-specific directory where no other lane will
ever run it.** Two instances in two days in two unrelated frontends says the
hazard is repo-wide and the placement is wrong. Suggested follow-up, filed
separately if anyone wants it: move it to `tools/` and hang it off
`gate.sh quick`, which is ~30s and already the pre-pin brake. A pin is exactly
the moment the seed's health matters, and it is currently the moment nothing
asks.

## Log
- 2026-08-29 — resolved, commit 9d14b759d.

---

**Duplicate noted, 2026-08-29 (frankA).** I filed the same defect independently
as `bug-r-rexprrecid-breaks-the-fpc-bootstrap-seed` before seeing this one. Both
are in `done/` — Track R fixed the defect while I was folding them together, so
"duplicate" is the right relation but `rejected/` was the wrong disposition: it
was a real bug and it was really fixed. This ticket is the fuller of the two; it
names the landing commit (`68dac6d2a`) and the five existing forwards at
`rparser.inc:63-67`.

Two facts from the duplicate worth keeping here:

- **Two instruments already catch this class in seconds**, and neither is in the
  mandatory per-fix loop: `tools/forwardlint.py` (~4s) enumerates the WHOLE class
  in one pass, and `tools/gate.sh quick` runs an FPC seed canary concurrently.
  The canary is what re-found it — measured RED at `gate.sh quick` on 2026-08-29,
  `rparser.inc(1412,12)`, while every other step of that same gate passed,
  including the self-host fixedpoint.
- **Prefer forwardlint over the canary's message when you fix it.** FPC reports
  one batch and aborts, so the canary names whatever it hit first, and a fix
  aimed at exactly that identifier can look complete and not be — that failure
  mode cost three RED cycles on 2026-08-27 and is why the linter exists.
  See `decide-should-the-fpc-seed-canary-be-in-the-mandatory-loop`.

**Two lanes filed this within hours of each other**, each finding it the moment
it happened to run a wider gate. That duplication is the argument the decision
ticket is weighing, in miniature.
