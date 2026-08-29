---
slug: bug-a-open-array-of-string-arg-spilled-through-a-managed-string-temp
title: "An open-array-of-string argument is spilled through a hidden temp declared tyAnsiString that actually holds an array data pointer"
track: A
prio: 30
type: bug
status: backlog
owner: ""
created: 2026-08-29
summary: "`JoinOpen(['x','yy','zzz'])` for `procedure JoinOpen(const a: array of string)` spills the argument through a hidden temp that ir.inc declares tyAnsiString. An open-array parameter records its ELEMENT kind in TypeKind, and the spill guard at ir.inc:11207 reads that field without also testing IsArray -- the same file already guards correctly at :11329. The temp then holds an array data pointer while claiming to be a managed string. On the register backends the mistyped retain and the scope-exit release cancel, so nothing is observable and it has been latent; wasm32 type-checks the store and refuses the body. One-clause fix, confirmed by measurement."
---

# Symptom

```pascal
program jc;
procedure JoinOpen(const a: array of string);
var i: Integer; r: string;
begin
  r := '';
  for i := 0 to High(a) do r := r + a[i] + '.';
  writeln('n=', Length(a), ' r=', r);
end;
begin
  JoinOpen(['x', 'yy', 'zzz']);
end.
```

Native (x86-64) prints `n=3 r=x.yy.zzz.` and is correct. On `--target=wasm32`:

```
wasm32: 123 of 124 bodies lowered; 1 emitted as `unreachable`:
    main$0 — value of type Pointer assigned to a managed string
```

**Only the CONSTRUCTOR spelling is affected.** The same routine fed from a
`array of string` variable compiles and runs correctly on both targets, so
open-arrays-of-managed-elements are fine as a feature; it is the `[...]`
argument that goes wrong.

# Root cause

`ParseArrayCtorAST` (pasparser_lval.inc:3354) documents the convention this
trips over: an open-array parameter's `TypeKind` **is the element type**. For
`const a: array of string` that is `tyAnsiString`, with `IsArray` carrying the
"it is an array" half.

`ir.inc:11207`, in the plain `AN_CALL` argument loop, decides whether an
argument needs an owning managed-string temp:

```pascal
argIsManagedTemp :=
  (not isRefArg) and
  (((cpi >= 0) and (pathIdx < Procs[cpi].ParamCount) and
    (Procs[cpi].Params[pathIdx].TypeKind = tyAnsiString)) or
   ...
```

It reads `TypeKind` without also testing `IsArray`, so it fires on an
open-array-of-string parameter. The argument -- an `IR_LEA` of the
constructor's dyn-array temp, i.e. a Pointer -- is then stored into a hidden
`AllocVar('', tyAnsiString)`:

```
22: lea       a=92 tk=17         { tyPointer: the array temp's data pointer }
23: store_sym a=93 b=22 tk=23    { sym 93 is tyAnsiString, IsArray=FALSE }
24: load_sym  a=93 tk=23
25: arg       a=24 tk=23
26: call      a=129 b=25         { JoinOpen }
```

(Measured with a probe on the wasm backend's `IR_STORE_SYM` arm:
`sym=93 IsArray=FALSE ArrLen=0 Kind=1 TypeKind=23 IsRef=FALSE valkind=17`.)

So a slot the compiler believes is a managed string holds an array data
pointer.

**The same file already gets this right one site over.** `ir.inc:11329` guards
the analogous decision with `(not Procs[cpi].Params[pathIdx].IsArray)`. Four
`hiddenArgSym` sites do not: the plain `AN_CALL` loop (:11207/:11260), the
ctor-arg loop (:10969), `AN_CALL_IND` (:11604), `AN_INTF_CALL` (:11731) and
`AN_VIRTUAL_CALL` (:12724). Only the first is confirmed to fire for this repro;
the others share the shape and are worth checking in the same pass.

# Why no target has noticed

On the register backends the mistyped store retains the "string" (bumping a
word below the array data) and the scope-exit release decrements it again. The
two cancel, so the program is correct and nothing crashes -- verified with a
2000-iteration loop and with `-dPXX_HEAP_DEBUG`, both clean.

wasm32 is the only backend that type-checks the store rather than emitting a
machine word, so it is the only one that can see it. This is the third instance
of that pattern from the wasm lane: **a shared-frontend mistyping that every
register backend absorbs by arithmetic coincidence.** The value here is the
diagnosis, not the wasm refusal -- the refusal is just what made it visible.

# Fix, confirmed by measurement

Add the guard the file already uses at :11329:

```pascal
  (((cpi >= 0) and (pathIdx < Procs[cpi].ParamCount) and
    (not Procs[cpi].Params[pathIdx].IsArray) and
    (Procs[cpi].Params[pathIdx].TypeKind = tyAnsiString)) or
```

Applied locally on the `wasm` branch as a probe only (NOT committed): the
refusal disappears, `wasm32` lowers `124 of 124`, and the wasm output matches
native (`n=3 r=x.yy.zzz.`). The self-host fixedpoint converged in 1 round with
the guard in place. The probe was reverted; `ir.inc` on the `wasm` branch is
unmodified.

`ir.inc` is shared Track A ground, so this is filed rather than landed.

# Gate

Track A's: `make compiler/pascal26` (the byte-identical self-host fixedpoint)
plus the repro above on both `--target=wasm32` and native. Worth also checking
the sibling `hiddenArgSym` sites listed above, since a `var`/virtual/interface
call with an open-array-of-string parameter has the same shape.
