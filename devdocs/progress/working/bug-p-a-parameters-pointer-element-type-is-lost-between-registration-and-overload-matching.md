---
prio: 65
track: P
owner: frankA
status: working
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

---

## ROOT CAUSE, 2026-08-30 (frankA) — measured; it is neither of the two hypotheses

Reproduced at HEAD first: the `GetPropInfo(o, 'Caption')` program in the
"Why it matters" section still **segfaults**, so the defect is live, not stale.

This ticket says to settle *"whether the symbol is wrong or the field is"* before
choosing a fix. **Neither.** Probes at both ends of the same parameter
(`p.ptrparam`, a temporary channel), binary `9a8963cfd4a6`:

```
REG   proc=GetPropInfo i=0 sym=363 elemtk=5 stored=5 procParamSym=363 name=cls kind=2 symcount=364
MATCH proc=GetPropInfo j=0 sym=363 ptrelem=0                          name=o   kind=1 symcount=365
```

- `Procs[i].Params[j].SymIdx` is **stable and correct** — 363 at both ends.
- `SetSymPointerType` **does** store the value: `stored=5`, read back from
  `Syms[idx].PtrElemTk` immediately after the call.
- By match time `Syms[363]` is **`o`** — the *test program's own variable*,
  `kind=1` where the parameter was `kind=2` (skParam).

**The slot was recycled.** The index is right, the write is right, and the symbol
it names has ceased to exist. `symtab.inc`'s `SymRollbackTo` does this on
purpose: it unhashes a routine's symbols and hands the indices back.

So the failure is not data loss and not a bad lookup — it is a **stored index
outliving its referent**, and the value that comes back is whatever the next
scope allocated there. For a pointer field that reads as `tyUnknown`, which is
the **untyped-pointer sentinel**, so the narrowing guard *fails open* and permits
the class argument. A guard that fails open on stale data is why this segfaults
instead of mis-diagnosing.

### This is the FOURTH instance, and defs.inc documents the other three

Not a new hazard. `defs.inc` already carries the mechanism and the reasoning:

- `ProcParamRecId` (:2611) — *"param syms are reused across procs, so this must
  persist"*
- `ProcParamSetEnumId` (:2612) — *"A PARALLEL ARRAY rather than a TParam field...
  a param symbol does not outlive the callee's scope, so a CALLER parsing
  `f([...])` cannot ask the symbol"*
- `ProcParamProcSig` (:2617) — the same rationale a third time
- `defs.inc:2018` even records the same measurement in the same style:
  *"the params are rolled back when the operator body finishes... (measured:
  SymIdx 93, SymCount 92)"*

`MatchParamCompatible` reached for the non-durable mechanism with the durable one
three lines away in the same file. That makes this a
`normalise-dont-special-case` case, not a design question.

### Direction — confirmed, and now for a measured reason

The ticket's suggested `ProcParamPtrElemTk` is right: `Proc*` arrays live as long
as the `Proc`; `Sym` slots do not. Put `ProcParamPtrElemTk`/`ProcParamPtrElemRec`
next to `ProcParamRecId`, write them where `ptypesPtrElemTk[i]` already reaches
in `pasparser_proc.inc`, and read them in `MatchParamCompatible` instead of
`Syms[si]`. One more column in an existing family; no new concept.

**Rejected alternative:** the precedent fix in `SymRollbackTo`'s own comment —
raising the high-water mark so an index is never reused — works for a
routine-local typed const (*"a few dead slots in a routine that has one"*) and
does **not** scale here: it would strand a slot per parameter of every routine.

### Scope of the read side

`MatchParamCompatible` is the only site that reads a parameter's symbol from a
**caller's** context. A broad `\.SymIdx` grep finds reads in nine files, but the
ones I checked read during the declaring proc's own parse, where the scope is
live (e.g. `pasparser_call.inc:1483` is `Procs[CurProc].Params[0]`). **I have not
audited all of them** and am not claiming the rest are safe — only that this is
the one on the overload-matching path.

### Blocked on the A slot

`defs.inc` is shared core. This ticket already says to route it as Track A if a
new `Proc*` array is needed, and it is. Requested from the coordinator; probes
are local and uncommitted until then.
