---
track: A
prio: 60
type: bug
blocked-by: []
status: done
owner: frank-optimize
found: 2026-08-30
found-by: frank-optimize, while profiling for feature-opt-emitasmx64-reparses-fixed-strings
summary: "`-g` compiles compiler.pas fine at the default -O, but `-g -O2` and `-g -O3` both die with `error: DWARF buffer overflow (-g)` in builtinheap.pas. So the compiler cannot be built with debug info at any optimisation level above the default, which blocks profiling an optimised compiler (the debugging playbook's own workflow) and the `-g -O2` + gdb row in that playbook."
---

> **Re-priced 50 -> 60 by the coordinator, 2026-08-30.** Not because the crash is
> worse than filed, but because of what it blocks. Two things stand behind it:
>
> 1. **The debugging playbook's `-g -O2` + gdb row** (`devdocs/dev/debugging-playbook.md:199`),
>    which is the tree's recommended instrument for exactly the ownership bugs that
>    show up at `-O2` — the row now names a build that does not complete.
> 2. **The optimization campaign's ability to measure itself.** frank-optimize could
>    not re-take `feature-opt-emitasmx64-reparses-fixed-strings`'s profile at that
>    ticket's own stated configuration because of this bug, and that ticket's headline
>    12.4% then turned out to be ~1.5% under interleaved A/B. A campaign that cannot
>    profile at the configuration it optimises for will keep producing figures nobody
>    can reproduce.
>
> The ticket's own framing says it best and is the reason this is not a p50 nuisance:
> **a filed measurement nobody can reproduce is indistinguishable from a correct one.**

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

## 2026-08-30 (frank-optimize) — FIXED. It was Q1, and the margin was 1.5%, not a shortfall.

`-g`, `-g -O2` and `-g -O3` all build `compiler.pas` now, 3430 subprograms each.
Self-host fixedpoint converged, `f5ef1bd15f68`. `gate.sh quick` GREEN.

### The measurement, which changes the story this ticket told

I filed this expecting `-O2` to inflate DWARF substantially. It does not. Total
`.debug_*` bytes emitted for `compiler/compiler.pas`:

| build | total `.debug_*` | vs the old 1 MiB cap |
| --- | ---: | ---: |
| `-g` (default) | 1,033,241 | **98.5%** |
| `-g -O2` | 1,050,915 | 100.2% — over by 2,339 B |
| `-g -O3` | 1,051,511 | 100.3% — over by 2,935 B |

Per section, `-O2` against default:

```
.debug_line    559,674 -> 577,347   (+17,673, +3.2%)
.debug_info    363,649 -> 363,650   (+1)
.debug_abbrev      134 ->     134   (identical)
.debug_frame   109,784 -> 109,784   (identical)
```

**So the working configuration was sitting at 98.5% of the cap with about 15 KB
of headroom, and `-O2` added 17.7 KB of line rows.** That is the whole bug.

This retires Q2 of the ticket ("does `-O2` inflate DWARF per procedure, making
the cap a symptom?") with a flat no — `.debug_info` moved by ONE byte and
`.debug_frame` not at all, so inlining is not producing extra DIEs; only the line
table grows, and only by 3.2%. It is Q1, a fixed cap, exactly as the cheap case
predicted.

It also means the framing in the body above — "`-g -O2` is broken" — was too
narrow. **Nothing about `-O2` was special except that it got there first.** At
98.5%, the default `-g` build was ~15 KB from the same failure: one more unit,
a few hundred more line rows, any ordinary growth of the compiler would have
broken plain `-g` too, with the identical unhelpful message. The bug was latent
in every configuration and had been for some time.

### The fix

`DbgBuf` becomes a growable dynamic array with `GrowDbg`, modelled directly on
`Code`/`GrowCode` already in this tree rather than inventing a second buffer
idiom (`normalise-dont-special-case`): same doubling, same 64 KiB first
allocation, same "the `MAX_` constant is a CEILING, not an allocation" split.
`MAX_DWARF` goes 1 MiB → 32 MiB and is now only the refusal threshold; it
allocates nothing.

Two lines, two files: `compiler/defs.inc` (declaration + constant),
`compiler/elfwriter.inc` (`GrowDbg`, and `DbgPutB` testing capacity instead of
the constant).

Checked before changing the type, not assumed: `DbgBuf` is passed to `syswrite`
as a bare identifier at two sites (`syswrite(f,DbgBuf,DbgLen)`) and as
`Blockwrite(f,DbgBuf[0],DbgLen)` at two more. **`Code` is already a dynamic array
and is passed identically in the same file** (`syswrite(f,Code,CodeLen)`,
`Blockwrite(f,Code[0],CodeLen)`), so the conversion follows a shape the ELF
writers already rely on rather than a new one.

### Free side benefit

BSS drops **1,048,568 bytes** (101,930,108 → 100,881,540). Every compile was
carrying a megabyte of debug buffer that only `-g` runs ever touch.

### Verification

- `make compiler/pascal26`: `converged after 1 round(s)`, `f5ef1bd15f68`.
- **The repro, at all three configurations rather than the one filed**: `-g`,
  `-g -O2`, `-g -O3` each exit 0 with 3430 `DW_TAG_subprogram` entries.
- **Non-`-g` output is untouched**: `compiler.pas` compiled without `-g` by the
  pre-change (`19ee024e3d07`) and post-change compilers is byte-identical.
- **The debug info is USABLE, not merely present** — which is the acceptance
  test that matters, since a buffer fix could easily produce well-formed-looking
  truncated DWARF:
  ```
  $ gdb -batch -ex 'info line IRLowerAST' pxx_g_O2
  Line 5831 of "compiler/ir.inc" starts at address 0x7ec665 <IRLowerAST>
                                 and ends at 0x7ed187 <IRLowerAST+2850>.
  ```
  `readelf --debug-dump=decodedline` also decodes the table cleanly. That is
  `devdocs/dev/debugging-playbook.md`'s `-g -O2` + gdb row working end to end.
- `tools/gate.sh quick`: GREEN.

### The message now names its numbers, and the refusal is shown to fire

The old `DWARF buffer overflow (-g)` named no size, no ceiling and no section,
which is why establishing that the cap was missed by **2,339 bytes** rather than
by an order of magnitude took a measurement pass instead of a read. `GrowDbg`'s
refusal now reports both figures.

Demonstrated rather than asserted, by temporarily setting `MAX_DWARF` to 200000
and rebuilding — because a guard nobody has watched fire is the open ticket
`bug-a-the-abi-oracle-invariant-is-enforced-by-a-grep-that-cannot-fire`, and I
made exactly this a condition on another lane's work today:

```
error: DWARF buffer overflow (-g): emitted 200000 bytes of .debug_* content,
ceiling MAX_DWARF is 200000. Debug info scales with program size; raise
MAX_DWARF in defs.inc.
```

Ceiling restored to 33554432 and re-verified afterwards: all three `-g` levels
exit 0 at 3430 subprograms, fixedpoint `c9a998b66475`.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
