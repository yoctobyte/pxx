---
slug: bug-a-paramsize-and-allocparam-disagree-about-a-5-8-byte-byvalue-record
track: A
prio: 40
type: bug
found: 2026-08-30
owner: unassigned
---

# ParamSize and AllocParam disagree about a 5-8 byte by-value record

Two functions in `symtab.inc` answer "how big is this parameter's slot" and give
different answers for the same parameter on a 32-bit target. `AllocParam` is the
one that is right; `ParamSize` is the one every backend reads.

```pascal
{ AllocParam — allocates the slot }
if (tk = tyRecord) and not isRef and not isArray and (RecSize(LastTypeRecId) <= 8) then
begin
  sz := RecSize(LastTypeRecId);              { 8 for an 8-byte record }
  if sz < TARGET_PTR_SIZE then sz := TARGET_PTR_SIZE;
end
else if ABIParamSlotIsPointer(tk, isRef, isArray) then
  sz := TARGET_PTR_SIZE
...

{ ParamSize — reports the slot's size }
function ParamSize(idx: Integer): Integer;
begin
  if ABIParamSlotIsPointer(Syms[idx].TypeKind, Syms[idx].IsRef, Syms[idx].IsArray) then
    Result := TARGET_PTR_SIZE                 { 4 on a 32-bit target }
  else
    Result := TypeSize(Syms[idx].TypeKind);
end;
```

`ABIParamSlotIsPointer` holds `tyRecord` **unconditionally**, so `ParamSize`
returns `TARGET_PTR_SIZE` for every record — while `AllocParam` has already
reserved the record's real width for the <=8-byte by-value case. On 64-bit they
agree by coincidence (`TARGET_PTR_SIZE` = 8 covers any `RecSize <= 8`); on
arm32 / riscv32 / xtensa / i386 they do not.

## Why this is worth a ticket and not just a note

**It is a trap that costs a build cycle and produces a plausible false comment.**
Measured, on 2026-08-30, while landing
`bug-a-a-by-value-wide-record-on-xtensa-renders-a-live-address`: the natural way
to widen xtensa's callee param spill is

```pascal
((Syms[idx].TypeKind = tyRecord) and (sz > 4) and (sz <= 8))
```

because `sz := ParamSize(idx)` is already in scope three lines above and reads
like the width. That guard **compiles, self-hosts, and can never be true**. The
symptom is a repro that comes back byte-identical, which reads as "my change did
nothing" and sends you back to re-read arms that were already correct. It also
invites a comment asserting that `sz` asks the real width — one was written, and
it was wrong.

arm32 and riscv32 both dodge it, in this same procedure
(`EmitParamSpillsForTarget`, `ir_codegen.inc`), by *not* using `sz` for records:
they spell it `RecSize(Syms[idx].RecName)` in the spill guard and
`RecSize(ProcParamRecId[procIdx * MAX_PROC_PARAMS + i])` in the word-count
pre-pass. xtensa now matches them. So all three live call sites are correct
today — **this ticket is about the next one**, and about a helper whose name
promises an answer it does not give.

## No known miscompile today

Checked, so the priority is honest rather than defensive: the `else` branches
that consume `sz` only distinguish 1 / 2 / other, and a record reaching them
gets a full-word store, which is right for a <=4-byte record and is the only
case that still reaches there. i386 refuses record parameters outright
(`target i386: only ordinal/pointer parameters supported yet`), so it cannot be
silently wrong. `cparser.inc` and `eparser.inc` also call `ParamSize`; those
were **not** audited and are the first thing to check if this is picked up.

## Options

1. **Make `ParamSize` ask `RecSize`** for the by-value <=8-byte record case, so
   it agrees with `AllocParam`. Correct in principle and makes the natural guard
   work — but `ParamSize` takes only a symbol index, `Syms[idx].RecName` is
   available, and any consumer currently *relying* on getting 4 would change
   behaviour. Needs the C-frontend call sites audited first.
2. **Rename it** to say what it answers (`ParamSlotWordSize`, or fold it into
   the `abi.inc` oracle beside `ABIParamSlotIsPointer` with a comment naming the
   record exception). Cheap, no behaviour change, kills the trap.
3. Leave it and document the exception at both definitions.

Recommendation: **2**, and only then 1 if an audit shows no consumer depends on
the pointer-sized answer. The defect here is a misleading name on a shared
helper, not a wrong number reaching the emitter.

## Provenance

Found by frankS under a bounded grant for `EmitParamSpillsForTarget`'s xtensa
arm. Filed rather than fixed: `symtab.inc` and `abi.inc` are Track A's and were
outside that grant. Sibling of `bug-a-param-pointer-rule-divergence`, which is
the same two functions disagreeing about `tyVariant` — that fix is cited in
`abi.inc` as the small-scale precedent for the whole oracle, so this is the
second instance of one pattern.
