---
track: A
prio: 45
type: bug
status: done
owner: claude-A@opus5
---

# `make pxx-debug`: line numbers index the INCLUDE-EXPANDED source

```
$ make pxx-debug
$ gdb --args compiler/pascal26-debug prog.py /tmp/out
(gdb) break PyClassCreate          # works
(gdb) bt                           # works, full parse chain
(gdb) info line IRDump
Line 61871 of "compiler/compiler.pas" ...
```

`compiler/compiler.pas` is **1001 lines**. 61871 is a line of the text after
`ExpandIncludes` splices every `.inc` in — so the number is real but useless,
and it names the wrong file (everything reads as `compiler.pas`, never
`ir.inc`).

So compiler self-debugging is **function-level only** today: `break <routine>`,
backtraces, `info args`/`locals` and stepping-by-instruction all work; stepping
by source line and `break ir.inc:1234` do not.

## This is the C bug again, one layer up

Identical shape to `bug-c-dwarf-lines-index-the-preprocessed-text` (fixed
`ee6ef36ac`): a textual include pass inlines other files into one buffer and the
lexer numbers lines in that buffer. The fix there was:

1. the include pass emits gcc-style `# <line> "<path>"` markers, drift-based
   (only when the origin would otherwise be inferred wrongly), `-g` only;
2. the lexer consumes them and stamps the origin line;
3. the multi-file line table (already built, shared) gives each `.inc` its own
   file entry.

Steps 2 and 3 are done and generic — `DbgFileId` / `DbgMarkTokFile` /
`DbgFileOfTok` are frontend-neutral, and `AllocNode` already consults ranges
before the main-file bound. What is missing is step 1 for `ExpandIncludes`
(the Pascal-side include splice, `compiler.pas:718`) plus marker handling in
`lexer.inc`, mirroring `clexer.inc`'s `CLexLineMarker`.

Estimated small — the C version was ~40 lines of emitter plus ~45 of lexer, and
half the design carries over unchanged.

## Why it is worth doing

The compiler is the program we debug most, and it is the one place where a
`.map`-and-print workflow is still the only option. It is also the last place
where the "plausible wrong line" failure survives: 61871 looks like an answer.

## Gate

`make pxx-debug` then `break ir.inc:<line>` resolving, and `bt` naming `.inc`
files. Plus the usual: no change without `-g`, self-host fixedpoint byte
identical.

## Resolution 2026-08-03 (claude-A@opus5)

Step 1 (the missing half) implemented as the ticket describes, mirroring the C
side: `ExpandIncludes` emits gcc-style `# <line> "<path>"` markers at each
splice boundary and `lexer.inc` consumes them.

- **Emitter** (`elfwriter.inc`): `IncEmitLineMarker` writes two markers per
  include — `<inc>` at line 1 on entry, the includer at the directive's line on
  resume. Absolute anchors rather than drift-based, so no error accumulates
  between them; the C side's drift check exists because its preprocessor emits
  per logical line, which this splice does not.
- **Consumer** (`lexer.inc`): `PasAtLineMarker` / `PasLexLineMarker`, run in a
  loop after `SkipSpace` (markers arrive back to back when an include's last
  line is another include). No collision with Pascal's `#nn` char literal: a
  marker has a space after the `#`, and `"` is not a Pascal quote.
- **selfPath param**: `ExpandIncludes(src, baseDir, selfPath)`. Pascal UNITS
  pass `''` and get no markers — a unit is deliberately absent from the line
  table (the RTL would swamp it) and a marker is exactly what would opt it in.
- **Closing the ranges** (`compiler.pas`): after `LexAll`, `DbgMarkTokFile(TokCount, 1)`.
  Without it the last `{$I}`'s .inc stayed the open range and every token of
  every unit appended afterwards — the whole RTL — reported as that .inc.
  Caught by measurement, not by reasoning: it showed up as unit frames naming
  an unrelated `.inc`.

Verified at 4c-forward (self-hosted at HEAD):

```
(gdb) info line IRDump
Line 9554 of "compiler/ir.inc" ...            { was: line 65576 of compiler.pas }
(gdb) break compiler/symtab.inc:100           { resolves }
(gdb) bt
#0 AllocNode (kind=19) at compiler/parser.inc:132
#1 ... ParseBlockAST () at compiler/parser.inc:17425
#4 ... ParseUsesUnitBody (name='builtinheap') at compiler/parser.inc:28544
```

All 54 `.inc` files carry rows (`readelf --debug-dump=decodedline`), and sampled
rows land on real code lines in the file they name.

`tools/gate.sh quick` GREEN including the **FPC seed canary**, which is what
caught the one real mistake here: the `DbgFileId`/`DbgMarkTokFile` forwards sat
*after* `{$include lexer.inc}` (they were added for clexer.inc), so the seed
build failed with "Identifier not found" while every pxx-side check passed.
Moved above the include.

### Residual, filed separately

A backtrace's outermost frame still names the wrong `.inc`, and `pyparser.inc`
routines still report no line info — **not** this bug. The line program emits
`Advance PC by 4294967161`, i.e. **-135** as an unsigned ULEB128, so the address
register carries into bit 32 and 34% of the rows describe addresses that do not
exist. Present identically in a `-g` build from `pinned` against HEAD sources.
Filed as [[bug-a-dwarf-line-program-emits-backward-address-steps]] (prio 50).

## Log
- 2026-08-03 — resolved, commit a273ed6d4.
