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

## Bisect results (2026-07-21) — narrowed to bulk emitted code, NOT the obvious suspects

Rebuilt the compiler with pyeval auto-used, swapping pyeval's body:
- **typinfo-only** auto-use (no pyeval): str_param PASSES → not typinfo.
- **minimal pyeval** (unit present, no-op `EvalPyStmts`, same `uses`): PASSES →
  NOT unit presence, NOT the module globals (Pos/Cur/Src/…), NOT a name clash.
- **pyeval that only calls the reflection fns** (GetInstanceRTTI /
  GetMethInfoByName / GetFieldPtr): PASSES → NOT the RTTI-reflection calls / RTTI
  emission. (So the original method-table-stride hypothesis is WRONG.)
- **full real pyeval**: str_param SEGFAULTS.

Key fact: `str_param.npy` never calls exec(), so pyeval's runtime code never
executes in it. The fault is therefore a **compile-time emission side-effect** of
pyeval's ~60 procs + hundreds of string-literal constants being added to the
program — it changes the code EMITTED for str_param's own str-indexing loop.

Further bisect ruled out MORE suspects (each = one compiler rebuild + str_param run):
- minimal pyeval + **300 string-literal constants**: PASSES → not the string pool.
- minimal pyeval + the **typed proc-pointer casts** (TVFn0/TVFn2/TVPr1/TSFn0 with
  `const Variant` params, cast from mi^.Code and called): PASSES → not the casts.
- full real pyeval **minus the PreprocessFStrings call**: still SEGFAULTS → not
  PreprocessFStrings.

Decisive observation: str_param's binary GROWS from ~188KB (minimal pyeval) to
~481KB (full pyeval) — all of pyeval is linked in (auto-used → fully emitted).
The crash is on face 3, the `tok` str-scanning loop (`while i <= n: c = line[i]`).
So it is **a layout-sensitive miscompile in str_param's OWN str-indexing code (or
a shared runtime helper), EXPOSED by the ~290KB of extra emitted code** — not any
single pyeval construct. Likely a relative-offset / alignment / fixed-buffer bug
that only manifests past a certain code size or at a certain layout.

Next step (focused session): binary-search by trimming pyeval's function set in
halves until str_param passes, to find the size threshold; then diff the emitted
str_param `tok` code between the passing and failing builds (same source, only
the surrounding code volume differs) to see which instruction miscompiles. This
is a latent Track A codegen bug that pyeval merely surfaces — worth fixing on its
own, independent of pyeval.

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

## Log
- 2026-07-21 — resolved, commit 08fda0c2.
