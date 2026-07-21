---
track: A
prio: 55
type: feature
blocked-by: []
---

# Wire pyeval into NilPy exec() — auto-use triggers an unrelated str-index segfault

The pyeval interpreter (feature-lib-pyexec) is complete and standalone-green (14
test files, ~84/131 corpus with a full stub). The final step is making NilPy's
`exec()` actually run it. **The wiring WORKS end-to-end** but auto-using the unit
regresses an unrelated NilPy test, so it is parked here for a careful root-cause.

## What was proven (2026-07-21)

Two-line source change:
- `compiler/pyparser.inc`: `ParseUsesUnit('pyeval');` right after
  `ParseUsesUnit('pylib');` (pyeval uses pylib + typinfo, must follow pylib).
- `compiler/parser.inc`: the `exec()` binding `FindProc('pyexec')` →
  `FindProc('EvalPyStmts')`.

Prerequisite already landed on master: pyeval's local var `str` renamed to `slit`
(it collides with NilPy's `str` type keyword when pyeval compiles under the
NilPy auto-use path — that was the first, now-fixed, blocker).

With those, a NilPy program:
```python
class VM:
    def __init__(self) -> None: self.data = []
    def push(self, v) -> None: self.data.append(v)
    def pop(self): return self.data.pop()
def main() -> None:
    vm = VM(); env = {"vm": vm}
    vm.push(10); vm.push(32)
    exec("b = pop(); a = pop(); push(b); push(a)", env, {})
    print(vm.pop()); print(vm.pop())
main()
```
compiles and prints `10\n32` — a correct SWAP, executed by pyeval against a real
NilPy VM through the reflection trampoline. **This is the payoff working.**

## The blocker

`make test-nilpy` then fails: `test/test_nilpy_str_param.npy` compiles fine but
**segfaults at runtime** on its third face (the `tok` str-scanning loop —
`while i <= n: c = line[i] …`). It prints `2`, `b`, then SIGSEGVs. The test
passes with the unmodified compiler. Only the `ParseUsesUnit('pyeval')` matters
(str_param does not use exec()), so merely PULLING pyeval into a NilPy program
breaks unrelated str indexing.

## Hypothesis

pyeval references GetMethInfoByName / GetInstanceRTTI (typinfo), which may force
method-RTTI emission for more/other classes, shifting the RTTI method-table
stride or a variant-tag layout that NilPy str indexing depends on (cf.
`project_rtti_method_table_multi_consumer_stride_landmine`). Or a global/symbol
interaction from the extra unit. Needs a bisect: does pulling a MINIMAL unit that
merely `uses typinfo` + calls one reflection fn reproduce it? (typinfo-only
auto-use does NOT break it — verified — so it is pyeval-specific, likely its
reflection *calls*, not typinfo's mere presence.)

## Options (Track U decision if root-cause is costly)

1. Root-cause + fix the RTTI/layout interaction so pyeval can be auto-used
   globally (cleanest; exec works everywhere).
2. Pull pyeval only for programs that actually call exec() (conditional
   ParseUsesUnit) — smaller blast radius, but exec-using programs still need the
   interaction fixed.
3. Keep exec() bound to the pylib `pyexec` stub as a thin dispatcher that somehow
   reaches pyeval without the circular uses (pylib can't `uses pyeval`).

Recommendation: option 1 (debug the segfault) — the e2e success shows the runtime
path is sound; the fault is a compile-time emission side-effect.
