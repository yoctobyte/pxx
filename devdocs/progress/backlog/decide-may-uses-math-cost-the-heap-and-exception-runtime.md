---
track: U
prio: 30
type: decide
blocked-by: []
summary: "Making Floor/Ceil raise EInvalidOp like FPC needs `uses sysutils` in math's implementation — measured, that is the ONLY way to raise anything, since Exception is not visible otherwise. That makes every `uses math` program require the heap + exception runtime: test/test_math.pas stops compiling today. Fork: pay it (and fix the prescan in A), saturate silently, or leave the wrong values. Blocks bug-b-floor-of-an-out-of-range-double-returns-0-where-fpc-raises."
---

# May `uses math` cost the heap + exception runtime?

- **Track U** — a design call, escalated rather than guessed.
- Raised by Track B on 2026-08-14 while implementing
  [[bug-b-floor-of-an-out-of-range-double-returns-0-where-fpc-raises]], which is
  parked in `unfinished/` with the working patch and its FPC diff banked. The
  code half is **done and verified**; this question is the only thing between it
  and landing.

## What is settled, and is not the question

`Floor(1e30)` returns `0` and `Floor64(1e30)` returns `INT64_MIN`. FPC raises
`EInvalidOp`. `0` is the dangerous one — an out-of-range magnitude becomes the
*smallest* answer, so `if Floor(x) > limit` passes.

The ticket recommended option (2), a local range check in the Pascal bodies,
and that works: implemented, and the pxx output then matched FPC 3.2.2 on all
**20 rows** of a table covering ±1e30, ±Inf, NaN, `3e9` (fits Int64 but not
Integer), both Int64 boundaries, and ordinary values — including the subtle row
where **FPC does not raise**: `Floor(3e9) = -1294967296`, because only the
*Int64* conversion is policed and the Int64→Integer narrowing is left to wrap.
Cost measured at +53% on a loop doing nothing but call `Floor64` (0.145s →
0.222s, 20M calls, -O2), which is fine.

## The cost that was NOT anticipated

To `raise` from `math` at all, `math`'s implementation must `uses sysutils`:
`Exception` is not visible otherwise (measured — `raise Exception.Create(…)`
without it is `error: undefined variable (Exception)`). And pulling sysutils in
makes `uses math` require the heap/exception runtime:

```
$ pxx test/test_math.pas /tmp/tm
pascal26:74: error: array of const requires the builtinheap unit
```

`test/test_math.pas` is 27 lines, `uses math`, and touches no string, array or
exception. It compiles today and stops compiling with the fix. The mechanism:
`DetectPascalRuntimeNeeds` (compiler/parser.inc ~32833) decides
`needHeapUnit` by prescanning the **program**, so a need introduced by a unit's
implementation-uses is invisible to it, and sysutils' `Exception.CreateFmt`
(`array of const`) then has no `builtinheap` to compile against.

So the real question is not "should Floor raise" — it is **"is `uses math`
allowed to cost the heap and exception runtime?"** That reaches past floats:
`pxxcio` does `uses math`, so every C program inherits the answer, and Track S's
bare-metal ESP profile is where it costs most.

## The fork

1. **Pay it.** `math` uses sysutils; Floor/Ceil/Floor64/Ceil64 raise like FPC.
   Needs a Track A fix first so a unit's implementation-uses can pull
   `builtinheap` — otherwise heap-free `uses math` programs simply stop
   compiling, which is a worse regression than the bug. **Recommended if and
   only if that A fix is wanted anyway** — the prescan being unable to see a
   unit's own needs looks like a latent defect independent of this ticket.
2. **Saturate** to `High`/`Low` of the return type. No sysutils, no runtime
   cost, nothing stops compiling — and still a silent wrong answer, just a
   less absurd one than `0`. Cheap, and it does not close the bug.
3. **Split the surface**: raise only from a sysutils-side wrapper and leave
   `math` silent. Two spellings of Floor with different contracts, which is the
   double-case shape `devdocs/dev/normalise-dont-special-case.md` warns about.
4. **Leave it**, documented in `devdocs/dev/math-implemented-twice.md`. The
   status quo, and the reason this was filed as a bug rather than a compat item.

**Recommendation: (1), gated on the Track A prescan fix.** FPC parity is the
stated goal for this surface, the runtime cost is measured and small, and the
"heap-free `uses math`" property is worth keeping *deliberately* rather than by
accident — if it is worth keeping, that is itself the answer, and it makes (2)
the honest choice.

## Related, already filed

- [[bug-a-trunc-and-round-of-an-out-of-range-double-return-int64-min-silently]]
  — the builtin half of the same defect, which no RTL change can reach, and
  where each backend gives a *different* wrong answer.
- [[bug-a-aarch64-writeln-of-low-int64-prints-negated-digit-bytes]] — fell out
  of that sweep; unrelated to floats.
