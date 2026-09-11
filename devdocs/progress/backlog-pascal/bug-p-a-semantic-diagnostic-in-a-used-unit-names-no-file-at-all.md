---
slug: bug-p-a-semantic-diagnostic-in-a-used-unit-names-no-file-at-all
track: P
type: bug
prio: 60
status: backlog
owner: ""
created: 2026-09-11
found-by: frankH
tags: [diagnostics, uses, corpus, fpc-umbrella, srcmap]
blocked-by: []
summary: "A semantic diagnostic raised while lowering a node from a `uses`d unit prints a correct LINE and NO FILE and NO `near:` window — `pascal26:18: error: incompatible types` and nothing else. A PARSE error in the same position prints `in: test/incdiag/badunit.pas` plus a `near:` window, so the attribution channel exists and this class does not reach it. Measured contrast at 15f293d4a, both fixtures live in the tree. This is the unowned residual of `bug-a-a-semantic-diagnostic-in-a-used-unit-has-no-location-at-all` (done), which fixed the LINE — it used to print `pascal26:0:` — and left the file. It is load-bearing for the FPC umbrella's all-failures instrument: separating a failure raised INSIDE the unit under test from one raised in a unit it pulls in is the instrument's whole point, and for semantic errors the output does not say which."
---

# Measured 2026-09-11 at `15f293d4a`

Two diagnostics, both raised inside a unit reached by `uses`, both with the
correct line number for that unit:

```
$ ./compiler/pascal26 -Futest/incdiag test/test_incdiag_unit_fail.pas /tmp/x
pascal26:13: error: expected expression
  in: test/incdiag/badunit.pas
  near: implementation procedure Foo ; begin if >>> then ; end

$ ./compiler/pascal26 -Futest/pascal_units \
    test/pascal_units/driver_a_semantic_error_in_a_unit.pas /tmp/y
pascal26:18: error: incompatible types: cannot assign Pointer to record
```

The first is a PARSE error and names its file. The second is a SEMANTIC one and
names nothing. Same door, same kind of coordinate, one of them attributed.

The mechanism is the one `ErrorNoPos`'s own docstring describes from the other
direction: `ErrorPrint` reads the `in:` path and the `near:` window off the
LEXER's position, which is correct while the lexer is still standing in the file
and is not once lowering has begun. So the parse-time class gets attribution for
free and the semantic class cannot, rather than the two disagreeing by accident.

# Why it is worth fixing rather than working around

**A bare `pascal26:<n>:` makes the reader supply the file they invoked**, and
CLAUDE.md records the cost: two unrelated NilPy modules failing at "line 31"
read as one shared dependency and were ranked at p80 as gating a whole package,
because both rows were the same imported file's line 31. That mis-ranking is
this defect wearing a different frontend.

It also blocks a specific instrument. `umbrella-pxx-compiles-fpc-itself` needs
an all-failures probe that separates a failure raised INSIDE the unit under test
from one raised in a unit it pulls in — that separation is the only way to answer
"how far is `cclasses.pas` from compiling", which four consecutive null rows have
made the umbrella's central question. For semantic errors the compiler's output
does not carry the distinction, so the instrument cannot derive it.

# The residual it is

`bug-a-a-semantic-diagnostic-in-a-used-unit-has-no-location-at-all` (done) fixed
the LINE for exactly this class — it printed `pascal26:0:` before — and
`test/pascal_units/unit_a_semantic_error_in_a_unit.pas` exists to pin it. The
FILE half was never picked up and nothing owns it. Two neighbours are closed and
are about the `in:` line naming the WRONG file
(`bug-a-…-names-the-wrong-source-file`, `bug-p-…-names-the-wrong-source-file`),
so the machinery has been worked on twice without this arm being reached.

**Read those two before starting.** Both found the token→file map subtle — a
start-only range list scanned backwards, which assumes the token index rises
monotonically with source file, and nested unit parsing does not — and
`bug-p-the-corpus-instance-of-the-wrong-file-diagnostic-survives-the-fix` was
REJECTED on a false premise in the same area. `PXXDBG=a.srcmap:*` is the
instrument that settled that one.

# Interim, for anyone consuming diagnostics before this lands

Treat a missing `in:` as **UNKNOWN**, never as "the unit under test". Defaulting
it to the invoked file is the mis-attribution above, and it is silent. A bare
`pascal26:<n>:` with no `near:` window is itself the tell that the coordinate may
belong to another file.
