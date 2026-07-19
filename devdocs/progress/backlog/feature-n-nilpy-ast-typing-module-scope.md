---
track: N
prio: 55
type: feature
---

# NilPy: type MODULE locals from the AST too

Remainder of `feature-n-nilpy-ast-based-typing` (resolved 1a4089b4). Def and
method bodies now type their locals by parsing (`PyCollectLocalsAST`);
**module scope still uses the token scanner** `PyCollectModuleLocals` ->
`PyInferExprType`, so the drift this ticket set out to kill still exists at
module level.

## Why it was left

A def body is one parseable block with a known start token, so the trial parse
is a straight `TokPos := bodyStart; PyParseBlock`. Module scope is not: it
interleaves `def`, `class` and statements, and `PyCollectModuleLocals` walks it
with an indent-depth filter to skip anything nested. A trial parse would have
to run the whole program's top level — including registering procs and classes
— and roll all of that back, which is a much bigger blast radius than a body.

## Status: mostly LANDED (226f2507)

`PyCollectModuleLocalsAST` trial-parses the module body — enabled by
`PyRegisterDefShells` (ba546669), which registers top-level def signatures up
front so a module statement may call a def declared further down.
`PyCollectModuleLocals` is gone.

**What remains, and why.** Three narrowings keep the pre-pass off ground it
cannot stand on. Only the second is a real gap:

1. An annotated `name: T = expr` reads the annotation and skips the RHS —
   intended, and the escape hatch for everything else.
2. **A bare assignment whose RHS calls a method on a NAME (`x = c.two(1)`) is
   skipped.** Class MEMBERS are not registered until `PyParseClass` reaches
   the class, so trial-parsing it would fail on a method that is valid a
   moment later. Cost: no WIDENING for that name (the real parse still
   declares it).
3. Only assignments are parsed; nothing else declares a module local.

**To close (2): hoist class member registration the way def signatures now
are.** `PyRegisterClassMembers` already has a `fieldsOnly` flag and is
already run twice (fields pre-pass, then `PyParseClass`). The obstacle is
that the non-fieldsOnly path also appends to the `PyDc*` dataclass-default
tables, so a third run would duplicate them — untangle that first, then give
`PyParseClass` a "members already registered" guard.

`PyInferExprType` survives for ONE caller: the ctor field scan, which has no
parseable block of its own — fields must exist before any body is parsed. See
[[project_nilpy_class_pipeline_ordering]]. Closing that is the same
declaration-phase work as (2).

## Gate

`test-nilpy` green + `--tier quick` + self-host byte-identical + `make
fpc-check` (see [[feedback_fpc_bootstrap_advisory_invisible_to_local_gate]]).
