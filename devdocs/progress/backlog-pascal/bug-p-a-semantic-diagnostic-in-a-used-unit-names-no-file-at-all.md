---
slug: bug-p-a-semantic-diagnostic-in-a-used-unit-names-no-file-at-all
track: P
type: bug
prio: 50
status: backlog
owner: ""
created: 2026-09-11
found-by: frankH
tags: [diagnostics, uses, corpus, fpc-umbrella, srcmap]
blocked-by: []
summary: "The 71 `ErrorAt`/`ErrorAtRecover` call sites — the IR-lowering checks — print a line and NO `in:` file, so a diagnostic from inside a `uses`d unit gives a bare `pascal26:18:` and the reader supplies the file they invoked. THE FIX IS SMALLER THAN IT LOOKS AND THE DATA ALREADY EXISTS: `ErrorAt` takes a LINE and `WriteDiagSourceFile` derives the path from the CURRENT TOKEN (EOF by then), so suppressing it is correct given what `ErrorAt` is handed — but every AST node already records `ASTFile[node]`, a DWARF file id stamped at allocation one line below `ASTLine[node]`, and `DbgFileName[id-2]` is its path. Hand the lowering checks the id. NARROWED 2026-09-11 (frankS's counter-observation): this is NOT 'semantic diagnostics' as a class — 5 of 6 error classes measured inside a used unit DO name their file, `Error(` has 3119 call sites against `ErrorAt`'s 71, and the first version of this ticket asserted the wide claim from ONE fixture."
---

# The population, measured — and the first version of this ticket was wrong about it

Filed saying "a semantic diagnostic in a used unit names no file". frankS read
real corpus diagnostics and observed the opposite: `unknown type: TExecuteFlags`
came with `in: .../cfileutl.pas`. They flagged it as one seat's observation
rather than a retraction. It is a retraction — the wide claim came from ONE
fixture and my own `feature-b-sysutils-...` ticket, filed 2026-09-09, already
showed `in: /usr/share/fpcsrc/3.2.2/compiler/cfileutl.pas` on its own first
line. The counterexample was inside my own evidence.

Six error classes, each raised inside the same `uses`d unit at the same line,
measured at `016ab69d0ca0`:

| error | `in:` | `near:` |
| --- | --- | --- |
| `expected expression` (parse) | yes | yes |
| `SizeOf: unknown type or variable` | yes | yes |
| `undefined variable (X)` | yes | yes |
| `no overload of Go matches these arguments` | yes | yes |
| `incompatible types: cannot assign Pointer to record` | **no** | **no** |
| `i(3)` where `i: Integer` | (compiles — not a diagnostic) | |

So the class is not semantic-versus-parse. It is **which error entry point was
used**: `Error(`/`ErrorRecover(` pass `withContext=True` and get both lines;
`ErrorAt(`/`ErrorAtRecover(` pass `False` and get neither. 3119 `Error(` call
sites in `compiler/*.inc` against **71** `ErrorAt(` — 39 of those in
`paslexer.inc`, 9 in `pylexer.inc`, 5 in `ir.inc`. The IR ones are the lowering
checks and are the ones a corpus reader meets.

# Why the suppression is correct today, and what makes it fixable

`lexer.inc`'s `WriteDiagSourceFile` derives the path from a TOKEN INDEX:

```pascal
if Lexing then t := TokCount
else if TokPos > 0 then t := TokPos - 1
else t := 0;
path := PasSrcOfTok(t);
```

After the parse that index is at EOF, i.e. inside the builtin units appended to
every program. Printing it would name a file the author never wrote — the exact
failure `ErrorNoPos`'s docstring records, where two agents read
`in: ./compiler/builtin/builtinheap.pas` as "the frontend cannot parse this".
So `withContext=False` is right, given a line and nothing else.

**But the node is not carrying only a line.** `ast_arena.inc`, at allocation:

```pascal
ASTLine[ASTNodeCount] := CurTok.Line;
ASTFile[ASTNodeCount] := DbgFileOfTok(TokPos);
```

and `DbgFileName[id - 2]` is that id's path (`dbg_filetable.inc:43`). The file
travels with the node already — `ir.inc:9629` reads it for DWARF, with the
comment *"line and file travel together"*. The lowering checks read `ASTLine`
and throw `ASTFile` away.

So the shape is: give `ErrorAt`/`ErrorAtRecover` the file id beside the line and
print `in:` from the id rather than from the token position. `near:` stays
suppressed — that one genuinely needs a token.

**The one trap, and it is in the same three lines:**

```pascal
if (ASTFile[ASTNodeCount] <= 1) and (TokPos > DbgMainTokEnd) then
  ASTFile[ASTNodeCount] := 0;
```

`ASTFile = 0` is load-bearing for DWARF — it is what keeps the RTL, pylib and
unit bodies out of the line table. It is not "file zero". A fix must print
nothing for 0, never a lookup of it, and `ASTLine` had this exact collision
before: one field answering two questions is what
`bug-a-a-semantic-diagnostic-in-a-used-unit-has-no-location-at-all` (done) was
about, and that ticket's own comment says a zero *"does not degrade a diagnostic,
it erases its entire locating apparatus at once."*

# The residual it is

That done ticket fixed the LINE for this class — it printed `pascal26:0:` before,
and `test/pascal_units/unit_a_semantic_error_in_a_unit.pas` pins the fix. The
FILE half was never picked up and nothing owns it. Two further closed neighbours
are about the `in:` line naming the WRONG file
(`bug-a-…-names-the-wrong-source-file`, `bug-p-…-names-the-wrong-source-file`),
and `bug-p-the-corpus-instance-of-the-wrong-file-diagnostic-survives-the-fix` was
REJECTED on a false premise in the same area. Read all three first;
`PXXDBG=a.srcmap:*` is what settled the rejection.

# Repro

```
./compiler/pascal26 -Futest/pascal_units \
  test/pascal_units/driver_a_semantic_error_in_a_unit.pas /tmp/y
pascal26:18: error: incompatible types: cannot assign Pointer to record
```

Compare `-Futest/incdiag test/test_incdiag_unit_fail.pas`, which names its file.

# Interim, for anyone consuming diagnostics

A missing `in:` means **the compiler did not say**, not "the unit under test".
Defaulting it to the invoked file is the silent mis-attribution that got two
unrelated NilPy modules ranked p80 as one shared dependency, both on "line 31" of
the same imported file. A bare `pascal26:<n>:` with no `near:` window is the
tell — and per the table above it is now known to be a NARROW class, so a corpus
instrument meets it rarely rather than everywhere. That is why this dropped from
p60 to p50.
