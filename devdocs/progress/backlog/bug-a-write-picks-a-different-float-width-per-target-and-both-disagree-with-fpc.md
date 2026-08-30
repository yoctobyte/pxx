---
track: A
prio: 30
type: bug
blocked-by: []
summary: "`Write` of a real renders at a width that depends on the TARGET: x86-64 prints `s1+s2` (Single+Single) in Double form where FPC and xtensa print Single, and xtensa prints `i/2` in Single form where FPC and x86-64 print Double. Two backends, opposite errors, same source and same compiler. The values are right; the width dispatch is not."
status: backlog
owner: unassigned
---

# Write picks a different float width per target, and both targets disagree with FPC

- **Type:** bug — **Track A** (target-dependent, so it is below the frontend:
  the same AST renders two ways).
- **Found:** 2026-08-30 (frankC), **unmasked by**
  [[bug-a-a-hidden-aggregate-result-temp-gets-an-unaligned-frame-slot]]. Before
  that fix `test_cross_float` SIGBUSed on xtensa before printing anything, so
  none of this was reachable.

## Measured — FPC as the oracle, not the x86-64 build

`test/test_cross_float.pas`, three implementations, same source:

| out | expression | FPC | pxx x86-64 | pxx xtensa |
| --- | --- | --- | --- | --- |
| 1-4 | `s1+s2` … `s1/s2` (Single op Single) | Single | **Double** | Single |
| 10 | `i * s1` (Integer * Single) | Single | **Double** | Single |
| 12 | `i / 2` (Integer / Integer) | Double | Double | **Single** |
| 21-22 | `Frac(d1)`, `Int(d1)` | Extended (20 digits) | Double | Double |

Single form is `3.500000000E+00`; Double is `3.5000000000000000E+000`;
Extended is `5.00000000000000000000E-0001`. **The values are correct
everywhere** — only the rendered width differs.

The last row is the known no-Extended difference and is a separate, low-value
matter. The first three are the finding.

## Why this is filed as a bug and NOT as Track F

CLAUDE.md makes float FORMATTING Track F and low prio by definition, and the
symptom here is a digit count — so the F reading is available and I considered
it. It is rejected on the rule that decides these: **rank the mechanism, never
the datatype**, and *when it is a close call it is NOT F.*

The mechanism is not a rendering policy. A rendering policy cannot be
target-dependent: `symtab`/frontend typing is shared, and these two backends
consume the same AST. Something below the frontend is choosing a different
float width for the `Write` argument on x86-64 than on xtensa, and doing it in
**opposite directions on different lines** — x86-64 widens where it should not,
xtensa narrows where it should not. That is dispatch, and it is exactly the
"codegen bug that merely lives in float code" the F charter excludes.

If triage shows the width is genuinely chosen by a formatting routine rather
than by lowering, re-track it to F and park it; do not assume that from the
symptom.

## Also worth noting: the suite cannot see this

`make test-xtensa` compares the xtensa build against the **x86-64 build**, not
against FPC. So the x86-64 error on lines 1-4 and 10 is invisible to it by
construction — it is the reference — and the xtensa error on line 12 shows up
as "xtensa diverges" when both are wrong in different places. **A
self-differential's reference is not an oracle**, and this is what that costs:
the x86-64 half of this bug has been reachable on every run of the suite since
the test was written, and was found only by putting FPC beside it.

## Repro

```
fpc -otcf_fpc test/test_cross_float.pas && ./tcf_fpc
./compiler/pascal26 test/test_cross_float.pas /tmp/tcf_x64 && /tmp/tcf_x64
./compiler/pascal26 --target=xtensa --platform=posix --xtensa-soft-mulhigh \
    test/test_cross_float.pas /tmp/tcf_xt && tools/run_target.sh xtensa /tmp/tcf_xt
```

Isolated `WriteLn(s)` for a plain `s: Single` agrees across all three, so the
divergence needs the EXPRESSION, not merely the type — that is where to start.

## Bound

Hosted xtensa profile, Call0, `--xtensa-soft-mulhigh`, at the alignment fix's
sha. Not checked on i386/aarch64/arm32, and not checked on real silicon.
`--xtensa-soft-mulhigh` labels an emulator divergence for multiplies, so the
`s1*s2` line specifically is worth re-measuring without the flag before leaning
on it; the `+`, `-`, `/` lines carry the finding on their own.
