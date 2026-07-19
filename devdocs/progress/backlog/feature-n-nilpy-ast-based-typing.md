---
track: N
prio: 70
type: feature
---

# NilPy: type locals from the AST, like Rust and Zig already do

Design: `devdocs/dev/type-identity-as-substrate.md` item 2. **Start here** — it
is the smallest of the four, the pattern is already proven in-repo, and it
unblocks the uforth corpus.

## What

`pyparser.inc` has EIGHT token-scanning inference functions
(`PyInferExprType`, `PyTypeFromTokenIndex`, `PyDefReturnType`,
`PyHeaderParamType`, `PyCollectLocals`, `PyCollectModuleLocals`,
`PyRegisterClassShells`, `PyRegisterClassFieldsPrepass`) that work on TOKENS and
never see the AST. Every NilPy feature must therefore be implemented TWICE —
once to parse it, once to infer it — and the two drift. Concrete drift caught
this session: `len(s.split(","))` segfaulted because inference did not know a
str method could return a class, and `"a,b".split(",")` was invisible to
inference because the scan only inspects IDENT tokens.

Rust (`rparser.inc:1036`) and Zig (`zparser.inc:942`) already do it right:
parse the initialiser, read `ASTTk[valNode]`. C needs no inference.

## Why NilPy diverged (do not just delete the pre-scan)

Python declares locals implicitly by assignment, and a local's type can WIDEN
across branches (`x = 1` then `x = "s"` -> variant). So all assignments must be
seen before the frame is laid out. That is a real constraint, not an accident.

## Shape

Keep a pre-pass, move it from TOKENS to the AST: parse the body to AST, walk it
collecting and widening local types, then declare and emit. `PatchProcPrologue`
already patches frame size after the body, so allocate-as-you-go is
structurally possible — check whether the widening pass can be folded into that.

Retire the token scanners as their callers migrate. `PyStrMethodInfo`'s
"one shared table read by both parse and inference" is a band-aid over this and
should disappear with it.

## Gate

`test-nilpy` green + `--tier quick` + self-host byte-identical + FPC bootstrap
clean (see [[feedback_fpc_bootstrap_advisory_invisible_to_local_gate]]).
Every `.npy` test diffed against CPython as the oracle.
