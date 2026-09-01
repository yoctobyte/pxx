{ ============================================================================
  THE ABI ORACLE — the one place that answers calling-convention questions.

  Design: `devdocs/dev/type-identity-as-substrate.md` item 4; ticket
  `feature-a-abi-oracle`.

  ## Why this file exists

  `IRTk` is a bare kind and identity rides `IRA`/`IRB`/`IRC` positionally per
  opcode. That is not enough to emit code, so every backend reached around the
  IR into frontend data and re-derived the convention for itself:

      (Syms[symIdx].Kind = skParam) and (Syms[symIdx].IsRef or ...)

  written out longhand in five backends plus `symtab.inc`. Eight copies of what
  reads like one rule. **They are not one rule**, which is the thing measurement
  established and reasoning had not (2026-08-09):

    * **slot SIZE** — how many bytes `AllocParam` reserves and `ParamSize`
      reports. `ABIParamSlotIsPointer`.
    * **callee SLOT-HOLDS** — whether the slot contains the VALUE or a POINTER
      to it, i.e. whether taking the parameter's address means "the slot's
      address" or "load the slot". `ABIParamSlotHoldsValueAddr`.

  and the caller's PASSES-BY half lives in `IRLowerCallArg`. Each backend's
  answers must agree with each other; they need NOT agree across backends, and
  they do not: riscv32 and i386 leave `tySet` out of the SLOT-HOLDS set while
  x86-64/aarch64/arm32 include it, and both arrangements are internally
  consistent (see `bug-a-set-and-shortstring-value-params-alias-the-caller`,
  which is what happens when the caller half disagrees with them).

  So the oracle is a per-target TABLE, not a portable predicate. Encoding it
  here makes the divergence deliberate and reviewable instead of accidental and
  invisible: previously nobody could say which of the eight copies was
  authoritative, and no test would have caught a ninth drifting.

  ## The invariant this file exists to enforce

  **Backends consult the oracle and never re-derive the convention from
  `Syms[]`.** Enforced by `tools/abi_oracle_lint.py`, which fails the moment a
  backend condition combines an ABI-carrying `Syms[]` field with a type-kind
  test for a PARAMETER. Run it; do not review by eye.

  This clause used to say the invariant was "greppable in review: a
  `Syms[...].IsRef or` chain inside `ir_codegen*.inc`". **That grep was
  calibrated to a SPELLING, not to a shape, and it never fired** -- the
  re-derivation that did happen was spelled `and ... and not`, and wrapped
  across lines where a line-oriented grep could not see it either. By
  2026-08-31 the grep matched exactly one line in the tree: a COMMENT quoting
  this rule. A reviewer running it got a hit, opened it, found prose, and
  concluded the tree was clean -- which is worse than the zero it returned
  before, because a hit reads as evidence the check works.
  `bug-a-the-abi-oracle-invariant-is-enforced-by-a-grep-that-cannot-fire`.

  The linter carries its own positive controls (`--selftest`): shapes it MUST
  flag, including one proving a routine-scoped exemption cannot leak past the
  next routine header. A check that cannot fail and a check that is passing are
  the same observation, and only one of them is worth anything.

  ## Success metric (from the ticket)

  Adding one new pass-by-pointer type kind must take ONE edit, here, not nine.
  ============================================================================ }

{ Does a PARAMETER's stack slot hold the ADDRESS OF THE VALUE rather than the
  value itself?

  Asked by every backend when it needs the address of a parameter: if the slot
  holds the value, the answer is the slot's own address (`lea`); if the slot
  holds a pointer the caller put there, the answer is a LOAD of the slot.

  Kinds in the set on every target:
    * `IsRef`    — `var`/`out`/`const`, and records the ABI passes by reference.
    * `IsArray`  — an open array: the slot holds the caller's data pointer.
    * frozen strings — `string[N]`/`ShortString`: the caller passes a buffer.
    * `tyVariant` — the caller forwards the 16-byte slot by address.

  `tySet` is the per-target row, and it is a REAL convention difference rather
  than drift: it is in the set exactly on the targets whose argument lowering
  passes a set param's address. i386 and riscv32 pass the value, so dereferencing
  their slot would read the first 8 bytes of the set AS a pointer.

  Takes a symbol index rather than a TypeRef for now. Lane 1 of
  `feature-a-typeref-migrate-consumers` is what turns this into a query on a
  type's identity alone; the shape of the answer does not change when it does. }
function ABIParamSlotHoldsValueAddr(symIdx: Integer): Boolean;
begin
  ABIParamSlotHoldsValueAddr := False;
  if symIdx < 0 then Exit;
  if Syms[symIdx].Kind <> skParam then Exit;
  if Syms[symIdx].IsRef or Syms[symIdx].IsArray or
     TypeIsFrozenString(Syms[symIdx].TypeKind) or
     (Syms[symIdx].TypeKind = tyVariant) then
  begin
    ABIParamSlotHoldsValueAddr := True;
    Exit;
  end;
  { the per-target row }
  if Syms[symIdx].TypeKind = tySet then
    ABIParamSlotHoldsValueAddr :=
      (TargetArch = TARGET_X86_64) or (TargetArch = TARGET_AARCH64) or
      (TargetArch = TARGET_ARM32);
end;

{ Is a PARAMETER's slot pointer-SIZED — the layout question, distinct from the
  one above and answering it differently on purpose.

  A `tyClass` or `tyPointer` param's slot holds a pointer because the pointer IS
  the value: pointer-sized, and taking the parameter's address still means the
  slot's address, so it is NOT in the SLOT-HOLDS set. A `tySet` param's slot is
  the full 32-byte set on the targets that pass it by value, so it is not
  pointer-sized anywhere.

  Moved here from `symtab.inc`, unchanged. `ParamSize` and `AllocParam` both
  read it, which is what stopped THOSE two from disagreeing — they did, on
  `tyVariant` (`bug-a-param-pointer-rule-divergence`), and that fix is the
  small-scale precedent for this whole file. }
function ABIParamSlotIsPointer(tk: TTypeKind; isRef, isArray: Boolean): Boolean;
begin
  ABIParamSlotIsPointer := isRef or isArray or (tk = tyString) or
                           (tk = tyRecord) or (tk = tyVariant) or
                           (tk = tyClass) or (tk = tyPointer);
end;

{ ---------------------------------------------------------------------------
  RETURNS. `RetViaHiddenDest` is the oracle's `ReturnVia` query, and it was
  ALREADY a single shared function when this ticket was written — the ticket's
  claim that "AN_CALL and AN_VIRTUAL_CALL decide returns independently" is
  stale. The direct, virtual, indirect and interface call paths all reach it,
  and all four build their destination with the one IRBuildHiddenDest. Moved
  here unchanged, so the oracle is genuinely one place rather than the parameter
  half being here and the return half somewhere else.

  The ticket's CAUTION holds and is visible in the predicate: this is NOT
  "aggregate implies hidden dest". A tyAnsiString is an aggregate by any
  informal reading and returns a heap HANDLE in a register, so it is absent from
  the set on purpose.
  --------------------------------------------------------------------------- }
function RetViaHiddenDest(tk: TTypeKind): Boolean;
{ Return types whose ABI is a caller-owned hidden destination pointer (NRVO):
  records/sets AND the inline frozen string kinds. The callee copies its Result
  local into [dest] and returns the dest pointer; the caller allocates the
  destination. Frozen strings previously returned a shared BSS-global Result
  address (not reentrant, bug-frozen-string-result-global). A default frozen
  `string` result is capped at LOCAL_STR_CAP (256, the ShortString norm). }
begin
  { tyVariant added for Variant-returning functions (pylib TPyList.get/pop —
    the first in the codebase): 16-byte result via the same caller-owned
    hidden destination as records (feature-core-variant-function-return). }
  { The PROMOTABLE INT family joins them for the same reason tyVariant did: a
    promo value is a {tag, payload} STRUCT (8 or 16 bytes), and its rvalue is the
    SLOT ADDRESS. Returned the ordinary way, a promo-returning function handed
    back the address of its own dying Result local, so the caller read freed
    stack — `function mk: PromoInt; begin end;` + `writeln(mk)` segfaulted, with
    an EMPTY body, so it was never about the assignment
    (bug-a-promoint-function-result-crashes). AggRetCopySize already falls
    through to TypeSlotSize, which is the right byte count for both widths. }
  Result := TypeIsAggregate(tk) or TypeIsFrozenString(tk) or (tk = tyVariant)
            or TypeIsPromoInt(tk);
end;

function AggRetCopySize(retSymIdx: Integer): Integer;
{ Byte count copied from the Result local into the caller's hidden destination. }
var tk: TTypeKind;
begin
  { A FIXED-ARRAY result: the byte count is the whole array, recorded per-proc
    because the Result symbol's KIND is only its element type.
    bug-a-set-and-array-function-results-come-back-empty }
  if (CurProc >= 0) and (CurProc < ProcCount) and
     (ProcRetFixedArrBytes[CurProc] > 0) then
  begin
    Result := ProcRetFixedArrBytes[CurProc];
    Exit;
  end;
  tk := Syms[retSymIdx].TypeKind;
  if tk = tyRecord then Result := RecSize(SymTR[retSymIdx].RecId)
  else if tk = tyString then Result := LOCAL_STR_CAP + 8
  else if (tk = tyFixedString) or (tk = tyShortString) then
    Result := FrozenStrSlotSize(tk, SymStrCap[retSymIdx])
  else Result := TypeSlotSize(tk);
end;

{ Does a CALL to this routine return through the caller-owned hidden
  destination? The kind-only `RetViaHiddenDest` cannot answer for a FIXED-ARRAY
  result: `function F: TArr` records the ELEMENT kind in `Procs[].RetType`, so
  the kind says tyInteger and the aggregate is invisible. The parser records the
  byte size in ProcRetFixedArrBytes instead, and this is the query that joins
  the two — the caller allocates the scratch and the callee's epilogue copies
  into it, exactly as for a record.
  bug-a-set-and-array-function-results-come-back-empty }
function ABIRetViaHiddenDestProc(procIdx: Integer): Boolean;
begin
  ABIRetViaHiddenDestProc := False;
  if (procIdx < 0) or (procIdx >= ProcCount) then Exit;
  ABIRetViaHiddenDestProc := RetViaHiddenDest(Procs[procIdx].RetType) or
                             (ProcRetFixedArrBytes[procIdx] > 0);
end;


{ AAPCS64 argument placement for the C ABI: is argument `argIdx` of `procIdx` in
  a register, and if so which bank and index -- or on the stack, and at what byte
  offset in the stack argument area?

  ONE function, because the CALLER (ir_codegen_aarch64.inc's ProcExternal-or-
  CProcUsesCAbi arm) and the CALLEE (EmitParamSpillsForTarget's ProcCdecl arm)
  have to agree argument for argument, and a disagreement here is not a wrong
  number in one slot -- it desynchronises every argument after it. The two used
  to carry the register half twice, each counting its own `lo`/`hi`, and both
  simply REFUSED past eight of either bank rather than growing a stack area.

  AAPCS64 stage C, restricted to the scalar types a C signature can express
  here: an integral or pointer argument takes x[NGRN] while NGRN < 8, a
  floating-point one takes v[NSRN] while NSRN < 8, and the two counters are
  INDEPENDENT -- f(i1,d1,i2,d2) puts i1,i2 in x0,x1 and d1,d2 in d0,d1. When a
  bank is full its argument goes to the stack at NSAA and THAT BANK is set to 8;
  the other bank keeps allocating. Every scalar slot is 8 bytes, which is
  AAPCS64's own rounding for a type of 8 bytes or less, so the stack area is a
  plain array of doublewords and needs no per-argument alignment.

  A by-REF or open-array parameter is a POINTER and belongs to the INT bank
  whatever its declared type. Getting that one wrong was a segfault rather than
  a wrong number on x86-64
  (bug-a-a-by-ref-float-param-through-a-cdecl-fnptr-is-classified-sse), and it
  is the reason this asks ABIParamSlotIsPointer rather than TypeIsFloat alone.

  bug-a-aarch64-has-no-stack-argument-passing-for-the-three-c-abi-call-kinds }
{ `selfCount` is how many INJECTED arguments precede the declared parameters --
  a method's Self, always integer-class. Argument i therefore carries parameter
  i - selfCount, and an index outside [0, ParamCount) is integer-class by
  construction: below the range it is injected Self, above it is a variadic
  tail, and AAPCS64 puts both in the GP bank. The direct call arm and the
  callee spill pass 0; only the INDIRECT arm can see a nonzero one.
  This parameter exists so the indirect arm does not hand-roll a second
  NGRN/NSRN/NSAA walk -- it had one, register-only, and growing an NSAA into
  it would have made two mechanisms for one convention.
  devdocs/dev/normalise-dont-special-case.md }
procedure ABIA64CdeclArgSlot(procIdx, argIdx, selfCount: Integer; var isFp: Boolean;
                             var regIdx, stackOff: Integer);
var i, pi, ngrn, nsrn, nsaa: Integer;
    fp: Boolean;
begin
  ngrn := 0; nsrn := 0; nsaa := 0;
  isFp := False; regIdx := -1; stackOff := -1;
  for i := 0 to argIdx do
  begin
    pi := i - selfCount;
    fp := (pi >= 0) and (pi < Procs[procIdx].ParamCount) and
          TypeIsFloat(Procs[procIdx].Params[pi].TypeKind) and
          (not ABIParamSlotIsPointer(Procs[procIdx].Params[pi].TypeKind,
                                     Procs[procIdx].Params[pi].IsRef,
                                     Procs[procIdx].Params[pi].IsArray));
    isFp := fp; regIdx := -1; stackOff := -1;
    if fp then
    begin
      if nsrn < 8 then begin regIdx := nsrn; Inc(nsrn); end
      else begin nsrn := 8; stackOff := nsaa; Inc(nsaa, 8); end;
    end
    else
    begin
      if ngrn < 8 then begin regIdx := ngrn; Inc(ngrn); end
      else begin ngrn := 8; stackOff := nsaa; Inc(nsaa, 8); end;
    end;
  end;
end;

{ The 16-byte-aligned size of the AAPCS64 stack argument area for `procIdx`'s
  first `nparams` ARGUMENTS (not parameters: pass the arg count, and the same
  `selfCount` shift the slot walk uses) -- 0 when everything fits in the banks.
  16 and not
  8 because sp must stay 16-byte aligned at a public interface. }
function ABIA64CdeclStackBytes(procIdx, nparams, selfCount: Integer): Integer;
var i, regIdx, stackOff, hiOff: Integer;
    isFp: Boolean;
begin
  hiOff := -1;
  for i := 0 to nparams - 1 do
  begin
    ABIA64CdeclArgSlot(procIdx, i, selfCount, isFp, regIdx, stackOff);
    if stackOff > hiOff then hiOff := stackOff;
  end;
  if hiOff < 0 then ABIA64CdeclStackBytes := 0
  else ABIA64CdeclStackBytes := ((hiOff + 8 + 15) div 16) * 16;
end;
