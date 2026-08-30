---
slug: bug-p-a-property-in-an-interface-declaration-is-rejected
track: P
prio: 45
type: bug
status: done
owner:
blocked-by: []
summary: "`property Current: T read GetCurrent;` inside an `interface` declaration is rejected -- `expected 'end' before 'property'`. FPC's IEnumerator (rtl/objpas/objpas.pp:79) declares exactly that, so lib/rtl's IEnumerator had to ship WITHOUT it. Generic or not makes no difference; mode DELPHI and mode PXX both fail. THE TRAP: an UNINSTANTIATED generic interface carrying a property compiles clean, because its body is never parsed -- so the obvious quick check returns a FALSE GREEN and you must instantiate to see the failure. Control included (+1 proc) proving the instantiating probe really generated code."
---

# A `property` inside an `interface` declaration is rejected

## Measured

Binary `e8cbe7767cc6` (self-host fixedpoint at HEAD `4dae78ad9`). Five probes,
pass/fail read off the **exit code** — note that pxx prints its success line
`ok: ... [code=... procs=N]` on stdout, so "produced output" is not a failure
test and a harness that treats it as one reports every probe as FAIL:

| probe | interface | property? | instantiated? | result |
| --- | --- | --- | --- | --- |
| a | non-generic | yes | — | **FAIL** `pascal26:6: expected 'end' before 'property'` |
| b | generic | no | no | ok, 129 procs |
| c | generic | **yes** | no | **ok, 129 procs — VACUOUS** |
| d | generic | yes | **yes** | **FAIL** `pascal26:6: expected 'end' before '.'` |
| e | generic | no | yes | ok, **130 procs** |

`a` is the plain statement of the bug: nothing generic is involved.

## The trap, which is the reason this ticket is worth its length

**`c` is a false green.** A generic interface whose body is never instantiated is
buffered as tokens and never parsed, so a property inside it is never seen. The
natural way to check "does pxx accept a property on an interface?" is to declare
one and compile — and that answers **yes**, incorrectly.

`e` is the control that makes `d` a claim rather than an impression: 129 -> **130
procs** shows the instantiation in the `d`-shaped probe genuinely generated code,
so `d`'s failure is the property and not a probe that quietly did nothing. This
is the same non-vacuity discipline [[feature-pascal-corpus-expansion]] uses for
rung 6a (+11 procs), and it is needed for exactly the same reason.

Note also that `d`'s message differs from `a`'s (`before '.'` vs `before
'property'`) while pointing at the same line 6 — the property line. Do not treat
the two messages as two bugs.

## Impact

Low-to-moderate, and honestly bounded: **nothing is blocked on it right now.**
`lib/rtl/classes.pas` ships `IEnumerator<T>` without FPC's
`property Current: T read GetCurrent;` and the rtl-generics corpus does not care,
because it never references `IEnumerator` at all — it uses only
`IEnumerable<T>`, six times, all as `AddRange` parameter types. Callers write
`GetCurrent` instead of `.Current`. It becomes real when someone wants `for..in`
over an interface-typed enumerable, or FPC-parity source that reads `.Current`
off an interface.

## Gate

`make compiler/pascal26` + probes `a` and `d` above compiling clean, with `e`
re-run to confirm the control still holds.

## Provenance

Flagged as an unknown by [[bug-b-rtl-provides-no-ienumerable-generic-interface]]
("`property ... read` on an interface is the one shape that should be checked
rather than assumed") and confirmed by measuring it. The flag was right.

---

## FIXED — and it was TWO defects, the first hiding the second

The ticket is about parsing, and parsing was half of it. With `property`
accepted in an interface body the probes compiled and then **segfaulted on
use** — which is the more expensive half, and it would have shipped invisibly
behind a green "does it compile?" check. That is this ticket's own probe-`c`
warning one layer further in: `a` and `d` compiling clean is *not* the same
claim as an interface property working.

### Defect 1 — the interface member loop had no `property` arm

The interface arm of `ParseTypeSection` accepted only `procedure`/`function`, so
a `property` ended the member loop and the following `Expect(tkEnd)` reported
`expected 'end' before 'property'` at the property's line. There was nothing for
that loop to call even if it had wanted to: the property parser was ~170 lines
written INLINE in the CLASS member loop a thousand lines away.

Writing a smaller second parser for the interface case was the obvious move and
is what `normalise-dont-special-case.md` exists to refuse — an interface property
takes `index`, `default`, hint directives and inherited redeclaration exactly as
a class property does, and the second path is the one that stays broken. So the
inline block was extracted **verbatim** into `ParsePropertyDecl(ci,
curPublished)` (no behaviour change for the class case, which is what makes the
extraction reviewable) and the interface loop now calls it. Interfaces live in
the same `UCls` tables and have no fields, so `FindUField` always misses and a
read/write name always lands in the METHOD slot — the correct reading for an
interface property, with no further work.

### Defect 2 — eleven copies of "how is an accessor dispatched", all with two answers

Then `i.V` compiled and crashed. Every property access built its accessor call by
hand, and all **eleven** copies spelled the same two-way choice: `AN_VIRTUAL_CALL`
when the accessor has a vtable slot, `AN_CALL` when it does not, with Self at
argument 0.

The choice is **three**-way. An interface receiver dispatches through the IMT as
`AN_INTF_CALL`, carries its slot in `ASTSOffset` rather than `ASTRight`, and takes
Self from the fat pointer's instance word instead of argument 0. The ordinary
method call `i.M(...)` already had that arm; the property path, being a separate
copy, did not — so a property on an interface read a class VMT off a fat pointer.

Eleven copies is well past `root-cause-over-microfix.md`'s "two is a smell, three
is a design flaw", so the fix is one function rather than a twelfth copy:

- **`MakeAccessorCall(mci, mmi, mpi, recvNode, firstArg)`** — `pasparser_call.inc`,
  beside `ParsePropIndexArgs`, which builds the arguments it takes. `firstArg` is
  the caller's chain of REAL arguments with **no Self in it**: where Self goes is
  precisely what separates the three shapes, so it is this function's decision
  and not each caller's.
- **`AccessorArgChain(margIdx, mlastArg, valueNode)`** — the setter's
  `[index...] , value` splice, which five of the eleven also spelled out.

All eleven now call it: both Self-relative arms, both default-property arms, the
NilPy augmented-assignment read and write legs, the qualified `o.Prop` getter and
setter, the selector-path getter and setter, and the grouped `(expr).Prop` getter
in `pasparser_expr.inc`. The `pyparser.inc` twins are **Track N's file** and were
left alone — they inherit nothing from this and still have the two-answer form,
which is a Track N ticket rather than a cross-lane edit.

### Measured

Binary `93e89c5795c1`, self-host fixedpoint at HEAD.

| probe | result |
| --- | --- |
| `a` non-generic interface + property | **ok**, runs, prints `a 42` |
| `d` generic interface + property, instantiated | **ok**, runs, prints `d 42` |
| `e` control, generic interface, no property, instantiated | **ok**, 131 procs — same as `d`, so `d` is not vacuous |

New test `test/test_property_in_an_interface.pas` (wired into `test-core`), read
/ write / indexed-read plus a `direct` control row, oracle **FPC -Mdelphi**,
which prints the same four lines. It is a real measurement in both directions:

- on the pinned binary it does not compile (`expected 'end' before 'property'`);
- with **defect 1 fixed and defect 2 not**, it compiles, prints `direct  40` —
  the control row, taking the arm that already worked — and then **segfaults on
  the property read**. That row is why the test can tell "interface dispatch is
  broken generally" apart from "only the property path is broken".

## The near-miss worth keeping: a green self-host proved less than it looks

An intermediate state of this work had a **duplicated `else if CurTok.Kind =
tkProperty then`** in the class member loop — the first with an empty statement
for a body. Any class property then matched a branch that consumed nothing, and
the member loop spun forever.

`make compiler/pascal26` **passed**, twice, printing `converged after 1
round(s)`: the compiler is written in a deliberately procedural Pascal subset and
**declares no class properties**, so its own sources never reach the loop that
hangs. The fixedpoint is exactly as load-bearing as CLAUDE.md says — it just
cannot see a construct the compiler does not use. `gate.sh quick`, the step the
loop calls OPTIONAL, is what caught it, as a **timeout** on
`quick_canary_nilpy.npy` (pylib is full of class properties) rather than as an
error.

Two things follow, and neither is "widen the loop":
- *"my repro passed"* and *"the compiler still works"* are different claims when
  the repro is Pascal the compiler itself never writes. A one-line probe in the
  affected shape is the cheap cover — the same lesson as the marshalling note in
  CLAUDE.md, arrived at from the other direction.
- A **hang** has no error text, so nothing in the output says which step is
  wrong. The step that told the truth here was `git stash` + rebuild on a clean
  HEAD: 2.5s versus a 120s timeout, separating "master is broken" from "my copy
  is" in one measurement rather than an argument.

## Log
- 2026-08-30 — resolved, commit 0f0fd6642.
