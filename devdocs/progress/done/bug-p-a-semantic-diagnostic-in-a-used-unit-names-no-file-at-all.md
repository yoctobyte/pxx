---
slug: bug-p-a-semantic-diagnostic-in-a-used-unit-names-no-file-at-all
track: P
type: bug
prio: 50
status: done
owner: frankH
created: 2026-09-11
found-by: frankH
tags: [diagnostics, uses, corpus, fpc-umbrella, srcmap]
blocked-by: []
summary: "FIXED — and THIS TICKET'S OWN CENTRAL CLAIM WAS FALSE, which is the part worth reading. It said the data already existed and the lowering checks need only be handed ASTFile. Probed 2026-09-11: `astfile=0 dbgfiles=0`, with AND without -g, because paslexer.inc's LexMarkDbgLines guard DELIBERATELY keeps a `uses`d unit out of the DWARF file table (the RTL would swamp it) — so ASTFile is 0 for exactly the nodes corpus work is made of, and a fix written to the instruction would have printed nothing and looked implemented. The node was missing a TOKEN INDEX, not a file id: PasSrcOfTok answers from PasSrcRange*, which IS populated for used units and is how the 3119 Error( sites already print `in:` correctly. Added ASTTok to the arena (stamped at alloc, never zeroed, carried by CloneAST), WriteDiagSourceFileOfTok, and ErrorAtTok/ErrorAtRecoverTok; 11 lowering sites converted. `near:` stays suppressed on purpose. 3 rows wired, one of them the main-file control that a fix printing `in:` unconditionally would fail. The second-class row was first written on record ordering, which the PRE-FIX binary already answered — caught by running the control, and repointed at a class measured to lack it."
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

## The fixture hazard frankS flagged — the advice holds, the mechanism is `1`, not `0`

frankS (2026-09-11) warned that `ASTFile = 0` is *"both a valid id and the
absence of one, so a row asserting 'prints the right file' for a node whose
ASTFile is 0 cannot fail — pick a fixture whose unit is not the first one
stamped."* **Measured before relaying it, and the id is not 0:**

- `dbg_filetable.inc:43,45` mint with `DbgFileId := i + 2`, so a real file id
  starts at **2**. Zero is never handed out.
- `DbgFileOfTok` (`:326-337`) returns **1** as its default — for `not DebugInfo`
  AND for a token in no marked range. That is the value that means two things.
- `ast_arena.inc:118-120` then collapses it: `if (ASTFile[n] <= 1) and (TokPos >
  DbgMainTokEnd) then ASTFile[n] := 0`, so **both** sentinels become 0 for any
  token past the main file.

So the ambiguity is real and it is upstream of where the note put it: **1 is the
overloaded value, 0 is the unambiguous "absent" it gets flattened into.**

**The advice survives, for a sharper reason than the one given.** A fixture whose
used unit was never MARKED produces `ASTFile = 0` by the ordinary path — with no
bug present. So a row asserting "the diagnostic names no file" cannot separate
*the diagnostic lost the file* from *the unit was never in a marked range*, and
it would pass on a fixed compiler. **Establish that the unit is marked
(`ASTFile >= 2`) first, or the fixture measures the marking and not the
diagnostic.** That is this file's own six-class matrix applied to its test rather
than to the compiler.

Note also which mechanism this touches: the `in:` line comes from
`WriteDiagSourceFile` → `PasSrcOfTok(t)` (`lexer.inc:186`), a TOKEN-INDEX path.
ASTFile is the DWARF neighbour. They fail differently, so a fixture built to
probe one says nothing about the other — worth keeping straight, because "line
and file travel together" (`ir.inc:9629`) is a statement about the DWARF half.

## RESOLVED — and this ticket's own central claim was false

**"THE FIX IS SMALLER THAN IT LOOKS AND THE DATA ALREADY EXISTS ... every AST
node already records `ASTFile[node]` ... Hand the lowering checks the id."** It
does not exist. Probed at the assignment check on 2026-09-11 by printing the
value the node actually carries:

```
pascal26:10: error: PROBE astfile=0 dbgfiles=0 :: incompatible types: ...
```

**`astfile=0 dbgfiles=0`, with AND without `-g`** — `-g` verified honoured
independently (the binary carries a `.debug_line` section). The cause is in
`paslexer.inc:4070-4079`, in its own comment:

> The DWARF line table is a different question ... only under -g, and only for a
> source that was **opted in**. A `uses`d unit is **deliberately absent from it
> (the RTL would swamp the table)**.

So `ASTFile` is 0 for **exactly** the nodes corpus work consists of, and the
exclusion is load-bearing — `tools/dwarf_smoke.sh` T5 counts 6 rows with the
guard against 3663 without. A fix written to this ticket's instruction would
have printed nothing and looked implemented. **This is the ticket's own hazard
rule firing on the ticket**: a plausible mechanism, stated confidently, that
nobody had run.

### What actually carries the answer

`PasSrcOfTok` → `PasSrcRange*`, which **is** populated for used units — that is
how the 3119 `Error(` sites already print a correct `in:` line, and it is why 5
of the 6 classes in the table above were fine all along. The node was missing a
**token index**, not a file id.

- `ASTTok` added to the arena beside `ASTLine`/`ASTFile`, stamped with `TokPos`
  at allocation and **never zeroed** — a token index has no second meaning to
  collide with, which is the whole reason for a separate slot rather than a
  second reader of `ASTFile`. frankS's `ASTFile` collision warning is therefore
  moot for this fix by construction, not by care.
- `WriteDiagSourceFileOfTok(tok)` prints `in:` from a token rather than the
  lexer's EOF position. `near:` stays suppressed and that is not an oversight:
  it is a window around the LEXER's cursor, and moving it to an arbitrary token
  would print a window the parse never stood in.
- `ErrorAtTok` / `ErrorAtRecoverTok`, and **11 lowering sites** converted (9 in
  `ir.inc`, 2 in `ast_arena.inc`). `ir.inc:676` is left alone on purpose — it
  reports against `IRLine[i]`, an IR instruction, which has no token.

### The second-class row was a guard that cannot fail, and the control caught it

The first version of the test asserted record ordering as its second class.
Run against the **pre-fix** binary, record ordering **already printed `in:`** —
so would an undefined `goto` label. Both rows would have been green on arrival
for a bug they never exercised. Five candidates were measured against the
pre-fix binary and the element-count form of `Initialize/Finalize` is the one
that genuinely lacked the line; the fixture is now that.

### Measured

| row | pre-fix | post-fix |
| --- | --- | --- |
| assignment check in a used unit | no `in:` | `in: test/pascal_units/unit_a_semantic_error_in_a_unit.pas` |
| `Initialize/Finalize` element count in a used unit | no `in:` | names its unit |
| the same diagnostic in the MAIN file | no `in:` | **still no `in:`** |

The third row is the pair's other half: without it, a fix printing `in:`
unconditionally would pass the first two while telling every reader the name of
the file they just typed. No row pins a line number — the assertion is a PATH,
so it does not go stale as a fixture grows.

The two pre-existing rows that pin the LINE are unregressed; they use `head -1`
and never saw the second line either way.

## Log
- 2026-09-11 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit d3d5098a5.
