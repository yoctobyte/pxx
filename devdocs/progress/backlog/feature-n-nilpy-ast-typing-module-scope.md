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

## Shape

Likely the same trial-parse trick applied to the top-level statement loop only,
skipping `def`/`class` spans the way the scanner already does. Check whether
`ParsePyProgram` can be restructured so module statements form a block the way
a body does.

Retire `PyInferExprType`, `PyTypeFromTokenIndex`'s inference role and
`PyStrMethodInfo`'s inference half when this lands — they exist only for this
caller now.

## Gate

`test-nilpy` green + `--tier quick` + self-host byte-identical + `make
fpc-check` (see [[feedback_fpc_bootstrap_advisory_invisible_to_local_gate]]).
