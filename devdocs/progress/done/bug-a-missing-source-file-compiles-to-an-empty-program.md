---
track: A
prio: 60
type: bug
status: done
owner: claude-AN
summary: "pxx on a nonexistent or unreadable source file printed `ok`, exited 0, and emitted a runnable binary that does nothing — LoadFile answers \"\" for an unopenable path and an empty NilPy source is a valid empty program"
---

# A missing source file compiled to an empty program, silently

- **Type:** bug (silent success) — **Track A** (driver)
- **Found:** 2026-08-06, bughunting — and found the way it bites: a heredoc that
  never ran left `w3.py` absent, `pascal26 w3.py w3.out` reported `ok`, and the
  resulting binary printed nothing. Several minutes went into "why does this
  NilPy loop produce no output" before `cat w3.py` said *No such file*.

## Measured (before, self-hosted binary at `e8450c58d`)

```
empty-file  exit=0  ok: /tmp/chk.out  [code=1340921B …]     <- correct
missing-py  exit=0  ok: /tmp/chk.out  [code=1340921B …]     <- WRONG
unreadable  exit=0  ok: /tmp/chk.out  [code=1340921B …]     <- WRONG (EACCES swallowed)
directory   exit=1  pascal26:1: error: unexpected character  <- right answer, by accident
```

A `.pas` main also failed to diagnose the missing file; it merely looked better,
erroring later and misleadingly:

```
pascal26:2: error: unexpected token
  near: >>> unit builtinheap
```

— the empty source fell through to the units path, so the complaint named a
builtin unit rather than the file the user typed.

## Cause

`LoadFile` (`compiler/elfwriter.inc:2892`) answers an EMPTY string when
`sysopen` fails:

```pascal
  f := sysopen(LoadPath, 0);
  if f >= 0 then …
  else
    SetLength(dst, 0);
```

That is indistinguishable from a genuinely empty file — and **an empty NilPy
source is a valid program**, so the frontend compiled it, correctly, into a
binary that does nothing.

## Fix

Check the MAIN input at the driver (`compiler/compiler.pas`, immediately before
the `LoadFile(inFile, Source)` call): `sysopen` it, and on failure print
`pascal26: error: cannot read input file: <path>` and `Halt(1)`.

Deliberately **not** fixed inside `LoadFile`: units and includes rely on
empty-means-absent to drive their own search chains (`LoadFileCI` reads the
result that way one routine below), so tightening the shared routine would break
every one of them. The main input is the one path where "absent" can only ever
be a mistake.

## Verified

| case | after |
| --- | --- |
| empty file | `exit=0 ok:` — still compiles, still correct |
| missing `.py` | `exit=1 pascal26: error: cannot read input file: …` |
| missing `.pas` | `exit=1` same message — no more `unit builtinheap` |
| unreadable (mode 000) | `exit=1` same message |
| ordinary program | `exit=0`, runs, prints `hi` |

`tools/gate.sh quick` GREEN (self-host fixedpoint byte-identical).

## Log

- 2026-08-06 — found, fixed and verified in one pass.
