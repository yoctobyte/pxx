---
track: P
prio: 60
type: bug
blocked-by: []
summary: "`r := s` where r is a record and s an AnsiString is correctly rejected (`incompatible types: cannot assign AnsiString to record`). The same assignment to an ELEMENT of an array of that record — `rs[1] := s` for a dyn array, `fx[0] := s` for a fixed one — compiles clean and segfaults at run time. FPC rejects all three. One concept, two paths, and the check lives on only one of them: the classic double-case shape. Found 2026-08-29 by the wasm32 lane through a botched line in its own test, which is the only reason anyone looked."
status: new
owner: ""
---

# A string assigned to a record ARRAY ELEMENT is not type-checked

- **Type:** bug (frontend type checking) — **Track P** (Pascal frontend).
- **Filed:** 2026-08-29 by the wasm32 lane (branch `wasm`, 24 ahead / 89 behind
  `d93190c4a` at the time). Target-independent: the native x86-64 build is what
  segfaults below.
- **Not a compat item.** By CLAUDE.md's table this is row two — *real Pascal
  source compiles but runs wrong* — so it is a bug in its own lane at its own
  prio, not a parity note. The program does not merely diverge from FPC; it
  crashes.

## Repro

```pascal
program TB2;
type
  TR   = record S: string; N: Integer; end;
  TRs  = array of TR;
  TFix = array[0..1] of TR;
var rs: TRs; fx: TFix; s: string;
begin
  SetLength(rs, 2);
  s := 'x';
  rs[1] := s;          { dyn-array element   — ACCEPTED }
  fx[0] := s;          { fixed-array element — ACCEPTED }
  writeln('compiled and ran');
end.
```

```
$ pascal26 tb2.pas tb2
ok: tb2  [code=62255B data=2036B bss=42500B procs=129]
$ ./tb2
Segmentation fault (core dumped)
```

The plain-variable form IS checked, in the same program:

```pascal
  r := s;   { -> pascal26:11: error: incompatible types: cannot assign AnsiString to record }
```

FPC rejects every one of them:

```
typebug.pas(9,12) Error: Incompatible types: got "AnsiString" expected "TR"
typebug.pas(11,8) Error: Incompatible types: got "AnsiString" expected "TR"
```

## Why this is worth more than one diagnostic

It is the shape `devdocs/dev/normalise-dont-special-case.md` is about: **one
concept — assigning to an lvalue of record type — reachable through two shapes,
with the check on only one of them.** The variable arm has it; the element arm
does not, for either array kind. The document's own advice applies to the fix:
when you add the missing check, grep for the sibling before closing this —
a record FIELD (`r.Inner := s`), a `var`/`out` parameter, and a class field are
the obvious neighbours and none of them was tested here.

The consequence is the expensive kind rather than the cheap one. It does not
fail to compile, it compiles to a byte move of a string HANDLE over a record's
first field, and what happens next depends on what that field is. Here it is
itself a managed string, so the segfault arrives at scope exit while releasing a
handle that was never one.

## How it was found, which is the part worth recording

Not by a test for this. The wasm32 lane wrote a bad line into its own slice —
`rs[1] := o2.Inner.S + '';`, a leftover from an edit — expected a type error,
and got a working compile and a core dump. **A test whose bad line is caught by
the compiler teaches nothing; this one was only found because the compiler
agreed with it.** Nobody was looking at record assignment that day.

## Gate

Per CLAUDE.md: `make compiler/pascal26` plus the repro above rejecting all four
forms. A `{%FAIL}` conformance case for each shape is the natural regression,
since the assertion is that compilation FAILS.
