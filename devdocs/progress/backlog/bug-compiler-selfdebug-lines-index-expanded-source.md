---
track: A
prio: 45
type: bug
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
