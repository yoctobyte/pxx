---
slug: feature-a-fold-the-consensus-dead-branch-core-at-every-level
track: A
prio: 65
type: feature
status: done
blocked-by: []
found: 2026-08-31
found-by: frank-user
owner: ""
summary: "Implements the ruling in decided/decide-should-unreachable-code-that-breaks-the-LOAD-be-pruned-at-O0. The SHORT-CIRCUIT half is DONE (88ef1232f C, e31f7112f Pascal) and the DEAD-ARM PRUNE is DONE for `if` and `while` in shared lowering, with the address-escape guard (part 2). Parts 3 (-OO, the source-1:1 named flag, gated at three choke points so a later fold inherits it) and 4 (the charter amendment) are DONE too. Part 1s third shape -- statements after a return/Exit, still -O0 only -- is SPLIT OUT to feature-a-prune-statements-after-a-return-at-O0, being AN_SEQ reachability rather than a constant condition, because gcc, clang and tcc all do and tcc has no optimizer, so this is LOWERING. The SHORT-CIRCUIT half is DONE (88ef1232f, 2026-09-01) and it was worse than this file said: `0 && f()` folded at NO level, -O3 included, not just at -O0. HARD CONSTRAINT, measured: prune only when unreachable AND the address does not escape; a dead arm holding a label whose address is taken is kept by all three at every level, and an if-only test will not catch getting this wrong. Both frontends: the Pascal arm is measured open, `if False and (F=0)` keeps its dead call at -O2. Also adds -OO for the true source-1:1 build, as a NAMED FLAG not a level."
---

# Fold the consensus dead-branch core at every level

Implements `decided/decide-should-unreachable-code-that-breaks-the-LOAD-be-pruned-at-O0`
(ruled by the owner 2026-08-31). Read the ruling for the three-compiler
measurement; this ticket is the work.

## Symptom this closes

```
-O0: symbol lookup error: undefined symbol: NEVER_stmt   (exit 127)
-O1/-O2/-O3: fine
```

**That second line was FALSE for one of the shapes this ticket names, and the
correction is why the busybox work hit it** (frankD, 2026-09-01). The listed
core includes *"short-circuit against a literal"*, and that shape folded at **no
level at all** — `0 && f()` kept the call at `-O0`, `-O1`, `-O2` and `-O3`.
The mechanism is specific and it is why raising `-O` did not help: `&&`/`||`
lower through a boolean temp and the branch RELOADS it, so `IROptConstBranch`
— which reads the operand feeding the jump — saw a `load_sym` and gave up. A
reader who took the two lines above at face value would have concluded the
default build was safe and moved on; that is exactly what the summary rule
exists to stop.

**That half is now DONE** — `88ef1232f`, folded in the C frontend at the three
sites a chain needs (`CMakeBinop`'s `&&`/`||`, `CMakeTruthy`, unary `!`), with
`test/c_short_circuit_const_folds.c`. The two lines above are true again.

**What is left is the DEAD ARM, and it is the larger half.** Once the condition
is a constant, the arm behind it is still emitted at `-O0`:

```c
if (0 || 0 || !1) { return NEVER(); }   /* condition folds; arm survives at -O0 */
```

Rows 13/14/15 of `test/c_short_circuit_const_folds.c` are exactly this and are
built at the default level for that reason; when this ticket lands, add the
`-O0` run there.

**THE PASCAL ARM IS OPEN AND MEASURED** (frankD, 2026-09-01, compiler
`b4ffb6c0caf4`). The same shape through the Pascal frontend keeps its dead call
at **`-O2`**, not merely at `-O0`:

```pascal
function NeverDefinedP: Integer; external name 'never_defined_P';
begin
  if False and (NeverDefinedP = 0) then Writeln('x');
  if (False or False) or (not True) then Writeln('y');
end.
```

Both `-O0` and `-O2` die with `undefined symbol: never_defined_P`. This is the
sibling of the C defect, in the frontend the C fix does not touch — `and`/`or`
on constants are not folded there either. Whoever takes this ticket owns both
arms: the C fold went in `cparser.inc` because parsers are duplicated per
language by design, so the Pascal one needs its own, or the whole thing needs
to move into shared lowering as this ticket's part 1 already proposes.

`IROptDeadCode` and `IROptConstBranch` live in `IROptimize`, gated at
`ir_codegen.inc:11332` behind `if OptLevel >= 1`, so `-O0` has never pruned any
dead code. The binary links, warns, and dies before `main`.

## What to build

**1. The consensus core, at every level.** Fold a condition that is constant *in
the expression itself* — literal, `sizeof` comparison, short-circuit against a
literal — and drop statements after a `return`. This belongs in **lowering**, not
in `IROptimize`; leave the `OptLevel >= 1` gate exactly where it is. Both
frontends and all six backends inherit it from shared IR.

**2. The address-escape guard — do not skip this.** Prune only when the arm is
unreachable **and** no label inside it has had its address taken:

```c
void f(void){ void *p = &&inside; if (0) { inside: N(); } goto *p; }
```

gcc, clang and tcc all **keep** `N` here, at every level. Pruning on
reachability alone silently breaks computed-goto code.

**3. `-OO` — the true source-1:1 build**, as a named flag, never a level below
zero (`decided/decide-the-o-level-charter`: trade-offs are not levels). This is
the byte-identity reference used to separate a lowering bug from an optimizer
bug, which is the whole reason `-O0`'s charter existed; it moves here rather than
disappearing.

**4. Amend the charter line.** `-O0 = zero optimization, source 1:1` becomes
`-O0 = zero optimization` with 1:1 pointing at `-OO`. Amend it in the open, do
not quietly violate it.

## Out of scope for the core

Constant propagation through a variable (`const int z = 0; if (z)`) — gcc and tcc
keep it, clang prunes it, so nothing portable relies on either answer. The
ruling leaves *diagnose vs quietly emit* here to this ticket; a hard compile-time
error is defensible and costs no real code.

## Acceptance

- The busybox `xatonum.h` shape links and runs at **every** level, `-O0` included.
- The computed-goto case above still resolves `N_addrtaken` at every level.
- `while (0) { N(); }` and `return; N();` both covered — a fix touching only `if`
  will miss them, **and no `if`-only test will say so** (measured in the parent).
- Self-host fixedpoint unchanged; `-OO` reproduces today's `-O0` bytes.
- Cross targets: unmeasured everywhere in this chain. Carry a one-line repro per
  frontend the quick tier does not cover.

## Unblocks

[[feature-c-corpus-busybox-applet]] — the corpus this was found closing.

## 2026-09-02 (frankC) — THE PASCAL SHORT-CIRCUIT HALF IS DONE

The arm this ticket called "measured open" is closed. `pasparser_expr.inc` now
folds a constant LEFT operand of `and` (ParseTerm) and of `or`
(ParseSimpleExpr), and `not` over a Boolean literal (the `tkNot` factor), each
returning a literal so a chain collapses.

It was worse than recorded here: the repro failed at **-O3 too**, not only at
-O0 and -O2 — the same mechanism the C half found, and for the same reason.

```
before:  -O0 rc=127  -O2 rc=127  -O3 rc=127   undefined symbol: never_defined_P
after:   -O0 alive   -O2 alive   -O3 alive
```

Semantics verified row by row with a HIT COUNT beside every value, because a
fold that drops an operand it should have kept still yields the right value for
these shapes — `True and T1` is True either way. Rows that must NOT fold are in
the test on purpose: `xor` does not short-circuit; bitwise `and`/`or`/`not` on
integers is a different operator with the same spelling; a RUNTIME-false left
operand short-circuits without being folded. Whole-file output is **byte-identical
to fpc 3.2.2**. `test/test_pascal_const_logic_folds.pas` (semantics) and
`test/test_pascal_dead_arm_ext.pas` (link-time, wired at all three levels).

Deliberately not folded: `const B = False`, matching the C side and the ruling —
gcc and tcc keep propagation-through-a-variable, clang prunes it, so nothing
portable may rely on either answer.

## What REMAINS, measured at the same tree

**Part 1's dead-ARM prune, and it is still the larger half.** With the condition
now folded, the arm behind it is still emitted at `-O0`:

```
if False then WriteLn(NeverArm);     { never_arm_P declared, never defined }

-O0 rc=127  undefined symbol: never_arm_P
-O2 alive   -O3 alive
```

So `-O0` is now the ONLY level that fails, where before the fold every level
did. `IROptConstBranch` catches it from `-O1` up, which is exactly why this
belongs in lowering and why the `OptLevel >= 1` gate at `ir_codegen.inc` must
stay where it is.

Also untouched, all still open: **part 2** the address-escape guard (a dead arm
holding a label whose address is taken is kept by gcc/clang/tcc at every level —
and Pascal has no computed goto, so this is a C-frontend obligation), **part 3**
`-OO`, and **part 4** the charter amendment.

## 2026-09-02 (frankC) — THE DEAD-ARM PRUNE IS DONE FOR `if` AND `while`

Part 1's larger half. `IRLowerAST` now drops the dead arm of a constant-condition
`AN_IF`, and a constant-FALSE `AN_WHILE` entire, in SHARED lowering — so both
frontends and all six backends inherit it, and the `OptLevel >= 1` gate on
`IROptimize` stays exactly where it was.

```
                       -O0        -O1/-O2/-O3
if False then Never    was 127    was alive     now alive at every level
while False do Never   was 127    was alive     now alive at every level
```

**THE `while` ARM WAS FOUND BY TESTING THIS TICKET'S OWN ACCEPTANCE LIST, not by
believing the `if` fix.** With `AN_IF` pruning and nothing else, `if False then
WriteLn(NeverW)` was clean at -O0 while `while False do WriteLn(NeverW)` two
lines below it still died with `undefined symbol`. The acceptance section
predicted this in writing — *"a fix touching only `if` will miss them, and no
`if`-only test will say so"* — and it was right. Both shapes are now one
mechanism reading one helper, per normalise-dont-special-case.

**`while True` IS DELIBERATELY NOT PRUNED, and that is a correctness
requirement, not caution.** It is the desugaring target for Ada `loop`/`exit
when` (aparser.inc) and for the post-bearing C `for`, so folding a
constant-condition loop *regardless of its value* would delete a running
program's body. `test_const_dead_arm_prune.pas` carries the positive control for
it: a `while True ... Break` whose counter stays 0 if the loop is wrongly
dropped.

**Checked BEFORE building, because these are the two shapes that would have made
this a miscompile rather than a bug:** `repeat` has its own `AN_REPEAT` kind and
never becomes an `AN_WHILE`, so `repeat ... until True` cannot be reached; and
`do { } while (0)` — the most common idiom in C — desugars to
`flag=1; while (flag || 0)`, whose condition holds a VARIABLE, so `ASTConstCond`
rejects it and the loop is untouched.

### The escape guard

Unchanged in design and now applied to both kinds: an arm holding `AN_LABEL`,
`AN_LABELADDR` or `AN_GOTO_INDIRECT` is KEPT. Deliberately broader than "the
address was taken" — Pascal reaches the same hazard by a different route (`goto`
into the arm), and the recursion's budget answers TRUE on exhaustion, because a
guard that runs out of room must fail toward emitting code. **Proven
load-bearing, not decorative:** with it disabled the compiler refuses the C
computed-goto program outright with `invalid IR label-address target (label not
defined)`.

### What was measured before landing

Both differentials are ISOLATING: the pre-change compiler was built from ONE
tree with only `ir.inc` and `ast_arena.inc` stashed, so a difference below can
have no other author. (Confirmed at the same time: the 9 commits this tree was
behind touched neither `compiler/` nor `lib/`.)

- **-O2, IMAGE identity, whole Pascal corpus: `ok=1410 skip=232 fail=0`.** Not
  "the output matched" — the two compilers emit BYTE-IDENTICAL binaries for
  every program at the default level. `IROptConstBranch` already reached this
  fixed point from -O1 up, so the new lowering AGREES with the existing pass
  rather than competing with it, and -O0 is the only level whose bytes move.
  This is the claim that makes a change to shared `AN_IF`/`AN_WHILE` lowering
  safe to land.
- **-O0, OUTPUT differential, whole Pascal corpus: `ok=1410 skip=232 fail=0`** —
  the level that does change, and no program's behaviour moved with it.
  An earlier run of this read `fail=4` and **all four were the instrument**:
  three `test_c_gtk_*` rows differing only in the HH:MM:SS.mmm and
  `(process:PID)` that GLib prints itself, and `lib_mimic_urllib_request_server`
  differing only in the ephemeral port it bound, both sides timing out
  identically. The harness now normalises exactly those three patterns and
  nothing wider: the Pascal prune test's whole discriminator is that a wrongly
  kept arm changes `n=15`, so a filter broad enough to hide a PID would hide the
  finding the harness exists to catch.
- The harness's own control had to be replaced first: it used
  `test_pascal_dead_arm_ext.pas`, which exercises the PARSER fold that landed at
  `e31f7112f` and is therefore in BOTH binaries, so the two images matched and
  the control correctly refused to certify the run. A control drawn from the
  wrong population passes and certifies a broken instrument; this one failed
  instead, which is the only reason the run was not believed.
- C side matches the **gcc oracle** at -O0, -O2 and -O3. gcc links the file at
  -O0 with no optimiser asked for, including the new `while (0)` row — which is
  the evidence that this is lowering and not an optimisation.

`test/test_const_dead_arm_prune.pas` (renamed from `..._const_if_...`, because
after the `while` rows the old name named only half of what it tested) and
`test/c_const_if_dead_arm_prune.c`, both wired at every level.

`compiler.pas:914`'s comment claimed -O0 "remains the byte-identity reference".
This change falsifies it, so it is corrected in the same commit and points at
`-OO`.

## What REMAINS

**Part 1's third shape: statements after a `return`/`Exit`.** Still open, still
-O0 only, measured at this tree:

```pascal
procedure P; begin Exit; WriteLn(NeverR); end;   { -O0 rc=127, -O2 alive }
```

It is NOT the same mechanism and is deliberately not bolted onto this one: `if`
and `while` are a CONDITION being constant, while this is statement-sequence
REACHABILITY inside `AN_SEQ`, needing a notion of which node kinds terminate a
block. The same label guard would apply.

**Part 2** the address-escape guard is DONE (above).

## 2026-09-02 (frankC) — PARTS 3 AND 4 ARE DONE

**Part 3, `-OO`.** A named flag, never a level below zero, per this repo's
o-level charter: an author must choose WHICH trade, not HOW MUCH. It is `-O0`
plus `SourceOneToOne`, which switches off the dead-arm prune and the
`e31f7112f`/`88ef1232f` const folds — so it emits what the source says, for the
whole pipeline.

The gate is at **three choke points, not at the call sites**: `ASTConstCond`
(shared lowering), `PasBoolLit` (Pascal parser), `CConstIntLit` (C parser).
Each is the single question its folds ask — verified by listing every caller,
all of which are folds — so a fold added later inherits `-OO` without anyone
remembering to gate it.

`-OO` is a DIAGNOSTIC mode and not a shipping one: it deliberately emits calls
the program cannot reach. Measured, 200-statement dead arm:

```
-OO code=134936B    the arm is emitted, 1:1 with source
-O0 code= 89880B    pruned; this is the RTL floor
-O2 code= 65304B
```

`test/test_source_one_to_one_oo.pas` **asserts a FAILURE at -OO**, deliberately
inverted against every other row in the suite, and that inversion is the flag's
positive control: `never_oo_P` is declared and never defined, so emitting the
unreachable call is observable as a binary that cannot start. A flag that
silently did nothing would pass a row asserting success and certify a flag that
does not exist. Both frontends verified; ordinary C is unchanged at `-OO` and
still matches gcc.

One reading was chased rather than accepted: `-OO` and `-O0` reported an
IDENTICAL `code=89880B` on the prune test while their images differed by 1465
bytes. Builds are deterministic (same flags twice, byte-identical), and the
explanation is that 89880B is the **RTL floor** — both programs are tiny once
pruned, so code size is dominated by the runtime. The 200-statement arm above
is what made the flag's effect legible.

**Part 4, the charter.** `decide-the-o-level-charter` had `O0 = zero
optimization, source 1:1`. The two halves came apart, so `source 1:1` MOVED to
`-OO` rather than being quietly violated, and the amendment says why in the
open: gcc, clang and tcc all prune here with no optimiser asked for, and tcc HAS
no optimiser, so this is lowering — a level called "zero optimization" that
performs zero LOWERING would not be a compiler.

## This ticket is DONE

The one shape left from part 1 — statements after a `return`/`Exit` — is split
out as [[feature-a-prune-statements-after-a-return-at-O0]], because it is a
different mechanism (`AN_SEQ` reachability, needing a notion of which node kinds
terminate a block) and deserves its own place in the ranker rather than a tail
on a closed ticket.

## Log
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
