---
summary: "FPC seed drift #4 in three days, now in Track A's own files: symtab.inc calls EmitAsmX64, defined in asmtext.inc five includes later. Verified one-line fix"
type: regression
track: A
prio: 60
---

# FPC seed drift #4: `EmitAsmX64` called from `symtab.inc`

- **Type:** regression, cold-start bootstrap path — **Track A**
- **Filed:** 2026-08-03 by `claude@xeon` (Track T) from the `fpc-bootstrap`
  canary. Handed over, not fixed.
- Notable: the first three were Track N frontend commits. This one is in **A's
  own files**, which kills the theory that it is a Track N habit.

## The failure

```
symtab.inc(5653,5) Error: Identifier not found "EmitAsmX64"
symtab.inc(5659,5) Error: Identifier not found "EmitAsmX64"
... (5 sites)
```

`compiler.pas` includes `symtab.inc` at line 79 and `asmtext.inc` — which
defines both `EmitAsmX64` overloads — at line 84.

## Verified fix — one line

`compiler.pas`, immediately before the `symtab.inc` include, beside the
existing `DbgFileId` / `AddDefaultCIncludeDirs` forwards that exist for exactly
this reason:

```pascal
procedure EmitAsmX64(const items: array of const); overload; forward;
```

Only the `array of const` overload is needed — symtab.inc never calls the
`AnsiString` one. Measured: `138681 lines compiled, 11.1 sec`, clean. Probe
reverted; tree clean.

## Four in three days — the pattern is the ticket now

| # | ticket | identifier | lane |
|---|---|---|---|
| 1 | [[bug-a-fpc-seed-drift-pymaketruthy-forward-wrong-file]] | `PyMakeTruthy` | A |
| 2 | [[bug-n-fpc-seed-drift-pybytesci-used-before-forward]] | `PyBytesCi` | N |
| 3 | [[bug-n-fpc-seed-drift-pywiden-needs-a-forward-in-parser-inc]] | `PyWiden` | N |
| 4 | this one | `EmitAsmX64` | A |

Every one is: a routine called from an include file that appears EARLIER in
`compiler.pas` than the file defining it, with no forward. pxx's own frontend
resolves all of them; FPC is single-pass and does not. The property is
therefore invisible to every check a dev runs, which is the whole reason it
keeps landing — see [[feature-t-fpc-seed-canary-closer-to-the-dev-loop]].

## Gate

`fpc -Mobjfpc -O2 -Tlinux -Px86_64 ... compiler/compiler.pas` compiles clean and
`fpc-bootstrap` goes green on the next watcher run.
