---
track: A
prio: 50
type: bug
blocked-by: []
status: new
owner: ""
found: 2026-08-30
found-by: frank-optimize, while profiling for feature-opt-emitasmx64-reparses-fixed-strings
summary: "`-g` compiles compiler.pas fine at the default -O, but `-g -O2` and `-g -O3` both die with `error: DWARF buffer overflow (-g)` in builtinheap.pas. So the compiler cannot be built with debug info at any optimisation level above the default, which blocks profiling an optimised compiler (the debugging playbook's own workflow) and the `-g -O2` + gdb row in that playbook."
---

# `-g` with `-O2` or `-O3` overflows the DWARF buffer on `compiler.pas`

## Repro

```
$ ./compiler/pascal26 -g     compiler/compiler.pas /tmp/pxx_g      # exit 0
$ ./compiler/pascal26 -g -O2 compiler/compiler.pas /tmp/pxx_g_O2   # exit 1
$ ./compiler/pascal26 -g -O3 compiler/compiler.pas /tmp/pxx_g_O3   # exit 1

pascal26:2: error: DWARF buffer overflow (-g)
  in: ./compiler/builtin/builtinheap.pas
  near:  ]   end  >>> unit builtinheap
```

Measured at `19ee024e3d07`. The default-`-O` build of the same source with the
same flag succeeds and yields 3,426 usable `DW_TAG_subprogram` entries, so the
DWARF path itself works — it is the interaction with `-O2`/`-O3` that overflows.

## Why it matters beyond the message

Two documented workflows depend on exactly this combination:

1. **`devdocs/dev/debugging-playbook.md`** lists `-g -O2` + gdb as the "step
   through it" row. That row cannot be executed on the compiler today.
2. **Profiling an optimised compiler.** `tools/pxxprof_symbolize.py` needs DWARF
   to name symbols, and the compiler you want to profile is the `-O3` one —
   profiling the default build measures a different program. This is what
   blocked me: `feature-opt-emitasmx64-reparses-fixed-strings` carries a profile
   taken at `-O3` (`AsmTextLine` 3.93%, `AsmText*` ~12.4% total) and I could not
   re-take it at that configuration to check the attribution. Falling back to the
   default `-g` build put **73% of samples outside `.text`**, unattributable.

That is the real cost: a *filed measurement nobody can reproduce* is
indistinguishable from a correct one, and the ticket it justified turned out to
overstate its win by roughly an order of magnitude (see that ticket's resolution
— the measured delta is ~1.5%, not ~12%). A profiler you cannot point at the
optimised build is how that survives.

## Where to look

The error is raised from the DWARF emitter against a fixed-size buffer and
surfaces on `compiler/builtin/builtinheap.pas`, i.e. late in a large build.
Two obvious questions for whoever takes it, in order:

1. Is the buffer simply a fixed cap that `-O2`/`-O3` exceeds because optimised
   code produces more line-table or location rows per procedure? If so, does it
   want growing, or growing dynamically like `GrowCode`?
2. Does `-O2` inflate DWARF **per procedure** (inlining producing more entries),
   in which case the cap is a symptom and the emitter wants to be incremental
   rather than buffered?

Answer 1 before reaching for 2 — a fixed cap that needs to be a growable buffer
is the cheap case and is worth confirming or excluding first.

## Gate

`make compiler/pascal26` (fixedpoint) plus the three repro lines above, all
exiting 0, plus `readelf --debug-dump=info` on the `-O2` output yielding a
non-empty subprogram list. `-g` output is not part of the self-host fixedpoint,
so a fix here cannot move the blessed binary.
