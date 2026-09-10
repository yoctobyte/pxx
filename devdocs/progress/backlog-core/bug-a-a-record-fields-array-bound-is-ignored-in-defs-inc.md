---
slug: bug-a-a-record-fields-array-bound-is-ignored-in-defs-inc
track: A
prio: 55
type: bug
status: backlog
owner: ""
created: 2026-09-10
found-by: frankH
tags: [core, record-layout, self-host, limits, sizeof]
blocked-by: []
summary: "TProc.Params in compiler/defs.inc keeps 32 slots whatever its array bound says. Declared `array[0..31]`, `array[0..255]` or `array[0..MAX_PROC_PARAMS-1]`, the build emits the same code/data/bss/procs and SizeOf(TProc) stays 1344 (= 32 x 40) at MAX_PROC_PARAMS 16, 32 and 64 alike. Not a const-expr gap and not scale: the identical shape standalone folds 1312 -> 2592, and a LOCAL array with the same const expression folds to 64 elements in the same file. The layout silently ignores the bound while the staging arrays around it widen, which is what makes raising MAX_PROC_PARAMS a SIGSEGV at exactly 33 parameters instead of a build error."
---

# The measurement

Three declarations of one field, each built with `compiler/pascal26` at
`e9599a1b0`, everything else identical:

| `TProc.Params` declared | code | data | bss | procs |
| --- | --- | --- | --- | --- |
| `array[0..31]` | 7565080 | 555780 | 86531556 | 4641 |
| `array[0..255]` | 7565080 | 555780 | 86531556 | 4641 |
| `array[0..MAX_PROC_PARAMS-1]` | 7565080 | 555780 | 86531556 | 4641 |

`Procs : array[0..MAX_PROCS-1] of TProc` is a static BSS array with
`MAX_PROCS = 16384`, so a 256-slot field would add ~167MB of bss. It adds
nothing.

A `WriteLn(SizeOf(TProc))` compiled into `RegisterProc` reports **1344** — with
`SizeOf(TParam) = 40`, exactly 32 slots — at `MAX_PROC_PARAMS` = 16, 32 **and**
64.

**The binaries are not byte-identical**, so the bound does reach emitted code
somewhere; it is the LAYOUT that ignores it. Controlled: two builds of one
source to two different output paths are byte-identical, so builds here are
deterministic and path-independent.

# What it is NOT — three controls, because the obvious readings are all wrong

**Not a const-expr gap.** The field's own comment blamed one for years. A LOCAL
`pnames : array[0..MAX_PROC_PARAMS-1] of AnsiString` in `pasparser_proc.inc`
folds to **64 elements** at `MAX_PROC_PARAMS = 64` — measured in this same
build, by the same technique. `CTypeFnRetPTypes` and eight siblings at
`defs.inc:4617` have used the constant in a bound all along.

**Not scale, and not record fields in general.** A standalone program with the
same shape — 16384-element static array, 40-byte element record, the array
field bound by a const expression — folds correctly: `SizeOf` goes
1312 -> 2592 and bss 21495808 -> 42467328 when the constant moves 32 -> 64.

**Not a literal-versus-expression split.** `array[0..255]`, a bare literal, is
ignored exactly as the expression is. Any fix aimed only at const folding will
not touch this.

# Why it costs more than a wrong number

The staging arrays around this field **do** widen — `pasparser_proc.inc`'s
locals, `cparser.inc`'s locals, the `ProcParam*` parallel arrays sized
`n*MAX_PROC_PARAMS`. `RegisterProc`'s guard is `nParams > MAX_PROC_PARAMS` and
is correct. So raising the constant makes every surrounding structure accept 64
parameters and leaves the destination at 32, and

```pascal
Procs[ProcCount].Params[i].Name := pnames[i];   { symtab.inc, i = 32 }
```

writes past the field. Confirmed under gdb: SIGSEGV in `RegisterProc` with
`i = 32`, `nParams = 33`, from a bare `external` declaration — no body, no call
site — in the Pascal and C frontends alike, on two independently seeded
compilers.

**A limits constant that silently does nothing is worse than one that is
hardcoded**, because the hardcoded one carries a comment telling you to move
its twin.

# Neighbourhood

`defs.inc:4346` records `project_tsymbol_field_landmine`: adding a single field
to `TSymbol` reproducibly corrupts the self-built binary's symbol table, while
writing an existing field the same way is fine. Same file, same family of
compiler-own-record layout defects, and worth checking whether one cause serves
both before treating this as isolated.

# Repro

```
sed -i 's/array\[0\.\.31\] of TParam/array[0..255] of TParam/' compiler/defs.inc
./compiler/pascal26 compiler/compiler.pas /tmp/probe    # bss is unchanged
```
