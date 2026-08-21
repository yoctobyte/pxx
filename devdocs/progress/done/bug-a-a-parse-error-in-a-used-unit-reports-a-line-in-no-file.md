---
slug: bug-a-a-parse-error-in-a-used-unit-reports-a-line-in-no-file
track: A
prio: 35
type: bug
blocked-by: []
summary: "A parse error inside a `uses`d unit reports a line number that belongs to no file and never names the file. Measured: an error at globtype.pas:800 is reported as line 1103, in a file 843 lines long. The `near:` context is correct, so the token is findable — by grepping, not by navigating."
status: done
owner: claude-A
---

# A parse error in a `uses`d unit reports a line number that exists in no file

## Measured (2026-08-21)

Two independent cases, both found while probing the FPC compiler tree under
`--mimic-fpc-compiler`:

| real location | reported |
| --- | --- |
| `constexp.pas:58` (`operator := (const u:qword):Tconstexprint;`) | `pascal26:360` |
| `globtype.pas:800` (`tmsgstate = (ms_on := 1,`) | `pascal26:1103` |

`globtype.pas` is **843 lines long**, so 1103 is not a line in it — nor in
`cclasses.pas` (3185) at that content, nor in the program that pulled it in
(4 lines). The number identifies nothing.

The `near:` context IS correct in both cases (`const u qword >>> Tconstexprint`
and `type tmsgstate ms_on >>>`), which is the only reason the real sites above
could be pinned down at all — by grepping for the token text.

## Why it costs more than it looks

Neither half of "where" survives: the line is wrong AND the file is never
named. A user compiling a program that `uses` a dozen units gets a number with
no file, and the number does not even bound the search. The `near:` text
rescues it, but grep-for-the-tokens is not error navigation, and it fails
outright when the tokens are common.

This is also a **compat-probing multiplier**: every wall found in a foreign
corpus costs this rediscovery step before it can be filed, which is exactly
when precise locations matter most.

## Where to look

The likely shape is a line counter that is cumulative across the concatenated
unit sources rather than reset per file (1103 and 360 both look like offsets
into a longer stream), and an error path that carries a line but not the file
identity. `dbg_filetable.inc` already maps positions to files for DWARF, so the
mapping the diagnostic wants may already exist.

## Gate

An error inside a `uses`d unit names the unit's file and a line that resolves
inside it. A test with a program using a unit that has a deliberate syntax
error at a known line, asserting file and line. Self-host byte-identical.

---

## Resolution (2026-08-21)

### The ticket's guess was wrong, and usefully so

The ticket guessed *"a line counter that is cumulative across the concatenated
unit sources rather than reset per file"*. It is not about units at all. The same
defect reproduces in a **single main file with one `{$I}`**, no unit in sight:

```
program p2;          { real error on line 6 }
{$I pad.inc}         { 100 lines }
...
  if then;
```
```
without -g:   pascal26:106: error: expected expression
with -g:      pascal26:6:   error: expected expression
```

`-g` was quietly correct the whole time. That is the entire finding.

`ExpandIncludes` splices every include into one buffer, so line numbers index
the spliced text unless something restores them. Something does: gcc-shaped
`# <line> "<path>"` markers, emitted at each splice boundary and consumed by the
lexer — built for DWARF, and **gated on `DebugInfo`**. Diagnostics were getting
correct line numbers as a side effect of a debug feature, and were wrong for
every other build. The 303-line discrepancy in the original measurement is
exactly `fpcdefs.inc`'s length, which `globtype.pas` includes at its line 23.

The C side has always emitted its markers unconditionally (`cpreproc.inc`), so
this is the Pascal side catching up to a decision its sibling already made.

### What changed

| | |
| --- | --- |
| `elfwriter.inc` | `wantMarkers := Length(selfPath) > 0` — no longer `DebugInfo and ...`. Plus a leading `# 1 "<self>"` so a file is named from its first token, not only from its first include. |
| `lexer.inc` | `PasAtLineMarker` no longer refuses to see a marker without `-g`. |
| `pasparser_proc.inc` | a `uses`d unit passes its own path instead of `''`. |
| `dbg_filetable.inc` | `PasMarkTokFile` / `PasSrcOfTok` — a token→path table that is NOT gated on `-g`, `CMarkTokModule`'s twin. |
| `lexer.inc` | `Error` prints `  in: <path>` when the token is not from the main source. |

**The DWARF line table keeps its old contents.** Suppressing a unit's markers
used to be how it was kept out of that table (the RTL would swamp it); that job
now belongs to `LexMarkDbgLines`, which `LexAppend` clears around a unit. Two
questions that had been sharing one switch — *"is this file in the debug line
table"* and *"can we say which file this line is in"* — now have one switch each.

### `in: <path>` is a separate line on purpose

The obvious format is gcc's `path:line: error:`. It is not available:
`apps/ide/garin/builder.pas` parses compiler output by taking *"a number between
the first two colons"*, so folding the path into the prefix would make every
diagnostic in an include **invisible to the IDE** — trading one broken half of
"where" for the other. An extra context line is additive, sits in the same shape
as the `near:` window under it, and anything that does not understand it ignores
it. A follow-up ticket covers teaching the IDE to read it.

Silent for the main source: the user just typed that filename.

### Attribution cannot leak across frontends

`PasSrcRange*` entries have a start and no end, so a C or NilPy token appended
*after* an ambiently pulled Pascal unit would have inherited that unit's path and
the diagnostic would have blamed `builtinheap.pas` for a line of C. `CLexAppend`
and `PyLexAppend` now plant an empty mark at their start — unknown = say nothing.
Verified: a broken `.c` and a broken `.npy` both report with no `in:` line.

### Measured

| case | before | after |
| --- | --- | --- |
| error after a 100-line `{$I}` in the main file | `pascal26:110` | `pascal26:10` |
| error inside the `.inc` | `pascal26:66`, no file | `pascal26:63` + `in: …/badinc.inc` |
| error in a `uses`d unit that includes a file (the ticket's shape) | `pascal26:113` in a 15-line file, no file named | `pascal26:13` + `in: …/badunit.pas` |
| **`constexp.pas:58`** (the ticket's own case, FPC tree) | `pascal26:360` | `pascal26:58` + `in: …/constexp.pas` |
| **`globtype.pas:800`** (ditto) | `pascal26:1103` in an 843-line file | `pascal26:801` + `in: …/globtype.pas` |

The `801` is right: 800 is `tmsgstate = (`, and the token the parser actually
trips on is `ms_on := 1,` on 801.

The "before" column is the **pinned** binary run against the committed tests, so
the three new Makefile rows fail on a pre-fix compiler. Exact line numbers are
asserted rather than a grep for `error:`, because a number that is merely *close*
is the whole bug.

### Emitted code is unchanged

The self-host fixedpoint converged in 1 round, but that only proves the compiler
agrees with itself. The stronger check, since this touches the lexer for every
Pascal program: build a compiler from HEAD (pre-change) and one from the working
tree, **both seeded by `pinned`**, and have each compile the same sources.

- `test/hello.pas`, `test_dynarray_copy_nested.pas`, `test_exceptions.pas` — byte-identical.
- `compiler/compiler.pas` — the include-heaviest program in the tree, ~8.8 MB of
  code — **byte-identical**.
- `-g`: `readelf --debug-dump=decodedline` identical (files and lines both);
  only addresses move, and they move because of unrelated commits between
  `pinned` and HEAD.

### Gate

`make compiler/pascal26` (byte-identical fixedpoint) + the three new rows + C and
NilPy diagnostics checked for leakage + `gate.sh quick` GREEN.

## Log
- 2026-08-21 — resolved, commit 09aaae653.
