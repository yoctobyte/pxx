---
slug: bug-a-basic-prints-a-string-variable-as-its-character-code
title: "BASIC: `DIM m = \"x\"` then `PRINT m` prints 120, not x"
track: A
prio: 40
type: bug
blocked-by: []
status: done
owner: claude-A
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

## Resolved 2026-08-24 (claude-A)

**Sharper than the ticket says: only a ONE-CHARACTER literal.** Measured:

| program | before | after |
| --- | --- | --- |
| `DIM m = "x"` / `PRINT m` | **120** | `x` |
| `DIM m = "hello"` / `PRINT m` | `hello` | `hello` |
| `PRINT "x"` (literal, no variable) | `x` | `x` |
| `m = "x"` (LET-less form) / `PRINT m` | **121** for `"y"` | `y` |

That pattern names the cause exactly. The RHS comes from the **shared Pascal
expression parser**, which tags `'x'` as `tyChar` and `'xy'` as `tyString`; both
copies of BASIC's variable-typing rule tested `ASTTk[rhsNode] = Ord(tyString)`
alone, so a one-character initialiser fell through to `tyInteger` and the write
printed a number.

Same root as the PChar `+` divergence recorded in
[[refactor-centralize-managed-string-pchar-conversion]]: *"With a ONE-char
literal — tyChar, an ordinal — the `ordinal + pointer` arm claimed the
expression first."* A one-character string literal has now produced a silent
wrong answer through two unrelated code paths.

### Fix

`BVarTypeForInit(rhsNode)` in `bparser.inc`, replacing **both** copies of the
rule. BASIC has no character type, no `A$` sigil and no type declarations — a
variable is whatever its first assignment says it is, and there are exactly two
things it can hold. So a one-char literal is a string *here*, and the helper is
where that is said once.

The two copies were the DIM/VAR arm and the LET-less `I = <expr>` arm; the ticket
was written against the first, and fixing only that one would have left the
second — `devdocs/dev/normalise-dont-special-case.md`'s "grep for the sibling
before closing the ticket", which is why the test covers both spellings.

### A third sibling this UNCOVERED, recorded not fixed

`IF a = "x"` used to pass by accident — an integer compare of 120 against 120.
Now that these are strings it is a real `PXXStrEq` call, and on aarch64/arm32
that is `compiler error: PXXStrEq not found`, because the body ships with
builtinheap and a unit-free `.bas` never pulls it. x86-64 and i386 have an inline
path and compile it. Same root as
[[bug-a-basic-string-concat-in-a-unit-free-program-is-a-compiler-error]] and
recorded there; deliberately kept OUT of this test so the two are not coupled.

### Test

`test/test_basic_one_char_string_var.bas` — both spellings, a multi-char control,
and an integer control. Wired into `test-core` natively and on i386 / aarch64 /
arm32. `pinned` prints `120` and `121` for the two string rows.

### Gate

`make compiler/pascal26` fixedpoint converged in one round; the four existing
`.bas` tests byte-identical; the new test on four targets; `tools/gate.sh quick`
GREEN.

## Log
- 2026-08-24 — resolved, commit PENDING-COMMIT.
