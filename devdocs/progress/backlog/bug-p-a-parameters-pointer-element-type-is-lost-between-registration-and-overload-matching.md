---
prio: 65
track: P
owner: unassigned
---

# A parameter's pointer element type is lost between registration and overload matching

- **Type:** bug (data loss, surfacing as wrong overload selection) — **Track P**
  (parameter registration). The *fix* may need a new `Proc*` parallel array in
  `defs.inc`, which is shared core — file/route as **Track A** if so.
- **Split out of**
  [[bug-p-a-class-instance-converts-implicitly-to-any-typed-pointer]] (`8b75fcabd`),
  which fixed the compatibility rule. This is the second, independent defect
  underneath it, and it is what still blocks
  [[feature-typinfo-facade-unit]]'s instance-taking overloads.
- **Binary:** `f2e90dedc75c`, verified fixedpoint.

## The measurement

Two probes, one at each end of the same parameter — typinfo's
`GetPropInfo(cls: PClassRTTI; ...)`, where `PClassRTTI = ^TClassRTTI` and
`TClassRTTI` is a record declared *before* it in the same interface:

At **registration** (`pasparser_proc.inc`, the `SetSymPointerType` call site):

```
PXXDBG a.pparam proc=GetPropInfo i=0 elemtk=5 elemrec=32
```

At **overload matching** (`symtab.inc`, `MatchParamCompatible`, reading
`Syms[Procs[i].Params[j].SymIdx].PtrElemTk`):

```
PXXDBG a.argptr proc=GetPropInfo j=0 symidx=362 ptrelem=0
```

**Captured as `tyRecord` (5), read back as `tyUnknown` (0).** The parser gets it
right; the value does not survive to the consumer, or
`Procs[i].Params[j].SymIdx` does not lead to the symbol that holds it.

## Why it matters

`tyUnknown` is the **untyped-`Pointer` sentinel**, so a consumer that reasons
over this field cannot distinguish "points at a record" from "takes anything"
and must permit the argument. That is exactly what happens to the narrowing
added in `8b75fcabd`: it is reached for `GetPropInfo`, reads `tyUnknown`, and
correctly permits the class argument *by its own rule*. So
`GetPropInfo(AnObject, 'Caption')` still binds the `PClassRTTI` arm and
segfaults, and typinfo's whole instance-taking facade stays unreachable —
gating `streams`, `classes_lite`, `lfm`, `lib/pcl` and fpjsonrtti.

Any future check that needs a parameter's pointee type inherits the same
silent failure, which is the general reason to fix it rather than work around it.

## Suggested direction

`ProcRetPtrElemTk` already exists as a `Proc*` parallel array for a routine's
**result** (`defs.inc:2520`, "pointed-at TTypeKind ord when the result is a typed
pointer (tyUnknown otherwise)"). There is no parameter equivalent — parameters
route through `Params[j].SymIdx` into `TSym` instead, and that is the hop where
the value is lost. Mirroring the existing array as `ProcParamPtrElemTk`, written
at the same place `ptypesPtrElemTk[i]` already reaches, keeps parameters and
results on the same mechanism instead of two.

Confirm first whether the symbol is wrong or the field is: `Syms[362]` may
simply not be that parameter (an interface declaration and its implementation
registering different symbols would explain it), in which case the fix is the
lookup, not the storage. **Measure that before choosing** — the two have
different fixes and the probes above make it a five-minute question.

## Do not verify with a synthetic overload pair

Every two-overload repro tried — in a program, and across a unit interface —
selects correctly **on `pinned`**, i.e. was never broken. Their parameters' element
types *are* recorded, so the pointer arm was never viable for them. Only the real
`typinfo.pas` call site is evidence; instrument the instance arm at
`lib/rtl/typinfo.pas:1479` and check it is entered.
