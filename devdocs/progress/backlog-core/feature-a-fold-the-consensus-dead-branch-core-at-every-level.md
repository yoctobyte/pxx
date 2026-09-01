---
slug: feature-a-fold-the-consensus-dead-branch-core-at-every-level
track: A
prio: 65
type: feature
status: open
blocked-by: []
found: 2026-08-31
found-by: frank-user
owner: ""
summary: "Implements the ruling in decided/decide-should-unreachable-code-that-breaks-the-LOAD-be-pruned-at-O0. What REMAINS is the DEAD-ARM PRUNE at -O0: fold statements after a return, and drop the arm of an if whose condition is already a constant, because gcc, clang and tcc all do and tcc has no optimizer, so this is LOWERING. The SHORT-CIRCUIT half is DONE (88ef1232f, 2026-09-01) and it was worse than this file said: `0 && f()` folded at NO level, -O3 included, not just at -O0. HARD CONSTRAINT, measured: prune only when unreachable AND the address does not escape; a dead arm holding a label whose address is taken is kept by all three at every level, and an if-only test will not catch getting this wrong. Both frontends: the Pascal arm is measured open, `if False and (F=0)` keeps its dead call at -O2. Also adds -OO for the true source-1:1 build, as a NAMED FLAG not a level."
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
