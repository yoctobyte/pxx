---
track: A
prio: 55
type: bug
blocked-by: []
status: backlog
summary: "Two REPORTED wasm32 lowering gaps -- PyBindHostKwArgs (value of type Int64 assigned to a managed string) and PyBoundFnCallvnMaskBody (32-parameter limit) -- are emitted as `unreachable`, and ordinary NilPy code calls them: a default argument, a user-written `__init__` and a generator all trap at runtime while the build exits 0 and prints `ok:`. A plain `def` and a class with no `__init__` are fine, so this is not the whole frontend. NOT the multi-CompileAST double-write bug: the rewrite counter fires on neither, and it is proven working on two Pascal controls."
---

# Two wasm32 gaps make ordinary NilPy trap at runtime

Measured at 6f86e8f48, binary `fcc5ad9a29a6`. Value comparison against four
targets, because a trap is the only thing that shows here.

| NilPy shape | native / i386 / arm32 / aarch64 | wasm32 |
| --- | --- | --- |
| `def f(a): return a + 1` | `2` | `2` — SAME |
| `class C:` with only a method | `5` | `5` — SAME |
| `def f(a, b=7)` | `8`, `3` | **trap, rc=134** |
| `def f(a=1, b=2)` | `3` | **trap, rc=134** |
| `class C:` with a user-written `__init__` | `3` | **trap, rc=134** |
| generator (`yield` in a `while`) | `6` | **`Unhandled exception`, rc=1** |

## The cause, and how the two controls find it

A PASSING and a FAILING NilPy build print the IDENTICAL census line:

    wasm32: 1723 of 1725 bodies lowered; 2 emitted as `unreachable`; 2 distinct gap(s)
        PyBindHostKwArgs — value of type Int64 assigned to a managed string
        PyBoundFnCallvnMaskBody — $proctype has no room for the hidden destination parameter (32-parameter limit)

The gaps are the same either way. What differs is whether the program CALLS one
of those two bodies, and `wasm trap: unreachable instruction executed` is
exactly what an `unreachable` body produces. A default-argument call and a
constructor call go through keyword-argument binding and the bound-call path; a
plain `def f(a)` call does not.

So the two passing rows are load-bearing: they say the wasm32 NilPy backend is
broadly fine and that these two named bodies are the blockers.

## What it is NOT, checked rather than assumed

Not
[[bug-a-wasm32-emits-a-separate-function-per-compileast-call-so-a-proc-built-in-two-calls-loses-a-body]].
The rewrite counter prints for none of the six shapes, and it is proven to work
on the same binary and invocation: it fires on `procedure Fill(out s: string)`
naming `Fill`, and on `test/test_managed_var_param.pas` naming `SetItOut`. These
rows were attributed to that mechanism for a day; that append is retracted there.

**A value comparison can establish THAT a target diverges and never WHY.** Six
rows and two clean controls looked exactly like a mechanism's signature and were
not it.

## Why it is ranked here

The build EXITS 0 AND PRINTS `ok:`. Nothing but running the program and
comparing its value can see this, so "it compiled" and any gap census counting
these sources as reaching the backend both count a program that traps on line
one. NilPy-on-wasm32 is a cell of the languages x platforms goal, and a default
argument or a constructor is not a corner of the language.

The generator row is listed with the others but fails differently
(`Unhandled exception`, rc=1, not a trap) and has NOT been traced to either
named body — it may be a third gap. Do not close it on the other two.
