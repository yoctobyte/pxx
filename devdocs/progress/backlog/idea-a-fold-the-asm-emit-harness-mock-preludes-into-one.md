---
track: A
prio: 35
type: idea
blocked-by: []
---

> **Re-priced 15 -> 35 by the coordinator, 2026-08-30.** frankA's call to file
> this rather than do it during the p70 red was right, and the reasoning for 15
> was sound at the time it was written. What moves it is the count, not the risk:
> this is the THIRD instance in the same file (`AsmRv32ProcessInlineLine`,
> `InlineAsmLineHoleN`, now `AIntToStr`), and `devdocs/dev/root-cause-over-microfix.md`
> prices two as a smell and three as a design flaw. It also has the one property
> a low-prio ticket must not have: it re-arms itself. Every encoder change from
> here can turn a green harness red for a reason that is not in the encoder, and
> the five harnesses were only recently wired into `test-asm`, so the population
> that can trip it just grew.
>
> Not raised further, for frankA's own reasons, which stand: the rot is no longer
> silent, the refactor risks five green harnesses to close nothing currently red,
> and the preludes are not identical so it is not mechanical. 35 says "do it
> deliberately, on a quiet lane, before the next encoder campaign" — not "do it now".

# Fold the five asm-emit harnesses' mock preludes into one shared include

The `test/test_asm_emit_{x64,386,a64,arm32,rv32}.pas` oracle harnesses each mock
the compiler environment by hand — a byte sink (`EmitB`/`EmitI32`/`Patch32`),
`Error`, `CaseEqual`, `AppendChar`, an empty inline-asm line pool, the
`AsmText*` string helpers — and then `{$include}` the real shipped encoder to
assert its bytes against `llvm-mc`. The mocks are duplicated: 4 of the 5 carry
their own copy of `AsmTextTrim`, and each carries its own copy of most of the
rest.

**The failure mode this creates** is that any shared helper an *included*
compiler file grows must be added to each prelude by hand, and nothing connects
the two edits. Recorded instances, all in `test_asm_emit_rv32.pas` alone:

| date | the encoder grew | the harness said |
| --- | --- | --- |
| 2026-08-21 | `AsmRv32ProcessInlineLine` | `undefined variable (InlineAsmLineHoleN)` |
| 2026-08-21 | the inline-asm line pool it reads | same, silently |
| 2026-08-30 | `RISCVRelCheck`, formatting with `AIntToStr` | `undefined variable (AIntToStr)` |

The last one is [[regression-test-asm-test-asm-emit-rv32]] — a good encoder fix
(`2f81d8008`, PC-relative range guards) that reddened the suite purely by calling
a helper the mock did not have. This is the shape
`devdocs/dev/normalise-dont-special-case.md` names: one concept ("the compiler's
shared helpers, mocked for an encoder harness") served by five hand-rolled
mechanisms, so a fix to one arm leaves four.

## Why it is prio 15 and not higher

**The rot is no longer silent, which is most of the value already.**
`chore-a-sweep-the-unwired-tests-into-the-suite` wired all five into `make
test-asm`, so 2026-08-30's instance surfaced the day the encoder changed rather
than years later — that is the difference between the first two rows of the table
and the third. What is left is the per-instance cost of adding one mock in one
file, which is small.

Against that, the refactor puts five currently-green harnesses at risk at once,
and it is not purely mechanical: the preludes are *not* identical (386 carries 26
mocked entry points to rv32's 19, and the byte sinks differ), so a shared
`test/asmharness_prelude.inc` has to separate the genuinely arch-independent part
(`Error`, `CaseEqual`, `AppendChar`, `AIntToStr`, `AsmText*`) from the per-arch
part, which is the actual design work.

## Shape, when someone takes it

- `test/asmharness_prelude.inc` = the arch-independent mocks, including every
  `compiler/util.inc` export (`AIntToStr`, `RealTypeKind`, `TargetIsEspClass`,
  `SoftFloatMissing`) whether or not an encoder calls it today — the point is
  that the next one that does costs nothing.
- Each harness keeps its own sink and its own arch include.
- Gate: all five compile and print their `ALL <arch> ASM EMIT TESTS PASSED` line
  (they are wired into `make test-asm`).

Note that `util.inc` itself cannot simply be included by a harness: it opens on
`AppendChar`, which lives in `lexer.inc`, so pulling it in drags the lexer
behind it. That is why `AppendChar` is hand-mocked in these files today, and it
is the constraint the shared prelude has to live with.
