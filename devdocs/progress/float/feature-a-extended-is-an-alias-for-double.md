---
slug: feature-a-extended-is-an-alias-for-double
track: A+F
prio: 25
type: feature
blocked-by: []
umbrella: extended
summary: "UMBRELLA for the `Extended` cluster. `Extended` is accepted and silently mapped to `Double`, so FPC code that uses it deliberately gets a quietly worse answer with no diagnostic. Owner ruled 2026-08-30 that real 80-bit Extended WILL be implemented eventually; the whole cluster is parked in `float/` until it is worked as one consolidated session."
---

# `Extended` is silently an alias for `Double`

> **This is the UMBRELLA ticket for the whole `Extended` cluster** (designated
> 2026-08-30). Three overlapping tickets existed in three folders; this one had
> the only real scope analysis, so it absorbed the others. Index at the bottom.

**User, 2026-08-10: "we also need to support extended in the future."** Filed
from the float-formatting discussion; deliberately not urgent.

## Measured (x86-64, `{$mode objfpc}`, HEAD `f20a7363d`)

| | FPC | pxx |
| --- | --- | --- |
| `SizeOf(Extended)` | **10** | **8** |
| `e := 1.0/3.0; WriteLn(e)` | `3.33333333333333333342E-0001` | `3.3333333333333331E-001` |

pxx accepts `Extended` and maps it to `Double`. It compiles, it runs, and it is
**silently less precise** — which is the part that matters: FPC code that uses
`Extended` deliberately (accumulators, iterative refinement, anything relying on
80-bit intermediates to avoid drift) gets a quietly worse answer with no
diagnostic. That is a compat trap, not merely a missing type.

## Scope, honestly

This is not a formatting change — it is a TYPE with 80-bit x87 semantics:

- **x86-64 only.** aarch64/arm32/riscv32/xtensa have no 80-bit format, so the
  alias is the only sane behaviour there and must stay. Any implementation is
  necessarily target-conditional, which also means `SizeOf(Extended)` becomes
  target-dependent — code that assumes 10 breaks on the cross targets exactly as
  it does on FPC's own non-x86 targets.
- **x87, not SSE.** pxx's float codegen is SSE-based; 80-bit needs the x87 stack
  (`fld`/`fstp` `tbyte`), a different register file and a different
  control-word/rounding story.
- **Storage is 10 bytes, alignment is not.** FPC pads to 16 in records/arrays on
  x86-64; get this wrong and every `Extended` field offset in a ported record is
  wrong.
- **The RTL surface**: `FloatToStr`, `Str`, `Val`, `WriteLn`'s formatter and the
  math routines all currently assume Double.

## Interim, cheap option worth considering first

If full 80-bit is not wanted soon, a **diagnostic** beats silence: warn (or
error under `--strict-fpc`) when `Extended` is declared on a target where it
aliases `Double`, so a port that depends on the precision finds out at compile
time instead of drifting. That is a small change and removes the trap without
the x87 work.

## Related

The default-output-format question for `Extended` (FPC prints 20 significant
digits and a 4-digit exponent) is deliberately postponed —
`rainy-day/decide-default-float-output-format-and-constant-precision`. Note that
question becomes moot for `Extended` if this lands, since the digits would then
be real rather than Double's rendered wider.

## Gate

`SizeOf(Extended) = 10` on x86-64 and `= 8` elsewhere; the 1/3 row matching FPC
to 20 significant digits; a record containing an `Extended` field laying out with
FPC-compatible offsets; `make test` + self-host byte-identical + cross.

<!-- float category -->
Indexed on [[meta-float-accuracy-policy]] — the standing float-accuracy index.
Collect, do not fix piecemeal; see the working rule there.

## Triage 2026-08-19 (Track D re-triage pass, pin v363)

**Genuine feature, still wanted, numbers unchanged.** Re-measured rather than
copied — `SizeOf(Extended)` is 8 under pxx and 10 under FPC 3.x, and
`1.0/3.0` prints `3.3333333333333331E-001` against FPC's
`3.33333333333333333342E-0001`. Identical to the table filed on 2026-08-10.

Deliberately **not** re-typed as a bug despite being silent: the repo's float
policy is fast-by-default, and this is a type that is not implemented rather
than an arithmetic result that drifted. The scope note is what matters here —
x86-64-only, x87 rather than SSE, 10-byte storage with 16-byte padding — and it
is why the low prio is right.

---

## RULING 2026-08-30 (owner) — Extended WILL be implemented, eventually

> *"eventually we will implement 80-bit extended type properly. for now, we move
> all related tickets to the float subfolder. so we can work on those tickets in
> a consolidated session."*

This settles the direction that `feature-extended-alias-or-reject` left open in
2026-06-22, when option (c) *real 80-bit* was recorded as "explicitly NOT
wanted". It is now wanted — **later, and as one piece of work, not piecemeal.**

Two things follow, and the second is the operative one:

1. The alias is **interim**, not the permanent answer. `done/feature-extended-alias-or-reject`
   should be read as a holding position, not a closed design question.
2. **Nothing in this cluster is worked on its own.** That is the entire reason
   the folder move happened: the cost here is not any single sub-part, it is
   that the parts only make sense together — a 10-byte type nothing can print,
   or an x87 path no math routine reaches, is worse than the honest alias we
   ship today. Parked in `float/`, invisible to `ready`/`next`, picked up on
   explicit request.

## What "properly" has to cover — the consolidated session's scope

The user's own framing, 2026-08-30: *"this has more aspects than data type alone
... it also involves math library and formatting functions, and using the
floating point stack registers."* Correct, and that is four workstreams:

| # | aspect | where | note |
| --- | --- | --- | --- |
| 1 | the **type**: 10-byte storage, 16-byte record/array padding, `SizeOf` | `defs.inc`, `symtab.inc`, `pasparser_lval.inc` | get padding wrong and every `Extended` field offset in a ported record is wrong |
| 2 | **x87 codegen** — `fld`/`fstp` `tbyte`, a second register file, its own control word and rounding story | `ir_codegen.inc` (x86-64), i386 | the SSE2 path **cannot express** 80-bit; this is not a widening of existing code |
| 3 | **RTL formatting**: `Str`, `Val`, `FloatToStr`, `WriteLn`'s formatter | `lib/rtl` | FPC prints 20 significant digits and a **4-digit** exponent for Extended |
| 4 | **math library**: `lib/rtl/math.pas` today provides Single + Double overloads only, deliberately, because Extended is the alias | `lib/rtl/math.pas` (Track B) | inherited from the folded-in `feature-extended-type-support` |

Plus the cross-target question that has no good answer and must be decided
rather than discovered: **aarch64, arm32, riscv32, xtensa and wasm32 have no
80-bit format.** FPC itself falls back to Double for `Extended` on those
targets, so `SizeOf(Extended)` becomes target-dependent (10 on x86-64/i386, 8
elsewhere) exactly as it is under FPC. Code that assumes 10 breaks on the cross
targets — under FPC too, which is the argument that it is acceptable.

## The cluster — index

| ticket | state | relation |
| --- | --- | --- |
| **this file** | float/ | the umbrella; scope + ruling live here |
| [[feature-extended-type-support]] | float/ | **superseded** by this ticket; kept as a gravestone, its RTL constraint folded in above |
| [[decide-is-real-a-double-or-fpcs-80-bit-extended]] | float/ | Track U. Partly answered by the ruling above — but the *residual* question stands: does the bare name `Real` follow Extended on x86-64, or stay Double for cross-target coherence? **Answer before starting workstream 1.** |
| [[bug-p-sizeof-extended-disagrees-with-the-storage-extended-gets]] | float/ | **NOT blocked by this ticket** — see below |
| [[decide-default-float-output-format-and-constant-precision]] | float/ | workstream 3's parent question; goes moot for Extended if this lands, since the digits become real rather than Double's rendered wider |
| [[bug-n-nilpy-carries-its-own-copies-of-the-float-type-table]] | backlog/ | left ranked deliberately (it is a duplication bug worth fixing regardless), but `pyparser.inc:966` collapses `single` and `extended` into `tyDouble` in a private table — **workstream 1 must land there too, or NilPy silently keeps the alias** |
| `done/feature-extended-alias-or-reject` | done | the 2026-06-22 holding position; now interim per the ruling |
| `done/bug-c-crtl-long-double-math` | done | C's `long double` — the other frontend that will want workstream 2 |

### The sizeof bug is deliberately NOT gated on this umbrella

`bug-p-sizeof-extended-disagrees-with-the-storage-extended-gets` is a
self-inconsistency *inside the current alias*, not a step toward the real type:
`pasparser_lval.inc:6304` (declaration) says `tyDouble`/8 while `:6417`
(`SizeOf`) says `tyExtended`/10. Measured 2026-08-30 on this tree: **`:6417` is
the only site in the entire compiler that PRODUCES `tyExtended`** — every other
reference (`ir_codegen`, the backends, `cparser`'s promotion rules at
`cparser.inc:133`/`:172`) is a consumer that only fires on an operand that is
already Extended.

So fixing it makes `tyExtended` genuinely dead, which is the *cleanest starting
position for this umbrella*, not a conflict with it: when real Extended lands,
both tables move together, in one place, instead of the split having to be
re-merged first. It makes the big job smaller. Work it whenever; do not wait.

### Interim, still worth doing before any of the above

The diagnostic proposed further up — warn (error under `--strict-fpc`) when
`Extended` is declared on a target where it aliases `Double`. The trap today is
not the missing precision, it is the **silence**: a ported FPC numeric routine
drifts with no compile-time signal. Small change, removes the trap, and does not
pre-commit workstream 2.
