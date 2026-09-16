---
slug: bug-p-a-conditional-directive-cannot-evaluate-in-over-a-set-constant
title: "`{$if}` cannot evaluate `in` over a set-valued constant"
track: P
prio: 35
type: bug
status: done
owner: ""
found-by: frankH
created: 2026-09-11
tags: [conditional-directives, lexer, fpc-corpus, sets]
blocked-by: []
summary: "SPLIT OUT of bug-p-a-conditional-directive-cannot-read-a-const-whose-value-is-not-an-integer-literal on 2026-09-11, whose other half is now fixed. `{$if (cs_opt_use_load_modify_store in supported_optimizerswitches)}` (FPC nld.pas:700) needs the `in` operator over a SET constant that is itself folded from three other set constants (`supported_optimizerswitches = genericlevel1optimizerswitches + ...`, x86_64/cpuinfo.pas:139 over globtype.pas:428-430), plus resolution of an enum MEMBER name. pxx answers `conditional directive: expected operator` at the `in`. 2 units of FPC's 207 stop here (nld, and ncnv whose interface uses nld -- ONE directive reached twice, not two). It is much larger than the half that was fixed: a third value kind on the directive's value stack, set-union folding, and enum-member resolution, where the fixed half reused walks that already existed. FIXED 2026-09-16: all four mechanisms built in paslexer.inc, byte-identical to fpc 3.2.2 on 10 rows. MEASURED, and the answer is the unflattering one: it buys ZERO compiling units -- both units advance to different older walls (nld to a wrong-branch sizeof/{$else}/{$error}, filed separately; ncnv to TDoubleRec). The unit-cycle caveat in the original summary was stale and checking it was still correct: the cycle is no longer in front, both units reached THIS wall first. An explicit-value enum body is deliberately DECLINED rather than guessed, asserted as a must-not-compile control."
---


## Still live at HEAD 2026-09-16, with a standalone repro the ORACLE ACCEPTS

Re-measured because this ticket's last line — "both are behind the unit-cycle
bug anyway, so neither buys a compiling unit today" — was written 2026-09-11 and
the unit cycle was fixed that same evening. **That caveat is stale; whether this
now buys units is unmeasured and is the first thing to check.** The defect
itself has not moved:

```pascal
program s2;
type toptswitch = (cs_opt_level1, cs_opt_level2, cs_opt_use_load_modify_store);
const genericlevel1 = [cs_opt_level1];
      genericlevel2 = [cs_opt_use_load_modify_store];
      supported_optimizerswitches = genericlevel1 + genericlevel2;
begin
{$if (cs_opt_use_load_modify_store in supported_optimizerswitches)}
  WriteLn('IN: yes');
{$else}
  WriteLn('IN: no');
{$endif}
end.
```

| compiler | result |
| --- | --- |
| fpc 3.2.2 | `IN: yes` |
| pxx at HEAD | `pascal26:0: error: conditional directive: expected operator` |

It exercises all three things the summary names — set-union folding across two
constants, an enum MEMBER name, and `in` on the directive's value stack.

**THE FIRST VERSION OF THIS REPRO WAS INVALID AND THE ORACLE IS WHAT SAID SO.**
It declared the constants as TYPED (`const x : toptimizerswitches = [...]`),
which reads naturally and is what FPC's own globtype.pas looks like at a glance.
fpc refuses that with `Illegal expression` — a typed constant is not a constant
expression — so pxx's failure on it would have been evidence about nothing.
Only the untyped form is a question about us.

**So in this area the oracle is not a nice-to-have, it is the ONLY instrument**
— pxx emits `conditional directive: expected operator` for the typed form and
for the untyped form alike, so our own output can never separate a valid repro
from an invalid one here. Any probe against this defect must be compiled under
fpc FIRST; a pxx-only reading of it cannot fail, and it was written as a
hand-off artefact, which is the thing whose whole job is to be trusted by
someone who did not build it.

# `{$if}` over a set-valued constant

Split from
[[bug-p-a-conditional-directive-cannot-read-a-const-whose-value-is-not-an-integer-literal]]
when its other shape was fixed. Keeping the two together made that ticket's
summary describe work of two very different sizes as one thing.

- **Umbrella:** `umbrella-pxx-compiles-fpc-itself`

## The directive, and everything it needs

`nld.pas:700`:

```pascal
{$if (cs_opt_use_load_modify_store in supported_optimizerswitches)}
```

`x86_64/cpuinfo.pas:139`:

```pascal
supported_optimizerswitches = genericlevel1optimizerswitches+
                              genericlevel2optimizerswitches+ ...
```

`globtype.pas:428-430`:

```pascal
genericlevel1optimizerswitches = [cs_opt_level1,cs_opt_peephole];
genericlevel2optimizerswitches = [cs_opt_level2,cs_opt_remove_emtpy_proc];
genericlevel3optimizerswitches = [cs_opt_level3,cs_opt_constant_propagate, ...];
```

So one directive needs, and none of it exists in the conditional evaluator:

1. **A set value on the directive's value stack.** It is tagged today with
   kind 0 = bool, 1 = int, and 2 = no-value (added 2026-09-11 for the
   short-circuit fix). A set needs a fourth and a payload wider than an `Int64`.
2. **Set-union folding** across three named set constants, two of which are in
   a different unit from the third.
3. **Enum MEMBER resolution** — `cs_opt_use_load_modify_store` is a member of an
   enum, not a const, and nothing in this evaluator resolves one.
4. **The `in` operator**, which the expression grammar does not have at all.

## Why it is worth less than its unit count

2 units of 207, and they are **one directive**: ncnv's interface `uses nld`, so
it is the same line reached twice. Both are behind
[[bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface]]
anyway — no unit here compiles when this is fixed.

Contrast with the half that WAS fixed on 2026-09-11, which is the argument for
splitting rather than for doing this next: that one reused walks the evaluator
already had (`PasCondTypeAlias`, `OrdinalNameToTk`, `OrdinalTypeBound`) and added
no new value kind, and it still bought zero compiling units — it moved rgobj to
the next wall. This one builds four new mechanisms for the same yield.

**The cheaper question to ask first:** whether the evaluator should answer `in`
at all, or whether a directive it cannot evaluate should be reported with the
operator named rather than as `expected operator`, which describes the grammar
and not the program. That is a smaller change and it is what a reader of
nld.pas:700 actually needs.

## FIXED 2026-09-16 (frankb-56) — and the stale caveat is now MEASURED, with the answer it feared

The four mechanisms the summary predicted were all genuinely required and all
four are in `paslexer.inc`: a SET value kind (3) with a 32-byte mask payload,
`PasCondSetConstIn` for `+`-joined term folding, `PasCondEnumOrdIn` for an enum
member's ordinal, and `in` as a relational operator. The mask shape is
deliberately the one `ConstSetTerm` (pasparser_decl.inc) already uses — that
walk cannot be reused, because it reads baked masks out of `Data[]` and nothing
is baked during LexAll, but a set now has ONE spelling in this compiler.

**THE STALE CAVEAT WAS THE RIGHT THING TO CHECK AND ITS CONCLUSION SURVIVED FOR
A DIFFERENT REASON.** The line said both units were behind the unit-cycle bug,
which was fixed 2026-09-11. Measured with `fpc_compiler_corpus_probe.sh` before
the fix: the cycle is indeed no longer in front — both units reach THIS wall
first (`oracle-no=0`, so fpc accepts both). Measured again after:

| unit | before | after |
| --- | --- | --- |
| nld | `expected operator` at :2 | `Unsupported tcompilerwidechar size` at :3266 |
| ncnv | `expected operator` at :3440 | `unknown type: TDoubleRec` at :36 (errs=2) |

**So it still buys ZERO compiling units** — exactly as the previously-fixed half
of this ticket did, and that is the honest result rather than a disappointment:
both units advance to different, older walls. `TDoubleRec` is
[[feature-b-rtl-has-no-tdoublerec]], already ranked p85.

**nld's new wall is a WRONG BRANCH and is not this fix's doing.** ncon.pas:968
is `{$if sizeof(tcompilerwidechar) = 2}` / `{$elseif ... = 4}` / `{$else}
{$error Unsupported tcompilerwidechar size}` — FPC's own error arm, and fpc
compiles the unit, so we are taking an arm fpc does not. It was always there,
hidden behind the wall this ticket removed. **The reduction does NOT
reproduce:** `$elseif` works, a local alias sizes correctly, and a cross-unit
`tcompilerwidechar = word` in a used unit also sizes correctly — all three
measured. So the cause is context-dependent and the leading unconfirmed
hypothesis is probe nesting (`PasCondProbeUsedUnits` refuses at
`ProbeDepth > 0`, so a sizeof needing its own probe while already inside one
declines, and under `PasCondQuiet` an unresolved expression answers False,
which walks every arm down to the `{$else}`). Filed separately rather than
guessed at here.

**WHAT THIS DELIBERATELY REFUSES.** An enum with an explicit value in its body
(`(a, b := 5, c)`) makes position stop meaning ordinal — c is 6, not 2 — so the
walk declines the whole declaration rather than counting commas. fpc answers
that case correctly and we refuse it. Refusing is the safe direction where the
alternative is a plausible wrong ordinal, which in a set test does not fail but
takes the other branch. Asserted as a must-not-compile control.

**THE FPC SEED CANARY EARNED ITS KEEP.** The first version walked the enum body
on the `for` variable itself, which pxx allows and FPC refuses
(`Illegal assignment to for-loop variable`). It built, self-hosted and passed
its own tests; only the canary saw it. That is the declaration-order/seed class
the canary exists for, arriving in a new subsystem.

Gate: `gate.sh quick` GREEN. Tests byte-identical to fpc 3.2.2 on all 10 rows,
every membership row paired with a non-membership row so an over-approximating
fold cannot pass, and the member under test not always first.

## Log
- 2026-09-16 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
