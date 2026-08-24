---
slug: bug-a-basic-prints-a-string-variable-as-its-character-code
title: "BASIC: `DIM m = \"x\"` then `PRINT m` prints 120, not x"
track: A
prio: 40
type: bug
blocked-by: []
status: backlog_new
owner: ""
created: 2026-08-24
summary: "A string-valued BASIC variable prints as a NUMBER. `DIM m = \"x\" : PRINT m` prints 120 -- the character code -- and a multi-character literal prints some other number. `PRINT \"x\"` (the literal directly) is correct, so the loss is in the variable, not the write. Present on pinned. Silent wrong output, no diagnostic."
---

# Symptom

```
$ cat > m.bas <<'X'
DIM m = "x"
PRINT m
X
$ pascal26 m.bas m && ./m
120
```

`120` is `Ord('x')`. `PRINT "x"` written directly prints `x`, so the write path
is fine and the variable is where the string-ness is lost.

Reproduced on `stable_linux_amd64/default/pinned` as well as HEAD — this is not
new.

# Where to start

`bparser.inc`'s `DIM`/`LET` arm decides the variable's type from the RHS:

```pascal
    vtype := tyInteger;
    if ASTTk[rhsNode] = Ord(tyString) then
      vtype := tyString;
    symIdx := AllocVar(vname, vtype);
```

So the type is only preserved when the RHS node is tagged `tyString` exactly.
Confirm what a BASIC string literal is actually tagged (`BMkRuntimeError` builds
one with `ASTTk[lit] := Ord(tyString)`, but the PRINT/DIM path may differ), and
whether the `AN_IDENT` node built for `m` on the read side carries the symbol's
kind. `PXXDBG=a.ast:` and `a.ir:` answer both in one run — **measure it, do not
reason about it**: a `tyString` variable that prints its first byte as a number
is equally consistent with a mis-tagged declaration and with a mis-tagged
reference.

# Scope note

BASIC has no `A$` string variables at all (`10 A$ = "hi"` is
`Undefined variable or procedure: A`), so the whole string-variable surface here
is `DIM`/`LET` of a literal. That makes this small, and it is prio 40 rather
than lower because it is a **silent wrong answer** in the most obvious two-line
program a BASIC user writes.

# Found by

Measuring the BASIC driver's runtime needs while closing
[[bug-a-a-unit-free-basic-program-calls-a-helper-it-never-emits]].
