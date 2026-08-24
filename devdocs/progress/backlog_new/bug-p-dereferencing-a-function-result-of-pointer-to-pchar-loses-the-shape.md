---
slug: bug-p-dereferencing-a-function-result-of-pointer-to-pchar-loses-the-shape
title: "`GetQ^` where `GetQ: ^PChar` is not recognised as a PChar — WriteLn prints the address"
track: P
prio: 30
type: bug
blocked-by: []
status: backlog_new
owner: ""
created: 2026-08-24
summary: "A function returning `^PChar`, dereferenced, is wrong in the four contexts that refuse to guess: WriteLn prints the address in decimal, concat on either side yields the address, and `=`/`<>` compare pointers. The three contexts that look right are right only by the blanket `AnsiString(<any pointer>)` rule. Unlike the array shape beside it, this one genuinely IS missing metadata: a proc records ProcRetPtrElemTk/Rec — the immediate pointee — and nothing about the return pointer's DEPTH or ultimate BASE."
---

# Symptom

```pascal
type PPC = ^PChar;
var p0: PChar;
function GetQ: PPC; begin GetQ := @p0; end;
...
WriteLn(GetQ^);          { fpc: alpha    pxx: 129547099963424 }
WriteLn('x' + GetQ^);    { fpc: xalpha   pxx: 129467708080280 }
WriteLn(GetQ^ + 'y');    { fpc: alphay   pxx: 131958113829017 }
WriteLn(GetQ^ = 'alpha');{ fpc: TRUE     pxx: FALSE  -- compares POINTERS }
```

`AnsiString(GetQ^)`, `s := GetQ^` and `Length(AnsiString(GetQ^))` answer
correctly, and that is **not** recognition: `AnsiString(<any pointer>)` treats
its operand as a PChar unconditionally. Four contexts wrong out of seven is what
an unrecognised shape looks like when a blanket rule covers the rest.

# Measured

2026-08-24, an 88-program cross product — 11 PChar sources x 8 contexts, each
its own program, each diffed against fpc 3.2.2. `pinned` diverged on 36. After
the `array of ^PChar` fix in
[[refactor-centralize-managed-string-pchar-conversion]], **5 remain, and all
five are this one shape.**

# Root cause, and why it is NOT the fix that just landed

The deref chain in `compiler/pasparser_lval.inc` needs two things for `x^`: the
pointer levels REMAINING and the ULTIMATE base kind. It has arms for `AN_IDENT`,
`AN_FIELD`, `AN_INDEX` and `AN_DEREF`, and **no arm for a call at all** — a call
falls to the `else` that yields `tyInteger`.

Adding an arm would not help, which is the actual finding. The array shape
beside this one *looked* like missing metadata and turned out to be present
under a name that means something else (`AllocArray` parks the ELEMENT's depth
and base in the symbol's own `SymPtrDepth`/`SymPtrBaseTk`). This one is not that:

```
$ grep -n "ProcRetPtr" compiler/defs.inc
2339:  ProcRetPtrElemTk  : array of Integer;   { pointed-at TTypeKind ord ... }
2342:  ProcRetPtrElemRec : array of Integer;   { pointed-at record id ... }
```

Two fields, both the IMMEDIATE pointee. There is no `ProcRetPtrDepth` and no
`ProcRetPtrBaseTk`, so `PChar` and `^PChar` are indistinguishable as return
types — exactly the ambiguity that ticket's `^PChar` note describes.

# The fix is a design call, not a patch — do NOT add two more parallel arrays

Symbols carry the pair (`SymPtrDepth`, `SymPtrBaseTk`/`Rec`) beside
(`PtrElemTk`, `PtrElemRec`). Mirroring that for procs means **two or three more
parallel arrays**, which is the sprawl
[[refactor-centralize-managed-string-pchar-conversion]] exists to reduce and
which its own text rules out: *"Adding a pair of parallel arrays would work and
is the wrong shape."*

The right shape is [[feature-a-typeref-migrate-consumers]] **lane 4** — proc
return types get one `TTypeRef` — and it is small: **10 write sites and 7 read
sites** for `ProcRetPtrElemTk` across `cparser.inc`, `pasparser_decl.inc`,
`pasparser_proc.inc` and `symtab.inc`.

**One thing to settle first, and it blocks the lane rather than this bug:**
`TTypeRef` as declared (`compiler/defs.inc:1559`) has `PtrBaseTk`/`PtrBaseRec`
and `DynDepth` — dynamic-array nesting — but **no pointer depth field**. Without
one it cannot express "pointer to (pointer to char)" any better than the pair it
replaces. Adding `PtrDepth` to `TTypeRef` is additive (nothing reads a pointer
depth off it today, because there is nothing to read) and looks clearly right,
but it changes a shared type mid-migration, so it wants a deliberate decision
rather than being slipped in under a bug fix.

# Repro

The 88-program generator is
`scratchpad/pc/xprod.py`-shaped: sources
{var, `q^`, `q[0]`, `qa[0]^`, `qd[0]^`, `GetQ^`, record field, array element,
dyn element, pointer arithmetic} x contexts {WriteLn, assign, concat L/R,
`AnsiString()`, `Length`, `=`, `<>`}. Re-run it against fpc after any change
here; it is the ticket's acceptance line made executable.
