---
prio: 45
track: A+O
type: bug
blocked-by: []
summary: "Fuzz finding pxx-self_case: at -O3 the compiler produces a DIFFERENT result than it does at -O0 and -O2 for a nested `case` statement, with no diagnostic. fpc-O0, fpc-O2, pxx-O0 and pxx-O2 all agree on 16452949249337348755; pxx-O3 alone says 16571182087083257235. Four independent implementations against one, so the program's meaning is a fact rather than a judgement call, and -O3 is the one that is wrong. --no-dce does not change it, so it is not the DCE pass. Contained to the -O3 free tier today, but it blocks promoting whichever pass is at fault to -O2."
status: new
owner: ""
---

# `-O3` alone computes a different result for a nested `case` statement

- **Type:** bug (optimizer — wrong code, silent) — **Track A**, work-tag **O**.
  Filed 2026-08-30 by the Track T agent from a directed pasmith slice. Per Track
  T's charter T files the finding and does not fix it: this is A's lane.

## What happens

A generated program prints a running checksum. Five oracles, four agree:

| oracle | result |
| --- | --- |
| fpc-O0 | 16452949249337348755 |
| fpc-O2 | 16452949249337348755 |
| pxx-O0 | 16452949249337348755 |
| pxx-O2 | 16452949249337348755 |
| **pxx-O3** | **16571182087083257235** |

No warning, no crash, no diagnostic — the program runs to completion and prints
a wrong number. **Four independent implementations agreeing is what makes this a
fact rather than a judgement call**: the program's meaning is not in dispute, and
`-O3` is the arm that is wrong.

## Reproducing it

`pasmith` is deterministic, so the seed and the generator arguments ARE the repro:

```
python3 tools/pasmith.py --seed 91162 --vars 12 --funcs 2 --stmts 60 --depth 4 \
  --classes 3 --objs 3 --strs 3 --recs 2 --arrs 2 --enums 2 --shorts 2 \
  --excepts 3 --modeprocs 2 --intfs 0 --hier 4 --mptrs 0 --props 3 \
  --exdtor 3 --clsm 3 --checks 1 --consts 1 -o g.pas
./compiler/pascal26 -Fulib/rtl -O2 g.pas g2 && ./g2   # 16452949249337348755
./compiler/pascal26 -Fulib/rtl -O3 g.pas g3 && ./g3   # 16571182087083257235
```

Reproduced at `d7e8e1dc6`; first seen at `8e39c9ed5`. Compiler binary
sha256 `dfb894303…`, self-host fixedpoint verified at HEAD before the run.

## Localisation

Adding `--trace` to the same command emits the checksum after every statement.
Diffing the two traces puts the **first** divergence at **checkpoint 8 of 67, a
`case` statement** — everything before it agrees, so the defect is at that
statement and not accumulated drift. Inserting `Halt;` immediately after
checkpoint 8 preserves the divergence, so the remaining 59 statements are not
involved.

The statement is a nested `case` on `longint(g4) and 3`, whose arms contain a
further two levels of `case`, `for` loops, record and array member access, and
calls to the `Safe*` division helpers.

## What has been ruled out

- **Not DCE.** `-O3 --no-dce` still diverges, identically.
- **Not the `for`-to-`MaxLongint` bound.** The diverging arm contains
  `for li0 := 2147483645 to 2147483647 do`, and `ir.inc:12072` gates for-bound
  re-emission on `OptLevel >= 3`, which made that the obvious suspect. It is not
  it: the loop in isolation gives 3 iterations under pxx at -O0/-O2/-O3 and
  under FPC. Recorded because it is the hypothesis the next reader will also
  form, and it costs them the same twenty minutes.

Not yet bisected to a pass. The remaining `OptLevel >= 3` sites on x86-64 are in
`ir.inc` (10603 — deeper inlining; 12072 — ruled out above), `ir_codegen.inc`
(4547, 5561, 6234, 6258, 6402, 6431), `emit.inc:211` and `symtab.inc:6115`.
**Track T deliberately did not bisect by patching those files**: frankA holds
`ir_codegen.inc`/`emit.inc` under a live Track A lock, and editing them to
diagnose would be exactly the concurrent-edit hazard the lane letters exist to
prevent.

## Reduction: attempted, abandoned, and what it did establish

A line-delta reducer got the program from **2829 to 1635 lines** — 42% removed
with the `-O2` vs `-O3` disagreement intact — before it was killed at load 19.6
on a 12-core workstation. It writes its output only on completion, so **there is
no reduced artefact**; what survives is the measurement that the program is
heavily reducible, which is worth knowing before anyone assumes 2829 lines is
the floor.

**That partial figure is NOT validated and must not be leaned on.** The reducer
ran a cheap two-oracle predicate (`pxx-O2` != `pxx-O3`) with a five-oracle
revalidation deferred to the end, and the end never came. A reducer optimises
for its predicate, so a deleted line that introduces an uninitialised read makes
`-O2` and `-O3` disagreeing *correct* behaviour and the predicate still says
"interesting". Everything above the reduction section was measured on the
unreduced program, where all five oracles ran.

The unreduced repro is complete on its own: pasmith is deterministic, so the
seed and the generator arguments reproduce it exactly.

## Why prio 45 and not higher

`-O3` is the free tier — nothing gates `OptLevel >= 3`, `-O2` is the proven
default, and no shipped artefact is built at `-O3`. So this is contained. It is
not lower than 45 because the failure is **silently wrong output from the
optimizer**, and because it blocks promoting whichever pass is at fault to `-O2`
— the promotion path in CLAUDE.md is exactly "land behind `-O3`, promote per-pass
after the full gate", and a pass cannot be promoted while it is miscompiling.

## Acceptance

`-O3` agrees with `-O0`, `-O2` and both FPC oracles on seed 91162, and the pass
at fault is named in the fix so the promotion decision has something to cite.
