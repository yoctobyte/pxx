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
  BY-VALUE AGGREGATE CLASSIFICATION — SysV x86-64 psABI 3.2.3.

  The question: when a C struct is passed BY VALUE, how many ABI slots does it
  occupy and what class is each? SysV splits an aggregate of at most 16 bytes
  into one or two EIGHTBYTES, classes them INTEGER or SSE, and sends anything
  larger to memory. That is the answer `ABIParamSlotIsPointer` cannot give: it
  returns one pointer-width slot for every record, which is the CONVENTION pxx
  implements today and not the ABI gcc does
  (bug-a-c-a-by-value-struct-parameter-is-passed-as-a-pointer-to-every-c-abi-callee).

  IT REFUSES RATHER THAN GUESSES, and that is the whole design. A conservative
  answer is not available here: "when unsure, say MEMORY" is not safe, because
  gcc will have put the bytes in registers and a disagreement is a silently
  wrong value across the link, not a slower one. So every shape this cannot
  classify EXACTLY returns -1 and the caller must refuse to compile. Wrong-and-
  quiet is the failure mode this whole ticket is about; loud is available and
  costs a diagnostic.

  Only x86-64 answers. AAPCS64 has HFA/HVA rules that are a different table, and
  the 32-bit targets another again; asking here on those returns -1 so a caller
  that forgets to check the target refuses instead of applying the wrong ABI.
  --------------------------------------------------------------------------- }
const
  SYSV_CLS_NONE    = 0;
  SYSV_CLS_INTEGER = 1;
  SYSV_CLS_SSE     = 2;
  SYSV_CLS_MEMORY  = 3;

{ psABI 3.2.3 step 4's merge, minus the X87 rows we refuse before reaching. }
function ABISysVMergeCls(a, b: Integer): Integer;
begin
  if a = b then ABISysVMergeCls := a
  else if a = SYSV_CLS_NONE then ABISysVMergeCls := b
  else if b = SYSV_CLS_NONE then ABISysVMergeCls := a
  else if (a = SYSV_CLS_MEMORY) or (b = SYSV_CLS_MEMORY) then ABISysVMergeCls := SYSV_CLS_MEMORY
  else ABISysVMergeCls := SYSV_CLS_INTEGER;   { INTEGER dominates SSE }
end;

{ One scalar's contribution. A field contributes to EVERY eightbyte its bytes
  touch, which is why this is a range and not a single index -- a double at
  offset 4 of a 16-byte struct straddles, and both halves become SSE-merged. }
procedure ABISysVMergeScalar(tk: TTypeKind; ofs, sz: Integer;
                             var c0, c1: Integer; var ok: Boolean);
var cls, i, lo, hi: Integer;
begin
  if not ok then Exit;
  if (ofs < 0) or (sz <= 0) or (ofs + sz > 16) then begin ok := False; Exit; end;
  { tyExtended is x87 (class X87/X87UP), which psABI sends to MEMORY as part of
    a struct. Refused rather than mapped, because getting it subtly wrong is
    exactly the silent disagreement this file refuses to risk.

    THIS ARM IS UNREACHABLE FROM THE C FRONTEND TODAY, and that is measured, not
    assumed: clexer.inc:342 maps C `long double` to double, so
    `struct { long double x; }` arrives here as one 8-byte tyDouble field and is
    classified 1x SSE. gcc makes that struct SIXTEEN bytes and MEMORY class.
    Verified both sides: gcc sizeof = 16, pxx sizeof = 8.

    So the guard cannot fire for the case it was written for -- the information
    is gone before the oracle is asked -- and the divergence is PRE-EXISTING and
    wider than this file (any long-double struct crossing a C boundary is
    already wrong, with or without aggregate classification). Filed as
    bug-c-long-double-is-8-bytes-in-pxx-and-16-in-gcc.

    KEPT, not deleted: it is correct the day a frontend produces tyExtended, and
    the Pascal frontend has that type. Deleting it would remove a correct guard
    because one caller currently cannot reach it. What was wrong was the comment
    claiming it covered long double, so the comment is what changed. }
  if tk = tyExtended then begin ok := False; Exit; end;
  if TypeIsFloat(tk) then cls := SYSV_CLS_SSE else cls := SYSV_CLS_INTEGER;
  lo := ofs div 8;
  hi := (ofs + sz - 1) div 8;
  for i := lo to hi do
    if i = 0 then c0 := ABISysVMergeCls(c0, cls)
    else if i = 1 then c1 := ABISysVMergeCls(c1, cls)
    else begin ok := False; Exit; end;
end;

{ Walk one record's fields at `base`, recursing into nested records and static
  arrays. A UNION needs no special case: its members share offsets, so they
  merge into the same eightbyte, which is what psABI says to do. }
procedure ABISysVWalkRec(recId, base: Integer; var c0, c1: Integer;
                         var ok: Boolean; depth: Integer);
var ci, k, i, f, n, cnt, elemSz, fofs: Integer; ftk: TTypeKind; frec: Integer;
begin
  if not ok then Exit;
  if depth > 8 then begin ok := False; Exit; end;
  { A BUILTIN record is compiler-authored (TSymbol/TParam/...), never a C struct
    crossing an ABI boundary. Refused rather than walked. }
  if recId < REC_UCLASS_BASE then begin ok := False; Exit; end;
  ci := recId - REC_UCLASS_BASE;
  n := UClsFCount[ci];
  if n <= 0 then begin ok := False; Exit; end;
  for k := 0 to n - 1 do
  begin
    f := UClsFBase[ci] + k;
    fofs := base + UFldOff_[f];
    ftk := IntToTypeKind(UFldTk[f]);
    frec := UFldRec_[f];
    if UFldDynDepth[f] > 0 then begin ok := False; Exit; end;   { dyn array: a handle, not inline }
    if UFldIsArray[f] then
    begin
      cnt := UFldArrLen[f];
      if cnt < 0 then begin ok := False; Exit; end;
      elemSz := TypeStorageSize(ftk, frec);
      if elemSz <= 0 then begin ok := False; Exit; end;
      for i := 0 to cnt - 1 do
      begin
        if ftk = tyRecord then
          ABISysVWalkRec(frec, fofs + i * elemSz, c0, c1, ok, depth + 1)
        else
          ABISysVMergeScalar(ftk, fofs + i * elemSz, elemSz, c0, c1, ok);
        if not ok then Exit;
      end;
    end
    else if ftk = tyRecord then
      ABISysVWalkRec(frec, fofs, c0, c1, ok, depth + 1)
    else
      ABISysVMergeScalar(ftk, fofs, TypeSlotSize(ftk), c0, c1, ok);
    if not ok then Exit;
  end;
end;

{ How many ABI slots a by-value record parameter occupies on x86-64.
    > 0  that many eightbytes (1 or 2); cls0/cls1 hold SYSV_CLS_INTEGER or _SSE
    = 0  MEMORY -- the bytes go on the stack, ceil(size/8) stack slots
    < 0  NOT CLASSIFIABLE -- the caller must refuse to compile, never guess }
function ABISysVRecordEightbytes(recId: Integer; var cls0, cls1: Integer): Integer;
var sz: Integer; ok: Boolean;
begin
  cls0 := SYSV_CLS_NONE; cls1 := SYSV_CLS_NONE;
  ABISysVRecordEightbytes := -1;
  if TargetArch <> TARGET_X86_64 then Exit;
  sz := RecSize(recId);
  if sz <= 0 then Exit;
  if sz > 16 then begin ABISysVRecordEightbytes := 0; Exit; end;
  ok := True;
  ABISysVWalkRec(recId, 0, cls0, cls1, ok, 0);
  if not ok then Exit;
  if (cls0 = SYSV_CLS_MEMORY) or (cls1 = SYSV_CLS_MEMORY) then
  begin ABISysVRecordEightbytes := 0; Exit; end;
  if cls0 = SYSV_CLS_NONE then Exit;      { no field covered eightbyte 0 }
  if sz <= 8 then
  begin
    if cls1 <> SYSV_CLS_NONE then Exit;   { a field past the size: refuse }
    ABISysVRecordEightbytes := 1;
  end
  else
  begin
    if cls1 = SYSV_CLS_NONE then Exit;    { >8 bytes but nothing in eightbyte 1 }
    ABISysVRecordEightbytes := 2;
  end;
end;

{ PLACEMENT: where does ONE cdecl argument go, given how much of each register
  bank is already spoken for? Classification (what class is it) and placement
  (does it fit) are one call because SysV couples them: an aggregate goes in
  registers only if ALL of its eightbytes fit in what is LEFT, and otherwise it
  goes on the stack ENTIRELY -- it is never split between the two. Written as
  two functions, that rule has to be restated by every caller, and the caller
  that restates it slightly differently is the one that desynchronises every
  argument after it.

  `intIdx`/`sseIdx` are IN OUT: the shared bank state each side already keeps.
  This does not do the whole walk the way ABIA64CdeclArgSlot does, because both
  x86-64 sides already have an accumulating loop of their own -- the caller
  needs slot ARRAYS (it pushes right-to-left and pops left-to-right) and the
  callee walks parameters in order. Handing them a per-argument step lets each
  keep its own loop and share the only part that must not differ.

  nSlots is what the argument OCCUPIES: 1 for a scalar, 1 or 2 for a
  register-classified aggregate, ceil(size/8) for a MEMORY one. reg0/reg1 are
  bank indices, or -1 when that slot is on the stack.

  A by-REF or open-array parameter is a pointer and is INTEGER class whatever
  its declared type -- the same rule, and the same reason, as the aarch64 walk
  above states at length.
  bug-a-c-a-by-value-struct-parameter-is-passed-as-a-pointer-to-every-c-abi-callee }
procedure ABISysVArgPlace(tk: TTypeKind; isRef, isArray: Boolean; recId: Integer;
                          var intIdx, sseIdx: Integer;
                          var nSlots: Integer; var isMem: Boolean;
                          var sse0, sse1: Boolean; var reg0, reg1: Integer);
var n, c0, c1, sz, needInt, needSse: Integer;
begin
  nSlots := 1; isMem := False;
  sse0 := False; sse1 := False; reg0 := -1; reg1 := -1;

  { An aggregate passed BY VALUE is the only case with more than one slot. }
  if (tk = tyRecord) and (not isRef) and (not isArray) and
     (TargetArch = TARGET_X86_64) then
  begin
    n := ABISysVRecordEightbytes(recId, c0, c1);
    if n > 0 then
    begin
      { Count what this aggregate needs from each bank, then take all of it or
        none. `needInt`/`needSse` rather than testing the banks one slot at a
        time: a MIX (INTEGER,SSE) with one GP register left and eight SSE free
        must go to the stack WHOLE, and a per-slot test would place its first
        eightbyte and strand the second. }
      needInt := 0; needSse := 0;
      if c0 = SYSV_CLS_SSE then Inc(needSse) else Inc(needInt);
      if n = 2 then
        if c1 = SYSV_CLS_SSE then Inc(needSse) else Inc(needInt);
      if (intIdx + needInt <= 6) and (sseIdx + needSse <= 8) then
      begin
        nSlots := n;
        if c0 = SYSV_CLS_SSE then
        begin sse0 := True; reg0 := sseIdx; Inc(sseIdx); end
        else begin reg0 := intIdx; Inc(intIdx); end;
        if n = 2 then
        begin
          if c1 = SYSV_CLS_SSE then
          begin sse1 := True; reg1 := sseIdx; Inc(sseIdx); end
          else begin reg1 := intIdx; Inc(intIdx); end;
        end;
        Exit;
      end;
      { Classifiable but the banks are too full: MEMORY, by the same rounding
        as a natively-MEMORY aggregate below. }
      sz := RecSize(recId);
      nSlots := (sz + 7) div 8;
      if nSlots < 1 then nSlots := 1;
      isMem := True;
      Exit;
    end;
    if n = 0 then
    begin
      sz := RecSize(recId);
      nSlots := (sz + 7) div 8;
      if nSlots < 1 then nSlots := 1;
      isMem := True;
      Exit;
    end;
    { n < 0 -- the classifier REFUSED (a shape it does not model). Fall through
      to the one-pointer-slot answer, which is what the compiler did for every
      aggregate before this existed. A refusal must not silently become a
      guess about the ABI. }
  end;

  if TypeIsFloat(tk) and (not isRef) and (not isArray) then
  begin
    sse0 := True;
    if sseIdx < 8 then begin reg0 := sseIdx; Inc(sseIdx); end;
  end
  else
    if intIdx < 6 then begin reg0 := intIdx; Inc(intIdx); end;
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
