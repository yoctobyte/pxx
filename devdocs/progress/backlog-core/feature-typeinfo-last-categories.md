---
track: A
prio: 20
type: feature
blocked-by: []
summary: "The tail of the TypeInfo widening that still has NO consumer: interfaces (14) and metaclasses (28) are refused outright, TypeInfo(PChar) is refused while bare Pointer works, Currency (4) needs a tyCurrency that does not exist, procvar/method types get no TTypeData, and NativeInt reports tkInteger where FPC reports tkInt64 on a 64-bit target."
status: backlog
owner: unassigned
---

# A TypeInfo — the categories still without a consumer

Split out of [[feature-typeinfo-ttypedata-payloads]] when its section 1 (the
`TTypeData` payloads) landed, because that was the only part something actually
asked for. Everything below is still in the same position the parent ticket was
in for weeks: **do it when a consumer needs it**, so the answer is designed
against a real reader instead of guessed. Same discipline as before — every new
row diffed against an FPC 3.2.2 oracle, never recalled.

## 1. Interfaces (14) and metaclasses (28)

`TypeInfo(TSomeInterface)` and `TypeInfo(TSomeClassRef)` are refused. Both
already have class-side bookkeeping (`UClsIsInterface`, and metaclasses go
through `RegisterClassRefAlias` with `AliasElemRec` holding the base class), so
this is a category and a `DataPtr` target, not discovery.

## 2. `PChar` and pointer aliases

`TypeInfo(PChar)` is refused; FPC answers `PChar` / 29 `tkPointer`. Named
pointer aliases go through `RegisterPtrAlias` so `FindTypeAlias` should reach
them — check whether the miss is the alias lookup or `PChar` being a builtin
that never enters the table, and fix the one that is actually wrong. Bare
`Pointer` and `CodePointer` already work (they resolve through
`BuiltinTypeNameTk`).

## 3. `Currency` (4)

pxx has **no `tyCurrency`** at all. This is a type-system item, not an RTTI one,
and RTTI is the least of what it needs. Do not add a TypeInfo special case; the
kind falls out once the type exists.

## 4. A `TTypeData` for procedural types and method pointers

The only category the payload work deliberately left empty. A procvar's
signature is an `AliasProcSig` row in `Procs[]`, and there is no obvious shape
for it in the uniform nine-slot record — probably a pointer to a parameter-kind
table like `TMethInfo.ParamKinds` already uses. Nothing reads it, so nothing
constrains it, so it was not invented.

## 5. `NativeInt` / `NativeUInt` report the wrong KIND (measured)

Not a payload gap — a wrong answer, and the one item here that could bite
silently. `PxxTkToFPCKind` puts `tyNativeInt` / `tyNativeUInt` in the
`tkInteger` (1) group unconditionally. FPC 3.2.2 on x86-64 answers `tkInt64`
(19) and `tkQWord` (20), because `NativeInt` **is** `Int64` there; on i386 it
would be `tkInteger`. So the right answer is target-dependent on
`TARGET_PTR_SIZE` and we give a fixed one.

Today nothing observes it: the `TTypeData` payload is self-consistent
(`OrdType` = `otSQWord`, the range is the full 64-bit one), so a consumer that
switches on `Kind` lands in the `tkInteger` arm and still reads correct 64-bit
`MinValue`/`MaxValue` from our Int64 slots. It becomes a real bug the moment
something sizes a buffer or picks a code path from `Kind` alone.

Fixing it changes an existing answer, so it wants its own gate pass and a check
of `test/test_typeinfo_*.pas` expectations, which is why it was not folded into
the payload change.

## Gate

`make compiler/pascal26` + `tools/gate.sh quick`, extending the
`test_typeinfo_*.pas` programs in `test/`. The standing deliberate divergences
are [[decide-typeinfo-scalar-name-spelling]] and the two value divergences
recorded in [[feature-typeinfo-ttypedata-payloads]] (a subrange's `OrdType` is
our storage width; `LongWord`'s `MaxValue` is honest where FPC's truncates).
