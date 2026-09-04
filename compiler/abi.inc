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
  { the per-target rows }
  if Syms[symIdx].TypeKind = tySet then
    ABIParamSlotHoldsValueAddr :=
      (TargetArch = TARGET_X86_64) or (TargetArch = TARGET_AARCH64) or
      (TargetArch = TARGET_ARM32) or (TargetArch = TARGET_WASM32)
  else if Syms[symIdx].TypeKind = tyRecord then
    { A BY-VALUE RECORD ON WASM32 IS ALWAYS AN ADDRESS, at every size.

      Every other target splits a record of 8 bytes or less across argument
      words and passes a pointer only above that, so the answer there depends
      on a size this function is not given — which is why the row is not
      "tyRecord everywhere". wasm has no word-splitting to do: a parameter is
      one typed local, and an aggregate is not a wasm value type. So ir.inc
      takes the private-copy path for EVERY by-value record on this target
      (see needTemp, which names the same decision from the caller's side) and
      what arrives is uniformly the temp's address.

      The two halves must agree or the callee reads a pointer as bytes. They
      are stated in two files because one is the caller's question and one is
      the callee's; this comment and that one are the link. }
    ABIParamSlotHoldsValueAddr := (TargetArch = TARGET_WASM32);
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
                          var sse0, sse1: Boolean; var reg0, reg1: Integer;
                          var isAgg: Boolean);
var n, c0, c1, sz, needInt, needSse: Integer;
begin
  nSlots := 1; isMem := False; isAgg := False;
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
        nSlots := n; isAgg := True;
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
      isMem := True; isAgg := True;
      Exit;
    end;
    if n = 0 then
    begin
      sz := RecSize(recId);
      nSlots := (sz + 7) div 8;
      if nSlots < 1 then nSlots := 1;
      isMem := True; isAgg := True;
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
{ AAPCS64 PLACEMENT: where does ONE argument go, given how much of each bank is
  already spoken for? `ngrn`/`nsrn`/`nsaa` are IN OUT -- the shared walk state --
  and every argument is described the same way, by how many registers of ONE
  bank it wants and how many BYTES it occupies:

    a scalar          nRegs = 1, size = 8, isFp by its type
    a GP composite    nRegs = 1 or 2, size = the aggregate's own size
    an HFA            nRegs = 1..4, size = the aggregate's own size, isFp
    an INDIRECT one   nRegs = 1, size = 8, not FP -- it IS a pointer here

  So the scalar case is not a special case; it is nRegs = 1. That is why
  ABIA64SlotWalk below now delegates rather than keeping its own copy of the
  rule -- it was the whole rule when every argument was one register, and
  growing composites into it would have made two mechanisms for one convention.
  Same reason ABISysVArgPlace exists on the x86-64 side, stated there at length.

  ALL OR NOTHING, and it is the half a per-slot rewrite gets wrong: an argument
  that does not fit in what is LEFT of its bank goes to the stack ENTIRELY, and
  the bank is then CLOSED (NGRN/NSRN set to 8) so nothing smaller sneaks in
  behind it. Measured against clang: five `{double,double}` arguments put four
  in d0..d7 and the fifth wholly on the stack. Placing an HFA's first two
  registers and stranding the third would be a plausible wrong answer rather
  than a crash.

  The two banks advance INDEPENDENTLY, which is why a trailing integer after an
  HFA lands in w0 and not w2. A walk that advanced NGRN for an FP argument would
  be wrong in a way no single-argument probe can see.
  bug-a-an-aggregate-argument-is-a-pointer-by-construction-on-aarch64 }
procedure ABIA64ArgPlace(nRegs, size: Integer; isFp: Boolean;
                         var ngrn, nsrn, nsaa: Integer;
                         var regIdx, stackOff: Integer);
var fits: Boolean;
begin
  regIdx := -1; stackOff := -1;
  if nRegs < 1 then nRegs := 1;
  if size < 1 then size := 8;
  if isFp then fits := nsrn + nRegs <= 8 else fits := ngrn + nRegs <= 8;
  if fits then
  begin
    if isFp then begin regIdx := nsrn; Inc(nsrn, nRegs); end
    else begin regIdx := ngrn; Inc(ngrn, nRegs); end;
    Exit;
  end;
  { Bank closed, and the argument goes to the stack whole. NSAA is 8-aligned
    here because pxx models no argument whose natural alignment exceeds 8 --
    ABIA64RecordClass REFUSES an aggregate with alignment > 8 rather than
    letting one reach this walk. }
  if isFp then nsrn := 8 else ngrn := 8;
  stackOff := nsaa;
  Inc(nsaa, ((size + 7) div 8) * 8);
end;

{ THE AAPCS64 placement walk over a FULL per-argument description -- how many
  registers of which bank each argument wants and how many bytes it occupies.

  ABIA64SlotWalk below is this walk with every argument fixed at one register
  and eight bytes, which is what an argument list of scalars and pointers IS.
  It is kept as its own entry point because the VARIADIC path builds a class
  vector out of argument node types and has no aggregates to describe; giving
  it the wide signature would make every caller carry two vectors of ones.
  bug-a-an-aggregate-argument-is-a-pointer-by-construction-on-aarch64 }
procedure ABIA64VecWalkN(const argRegs, argSize: array of Integer;
                         const argFp: array of Boolean; argIdx: Integer;
                         var isFp: Boolean; var regIdx, stackOff: Integer);
var i, ngrn, nsrn, nsaa: Integer;
begin
  ngrn := 0; nsrn := 0; nsaa := 0;
  isFp := False; regIdx := -1; stackOff := -1;
  for i := 0 to argIdx do
  begin
    isFp := argFp[i];
    ABIA64ArgPlace(argRegs[i], argSize[i], isFp, ngrn, nsrn, nsaa, regIdx, stackOff);
  end;
end;

procedure ABIA64SlotWalk(const argFp: array of Boolean; argIdx: Integer;
                         var isFp: Boolean; var regIdx, stackOff: Integer);
{ THE AAPCS64 placement walk, over a per-ARGUMENT class vector rather than over
  a parameter list. NGRN and NSRN advance independently and share one NSAA, and
  the answer for argument `argIdx` is whatever the walk holds when it gets there.

  Split out of ABIA64CdeclArgSlot so that a VARIADIC call can ask the same
  question. That walk derived the class from `Procs[procIdx].Params[pi]` and
  therefore answered "not floating point" for every argument past ParamCount --
  correct for a fixed signature and wrong for a variadic tail, where the class
  has to come from the ARGUMENT's own type because there is no parameter. One
  walk with two sources for the vector, not two walks.
  bug-a-aarch64-passes-a-variadic-float-in-an-fp-register-so-glibc-reads-zero }
var i, ngrn, nsrn, nsaa: Integer;
begin
  ngrn := 0; nsrn := 0; nsaa := 0;
  isFp := False; regIdx := -1; stackOff := -1;
  for i := 0 to argIdx do
  begin
    isFp := argFp[i];
    ABIA64ArgPlace(1, 8, isFp, ngrn, nsrn, nsaa, regIdx, stackOff);
  end;
end;

{ Walk one record's fields deciding whether it is a HOMOGENEOUS FLOATING-POINT
  AGGREGATE: every member, after nested records and static arrays are flattened,
  is the SAME fundamental floating-point type. `fpTk` starts tyUnknown and is
  fixed by the first member seen; `cnt` counts flattened members. `ok` goes
  False the moment anything is not that -- an integer member, a second FP type,
  a dynamic array, a shape the walk does not model.

  Mirrors ABISysVWalkRec's shape deliberately (same field arrays, same union
  handling by shared offsets, same depth cap, same refusal on a BUILTIN record
  id) so the two classifiers can be read against each other. What differs is the
  QUESTION: SysV merges members into eightbyte classes, AAPCS64 asks whether
  they are all one FP type, and those do not reduce to each other.
  bug-a-an-aggregate-argument-is-a-pointer-by-construction-on-aarch64 }
procedure ABIA64WalkHfa(recId, base: Integer; var fpTk: TTypeKind;
                        var cnt: Integer; var ok: Boolean; depth: Integer);
var ci, k, i, f, n, arrCnt: Integer; ftk: TTypeKind; frec: Integer;
begin
  if not ok then Exit;
  if depth > 8 then begin ok := False; Exit; end;
  if recId < REC_UCLASS_BASE then begin ok := False; Exit; end;
  ci := recId - REC_UCLASS_BASE;
  n := UClsFCount[ci];
  if n <= 0 then begin ok := False; Exit; end;
  for k := 0 to n - 1 do
  begin
    f := UClsFBase[ci] + k;
    ftk := IntToTypeKind(UFldTk[f]);
    frec := UFldRec_[f];
    if UFldDynDepth[f] > 0 then begin ok := False; Exit; end;
    arrCnt := 1;
    if UFldIsArray[f] then
    begin
      arrCnt := UFldArrLen[f];
      if arrCnt < 0 then begin ok := False; Exit; end;
    end;
    for i := 0 to arrCnt - 1 do
    begin
      if ftk = tyRecord then
        ABIA64WalkHfa(frec, base, fpTk, cnt, ok, depth + 1)
      else
      begin
        { tyExtended is refused for the same reason ABISysVMergeScalar refuses
          it: pxx's `Extended` is 8 bytes and a C `long double` is 16 on this
          ABI, so any answer here would be about a different type.
          bug-c-long-double-is-8-bytes-in-pxx-and-16-in-gcc }
        if (not TypeIsFloat(ftk)) or (ftk = tyExtended) then begin ok := False; Exit; end;
        if fpTk = tyUnknown then fpTk := ftk
        else if fpTk <> ftk then begin ok := False; Exit; end;
        Inc(cnt);
        if cnt > 4 then begin ok := False; Exit; end;
      end;
      if not ok then Exit;
    end;
  end;
end;

{ AAPCS64 classification of a by-value COMPOSITE argument -- where does it go?
    > 0  in that many registers of ONE bank. `isFp` says which: an FP answer is
         1..4 registers of the same fundamental type (an HFA), a GP answer is
         1 or 2 X registers holding the aggregate's own bytes.
    = 0  INDIRECTLY -- one GP slot holding a pointer to a copy the caller makes.
         This is what pxx does for EVERY aggregate today, which is why a probe
         built around a large struct reports no defect.
    < 0  NOT CLASSIFIABLE. The caller must keep whatever it does now and must
         not guess: an ABI guess is not one wrong argument, it is every argument
         after it.

  Refusals, and each is a real shape rather than defensive padding:
  - alignment > 8. AAPCS64 rounds NGRN up to an even number for a 16-aligned
    composite, and that rounding is not modelled here yet; answering without it
    would place the argument one register early.
  - size <= 0, or a walk that refused (see ABIA64WalkHfa).

  NO PRODUCTION CONSUMER YET -- see the ticket. This lands with a PXXDBG probe
  and a test that checks it against clang's placement for the same shapes, so
  that the classifier is PROVEN BEFORE anything depends on it. The by-value
  switch (ABICRecordParamByValue) and the caller/callee halves move together in
  the next step, because they are one decision: a caller and a callee that
  disagree about what a slot CONTAINS desynchronise everything after it.
  bug-a-an-aggregate-argument-is-a-pointer-by-construction-on-aarch64 }
function ABIA64RecordClass(recId: Integer; var nRegs: Integer;
                           var isFp: Boolean; var fpTk: TTypeKind): Integer;
var sz, cnt: Integer; ok: Boolean;
begin
  nRegs := 0; isFp := False; fpTk := tyUnknown;
  ABIA64RecordClass := -1;
  if TargetArch <> TARGET_AARCH64 then Exit;
  sz := RecSize(recId);
  if sz <= 0 then Exit;
  if recId >= REC_UCLASS_BASE then
    if UClsAlign[recId - REC_UCLASS_BASE] > 8 then Exit;

  { HFA first: it is not a size question. `struct { double x, y; }` is 16 bytes
    and goes in d0,d1, while `struct { long a, b; }` is 16 bytes and goes in
    x0,x1 -- same size, different bank, and only the member types separate them. }
  cnt := 0; ok := True;
  ABIA64WalkHfa(recId, 0, fpTk, cnt, ok, 0);
  if ok and (cnt >= 1) and (cnt <= 4) and (fpTk <> tyUnknown) and
     (sz = cnt * TypeSlotSize(fpTk)) then
  begin
    { The size equality is the guard against padding: a homogeneous aggregate
      whose bytes are not exactly its members is not what AAPCS64 describes, and
      pxx's own record layout is the thing that would have to be trusted. }
    nRegs := cnt; isFp := True;
    ABIA64RecordClass := cnt;
    Exit;
  end;
  fpTk := tyUnknown;

  if sz <= 16 then
  begin
    nRegs := (sz + 7) div 8;
    if nRegs < 1 then nRegs := 1;
    isFp := False;
    ABIA64RecordClass := nRegs;
    Exit;
  end;
  { > 16 bytes: indirect. One GP slot, a pointer to the caller's copy. }
  nRegs := 1; isFp := False;
  ABIA64RecordClass := 0;
end;

{ MOVED BELOW ABIA64RecordClass, and the FPC seed canary is the reason. It
  used to sit ~420 lines above, which pxx accepts because pxx prescans headers;
  FPC is single-pass and rejects a call to a function it has not seen. The same
  ordering trap ABIA64ArgDesc hit one commit earlier, in the same file, on the
  same callee -- and neither make compiler/pascal26 nor testmgr --tier quick
  can see it. Keep this below ABIA64RecordClass. }
{ Is a C record parameter of this type passed BY VALUE in registers?

  THE ONE PREDICATE, because two sites must agree or the call desynchronises,
  and they are in different files: cparser's AllocParam (what the parameter IS,
  and so how the callee's body reads its fields) and the Params[].IsRef the
  signature carries (what the CALLER marshals). RegisterProc sets the second
  from `CProgramMode and (ptypes[i] = tyRecord)` and cannot do better -- it is
  handed type kinds and no record ids, so it cannot classify. cparser fixes it
  up right after, through this.

  The ticket's own words for why this is not two decisions: the caller and the
  callee must agree about what the slot CONTAINS. A disagreement here is not a
  wrong value in one argument, it is every argument after it.
  bug-a-c-a-by-value-struct-parameter-is-passed-as-a-pointer-to-every-c-abi-callee }
function ABICRecordParamByValue(recId: Integer): Boolean;
var c0, c1, a64N: Integer;
    a64Fp: Boolean;
    a64Tk: TTypeKind;
begin
  ABICRecordParamByValue := False;
  { i386 cdecl has no register arguments and no eightbyte classification: EVERY
    aggregate is passed as its own bytes in the stack argument area, rounded up
    to a whole number of 4-byte slots. So the only question is whether the size
    is known -- a REC_NONE id would size the argument from RecSize's fallback
    and desynchronise the block, which is the one thing worse than a pointer. }
  if TargetArch = TARGET_I386 then
  begin
    ABICRecordParamByValue := RecSize(recId) > 0;
    Exit;
  end;
  { AAPCS64: `> 0`, AND THE SIGN OF THE SysV TEST BELOW IS `>= 0` FOR A REASON
    THAT DOES NOT CARRY OVER. Both classifiers use 0 for "does not go in
    registers", and the two ABIs mean OPPOSITE things by it.

    SysV's 0 is MEMORY: the aggregate's OWN BYTES are in the stack argument
    area, so the slot IS the object and by-value is right. AAPCS64's 0 is
    INDIRECT: the argument is a POINTER to a copy the caller makes, so the slot
    is a pointer and the callee reads the object through it -- which is exactly
    the by-REFERENCE parameter pxx already had. Marking it by-value would make
    the callee copy 24 bytes into a slot the ABI never said it owned, and would
    change what every existing indirect-class parameter IS.

    MEASURED, and it is why this reads `> 0` today: with `>= 0`, `va_list`
    -- `struct __pxx_va_elem[1]`, 24 bytes, indirect class -- stopped being a
    pointer parameter, and every crtl routine that forwards one (vprintf,
    vsnprintf, __crtl_vformat) took a by-value slot. A plain
    `printf("hello %d %.2f")` SEGFAULTED on aarch64 while x86-64 stayed green,
    which is the shape of a change that is correct about one ABI and applied to
    another.

    The caller's obligation to pass a pointer to a COPY rather than to the
    original is a separate thing and is already met: the marshalling memcpys
    the aggregate into a temp before taking its address.
    bug-a-an-aggregate-argument-is-a-pointer-by-construction-on-aarch64 }
  if TargetArch = TARGET_AARCH64 then
  begin
    ABICRecordParamByValue := ABIA64RecordClass(recId, a64N, a64Fp, a64Tk) > 0;
    Exit;
  end;
  if TargetArch <> TARGET_X86_64 then Exit;
  { >= 0, not > 0: a MEMORY aggregate is passed BY VALUE as well -- as its own
    bytes in the stack argument area, not as a pointer to them. Only a REFUSAL
    (-1), a shape the classifier does not model, keeps the by-reference slot. }
  ABICRecordParamByValue := ABISysVRecordEightbytes(recId, c0, c1) >= 0;
end;

{ MOVED BELOW ABIA64RecordClass ON PURPOSE, and the FPC seed canary is why. It
  sat above ABIA64SlotWalk in the first draft, which pxx accepts -- pxx
  prescans headers -- and FPC does not, because FPC is single-pass: `calls
  ABIA64RecordClass, declared at abi.inc:704, which FPC has not seen yet`.
  Nothing else caught it: make compiler/pascal26 and testmgr --tier quick were
  both green on the draft. Keep this below its callee, or forward-declare it. }
{ Describe ONE AAPCS64 argument for ABIA64ArgPlace: how many registers of which
  bank it wants, how many bytes it occupies, and whether it travels as a POINTER
  to a caller copy. `ok` is False only when the composite classifier refused, and
  a refusal must stay a refusal -- the caller keeps whatever it does today rather
  than turning a "cannot classify" into a guess.

  A by-REF or open-array parameter is a pointer and is integer-class whatever its
  declared type, the same rule ABIA64ParamIsFp applies for the same reason.
  bug-a-an-aggregate-argument-is-a-pointer-by-construction-on-aarch64 }
procedure ABIA64ArgDesc(tk: TTypeKind; isRef, isArray: Boolean; recId: Integer;
                        var nRegs, size: Integer;
                        var isFp, isIndirect, isAgg, ok: Boolean);
var n, cnt: Integer; fpTk: TTypeKind; hfa: Boolean;
begin
  nRegs := 1; size := 8; isFp := False; isIndirect := False; isAgg := False;
  ok := True;
  if isRef or isArray then Exit;
  if tk = tyRecord then
  begin
    n := ABIA64RecordClass(recId, cnt, hfa, fpTk);
    if n < 0 then begin ok := False; Exit; end;
    if n = 0 then begin isIndirect := True; Exit; end;   { pointer: 1 GP, 8 bytes }
    nRegs := cnt; isFp := hfa; size := RecSize(recId); isAgg := True;
    Exit;
  end;
  isFp := TypeIsFloat(tk) and not ABIParamSlotIsPointer(tk, isRef, isArray);
end;

{ `isAgg` IS ITS OWN FLAG AND CANNOT BE INFERRED FROM nRegs AND size, which is
  what the first draft of the marshaller tried. `struct { int a, b; }` is ONE
  GP register and EIGHT bytes -- exactly a scalar's description -- so a guard
  reading `(nRegs > 1) or (size <> 8)` sends it down the scalar path and passes
  the ADDRESS where AAPCS64 wants the packed value. Measured against
  `clang --target=aarch64-linux-gnu -O1 -S`: four of the five shapes were
  already right and that one was not, and it is the SMALLEST aggregate there
  is. The default and the correct answer collide, so the fact has to be
  carried rather than derived.
  bug-a-an-aggregate-argument-is-a-pointer-by-construction-on-aarch64 }

{ The 16-byte-aligned AAPCS64 stack-argument bytes implied by a class VECTOR,
  the vector-sourced twin of ABIA64CdeclStackBytes below. A variadic call cannot
  use that one: it derives every class from the parameter list and there is no
  parameter for a tail argument, so it would under-count the stack whenever a
  float in the tail displaced a GP slot.
  bug-a-aarch64-passes-a-variadic-float-in-an-fp-register-so-glibc-reads-zero }
function ABIA64VecStackBytes(const argFp: array of Boolean; nArgs: Integer): Integer;
var i, regIdx, stackOff, hiOff: Integer;
    isFp: Boolean;
begin
  hiOff := -1;
  for i := 0 to nArgs - 1 do
  begin
    ABIA64SlotWalk(argFp, i, isFp, regIdx, stackOff);
    if stackOff > hiOff then hiOff := stackOff;
  end;
  if hiOff < 0 then ABIA64VecStackBytes := 0
  else ABIA64VecStackBytes := ((hiOff + 8 + 15) div 16) * 16;
end;

{ The same total as ABIA64VecStackBytes, over a FULL description. The last
  stack argument's own SIZE is what makes this different rather than a copy:
  the block ends where that argument ends, and an aggregate on the stack
  occupies its own bytes, not eight. Sizing it at eight would put the callee's
  frame on top of the tail of the last argument.
  bug-a-an-aggregate-argument-is-a-pointer-by-construction-on-aarch64 }
function ABIA64VecStackBytesN(const argRegs, argSize: array of Integer;
                              const argFp: array of Boolean; nArgs: Integer): Integer;
var i, regIdx, stackOff, hiEnd, e: Integer;
    isFp: Boolean;
begin
  hiEnd := -1;
  for i := 0 to nArgs - 1 do
  begin
    ABIA64VecWalkN(argRegs, argSize, argFp, i, isFp, regIdx, stackOff);
    if stackOff >= 0 then
    begin
      e := stackOff + ((argSize[i] + 7) div 8) * 8;
      if e > hiEnd then hiEnd := e;
    end;
  end;
  if hiEnd < 0 then ABIA64VecStackBytesN := 0
  else ABIA64VecStackBytesN := ((hiEnd + 15) div 16) * 16;
end;

function ABIA64ParamIsFp(procIdx, pi: Integer): Boolean;
var r: Boolean;
begin
  r := (pi >= 0) and (pi < Procs[procIdx].ParamCount);
  if r then
    r := TypeIsFloat(Procs[procIdx].Params[pi].TypeKind) and
         (not ABIParamSlotIsPointer(Procs[procIdx].Params[pi].TypeKind,
                                    Procs[procIdx].Params[pi].IsRef,
                                    Procs[procIdx].Params[pi].IsArray));
  if PxxDbgEnabled('a.a64fp') then
    WriteLn('A64FP pi=', pi, ' pc=', Procs[procIdx].ParamCount,
            ' tk=', Ord(Procs[procIdx].Params[pi].TypeKind), ' r=', Ord(r));
  ABIA64ParamIsFp := r;
end;

{ Describe ONE ARGUMENT of a call to `procIdx` -- the parameter-list source for
  ABIA64ArgDesc, with the two out-of-range cases the walk has always had. Below
  the parameter range is an injected Self (a pointer) and above it is a variadic
  tail (already promoted, and never an aggregate), so both are one GP slot and
  neither carries a record id. }
procedure ABIA64ArgDescOf(procIdx, pi: Integer; var nRegs, size: Integer;
                          var isFp, isIndirect, isAgg: Boolean);
var ok: Boolean;
begin
  nRegs := 1; size := 8; isFp := False; isIndirect := False; isAgg := False;
  if (pi < 0) or (pi >= Procs[procIdx].ParamCount) then Exit;
  ABIA64ArgDesc(Procs[procIdx].Params[pi].TypeKind,
                Procs[procIdx].Params[pi].IsRef,
                Procs[procIdx].Params[pi].IsArray,
                ProcParamRecId[procIdx * MAX_PROC_PARAMS + pi],
                nRegs, size, isFp, isIndirect, isAgg, ok);
  { A REFUSAL STAYS A REFUSAL. ABIA64RecordClass answers -1 for a shape it does
    not model rather than guessing, and ABICRecordParamByValue refuses the same
    shapes, so such a parameter is still IsRef and still one pointer-sized GP
    slot. Turning "cannot classify" into a placement here would desynchronise
    the call the classifier declined to describe. }
  if not ok then
  begin
    nRegs := 1; size := 8; isFp := False; isIndirect := False; isAgg := False;
  end;
end;

{ THE FULL AAPCS64 answer for one argument: where it goes, AND what occupies
  that place. `nRegs` is how many consecutive registers of `isFp`'s bank it
  takes, `size` how many bytes it occupies on the stack, `isIndirect` whether
  the slot holds a POINTER to a caller-made copy rather than the bytes.

  The three readers -- the callee spill, the direct call and the indirect call
  -- all ask this one question, which is the point: fixing the direct arm and
  not the indirect one produces a gate that passes because the subject contains
  no call through a function pointer, and that is the trap x86-64 and i386 both
  walked into on the parent ticket.
  bug-a-an-aggregate-argument-is-a-pointer-by-construction-on-aarch64 }
procedure ABIA64CdeclArgSlotN(procIdx, argIdx, selfCount: Integer; var isFp: Boolean;
                              var regIdx, stackOff, nRegs, size: Integer;
                              var isIndirect, isAgg: Boolean);
var i: Integer;
    argFp: array[0..MAX_PROC_PARAMS + 7] of Boolean;
    argRegs, argSize: array[0..MAX_PROC_PARAMS + 7] of Integer;
    dFp, dInd, dAgg: Boolean;
    dRegs, dSize: Integer;
begin
  for i := 0 to argIdx do
  begin
    if i > MAX_PROC_PARAMS + 7 then
      Error('target aarch64: argument index past the AAPCS64 class vector');
    ABIA64ArgDescOf(procIdx, i - selfCount, dRegs, dSize, dFp, dInd, dAgg);
    argFp[i] := dFp; argRegs[i] := dRegs; argSize[i] := dSize;
    if i = argIdx then
    begin
      nRegs := dRegs; size := dSize; isIndirect := dInd; isAgg := dAgg;
    end;
  end;
  ABIA64VecWalkN(argRegs, argSize, argFp, argIdx, isFp, regIdx, stackOff);
end;

procedure ABIA64CdeclArgSlot(procIdx, argIdx, selfCount: Integer; var isFp: Boolean;
                             var regIdx, stackOff: Integer);
var nRegs, size: Integer;
    isIndirect, isAgg: Boolean;
begin
  ABIA64CdeclArgSlotN(procIdx, argIdx, selfCount, isFp, regIdx, stackOff,
                      nRegs, size, isIndirect, isAgg);
end;

{ The 16-byte-aligned size of the AAPCS64 stack argument area for `procIdx`'s
  first `nparams` ARGUMENTS (not parameters: pass the arg count, and the same
  `selfCount` shift the slot walk uses) -- 0 when everything fits in the banks.
  16 and not
  8 because sp must stay 16-byte aligned at a public interface. }
function ABIA64CdeclStackBytes(procIdx, nparams, selfCount: Integer): Integer;
var i, regIdx, stackOff, hiEnd, e, nRegs, size: Integer;
    isFp, isIndirect, isAgg: Boolean;
begin
  { The END of the last stack argument, not its offset plus a fixed eight: an
    aggregate on the stack occupies its own bytes, and sizing the block at eight
    would let the callee's frame land on the tail of the last argument. }
  hiEnd := -1;
  for i := 0 to nparams - 1 do
  begin
    ABIA64CdeclArgSlotN(procIdx, i, selfCount, isFp, regIdx, stackOff,
                        nRegs, size, isIndirect, isAgg);
    if stackOff >= 0 then
    begin
      e := stackOff + ((size + 7) div 8) * 8;
      if e > hiEnd then hiEnd := e;
    end;
  end;
  if hiEnd < 0 then ABIA64CdeclStackBytes := 0
  else ABIA64CdeclStackBytes := ((hiEnd + 15) div 16) * 16;
end;

{ How many BYTES of a variadic function's own incoming stack area its NAMED
  parameters occupy -- i.e. where the variadic tail's overflow area begins,
  measured from the first incoming stack argument.

  NOT the same as ABIA64CdeclStackBytes: that one is 16-byte aligned because it
  sizes an outgoing block that sp must sit on, and this one is an OFFSET into an
  area the caller already laid out, so rounding it up skips a real argument.
  A named parameter reaches the stack only when its OWN bank is full, which is
  why this walks rather than comparing a total against 8 -- the all-GP form
  (ProcNamedGP + ProcNamedFP > 8) counted a float against the GP bank.
  bug-a-aarch64-passes-a-variadic-float-in-an-fp-register-so-glibc-reads-zero }
function ABIA64NamedStackBytes(procIdx: Integer): Integer;
var i, regIdx, stackOff, n: Integer;
    isFp: Boolean;
begin
  n := 0;
  for i := 0 to Procs[procIdx].ParamCount - 1 do
  begin
    ABIA64CdeclArgSlot(procIdx, i, 0, isFp, regIdx, stackOff);
    if stackOff >= 0 then Inc(n);
  end;
  ABIA64NamedStackBytes := n * 8;
end;

{ RV32 VARIADIC TAIL PLACEMENT — ONE ORACLE, ASKED BY BOTH HALVES.

  The receiving half (cparser's __builtin_va_arg -> __pxx_va_arg_cross32) and
  the marshalling half (ir_codegen_riscv32's variadic-tail arm) have to agree
  about two things per argument: how many bytes the slot holds, and whether the
  slot sequence pads to an even word first. They agree by asking here, the same
  way the aarch64 pair agrees by both asking ABIA64RecordClass.

  Measured against clang --target=riscv32-unknown-linux-gnu, reading the CALL
  SITE with a trailing int so the following argument's register is part of every
  row (a placer that gets the argument right and does not advance the sequence
  is a different bug that looks like this one):

    struct {char}          1b  a1,          tail a2   by value, one word
    struct {int}           4b  a1,          tail a2   by value, one word
    struct {int,int}       8b  a1,a2,       tail a3   by value, PACKED (align 4)
    struct {double}        8b  a2,a3,       tail a4   by value, SKIPS a1 (align 8)
    struct {long long}     8b  a2,a3,       tail a4   ditto
    struct {int,int,int}  12b  a1 POINTER,  tail a2   indirect, over 2 x XLEN
    struct {double,double}16b  a1 POINTER,  tail a2   indirect -- NOT fa0,fa1
    double (a scalar)      8b  a2,a3,       tail a4   SKIPS a1 (align 8)

  Two rules, and the second one is the one that was missing entirely:

  1. AN AGGREGATE IS BY VALUE IFF IT FITS IN 2 x XLEN. Over that it is a pointer
     to the caller's copy -- INCLUDING `struct { double x, y; }`, whose FIXED
     parameter form goes in fa0,fa1. riscv32's variadic rule is genuinely not
     its fixed rule, which is the opposite of aarch64, where it is. Three
     quarters of the shapes were therefore already right here, and that is
     exactly why this could sit open looking half-fine: any probe using a struct
     larger than 8 bytes measures GREEN on a target that is broken.

  2. AN 8-BYTE-ALIGNED SLOT STARTS ON AN EVEN REGISTER. This applies to a
     `double` and an `int64` as much as to a record, and pxx applied it to
     NEITHER -- `v(1, 2.5, 77)` put the double in a1:a2 where clang puts it in
     a2:a3. Fixing only the record half would have left the scalar sibling wrong
     in the same function, which is the shape this repo keeps re-finding.
     (arm32 already had the scalar half; see the align argument threaded into
     __pxx_va_arg_cross32.)

  slotBytes is the promoted width of a NON-record argument, ignored when recId
  names a record. bytes is what the slot HOLDS -- 4 for the indirect case,
  because there the slot holds a pointer and not the aggregate.
  bug-a-c-the-variadic-struct-abi-is-still-a-pointer-on-aarch64-arm32-and-riscv32 }
{ THE SAME QUESTION FOR XTENSA, AND IT HAS TO BE ASKED IN ONE PLACE BECAUSE
  BOTH SIDES ASK IT. XtensaPadTo64Xtensa starts a 64-bit argument at an EVEN
  word index -- measured from the IDF's own xtensa-esp32s3-elf-gcc, which puts
  `long long v` in a4:a5 and SKIPS a3 -- and that rule applies to a variadic
  argument exactly as to a named one. The READER (__pxx_va_arg_cross32) is told
  the alignment by the frontend and defaults to 4, the packed walk i386 and
  riscv32-scalar... take.

  With the two disagreeing, the caller pushed a pad word the walk did not skip:
  `printf("%llx", v)` printed the pad and the low word as one value, and it was
  visible only at ODD preceding-word counts, so `printf("%d %llx", 7, v)` was
  RIGHT and `printf("%llx", v)` was WRONG in the same program. Measured 2026-09-04
  across five positions; three wrong, two right, which is the signature of a
  parity disagreement rather than a broken read.

  Records are deliberately NOT given an answer here: the xtensa tail still
  passes an aggregate as a POINTER, four bytes and four-aligned, exactly as
  before, and inventing a by-value rule for them in a scalar fix is how a
  refactor gets blamed for a bug it did not cause.
  bug-cfront-no-entry-stub-for-xtensa }
function ABIXtensaVaArgSlotAlign(recId, slotBytes: Integer): Integer;
begin
  ABIXtensaVaArgSlotAlign := 4;
  if recId > REC_NONE then Exit;
  if slotBytes > 4 then ABIXtensaVaArgSlotAlign := 8;
end;

procedure ABIRV32VaArgDesc(recId, slotBytes: Integer;
                           var bytes, align: Integer; var byValue: Boolean);
begin
  align := 4;
  if recId > REC_NONE then
  begin
    bytes := RecSize(recId);
    byValue := (bytes >= 1) and (bytes <= 8);
    if not byValue then
    begin
      { The slot holds a POINTER to the caller's private copy. Four bytes,
        four-byte aligned -- the aggregate's own alignment says nothing about
        where a pointer to it sits. }
      bytes := 4;
      Exit;
    end;
    if recId >= REC_UCLASS_BASE then
      if UClsAlign[recId - REC_UCLASS_BASE] > 4 then align := 8;
    Exit;
  end;
  byValue := True;
  bytes := slotBytes;
  if bytes < 4 then bytes := 4;
  if bytes > 4 then align := 8;
end;

{ AAPCS32 VARIADIC TAIL PLACEMENT — the arm32 sibling of ABIRV32VaArgDesc, and
  a DIFFERENT RULE, which is the whole reason this ticket has three thirds.

  Measured against clang --target=armv7-linux-gnueabihf -O1 -S, reading the call
  site with a trailing int on every row:

    struct {int,int}        8b  r1,r2,              tail r3
    struct {int,int,int}   12b  r1,r2,r3,           tail [sp+0]
    struct {double,double} 16b  SKIPS r1: r2,r3 + [sp+0..7],  tail [sp+8]
    struct {int x6}        24b  r1,r2,r3 + [sp+0..11],        tail [sp+12]
    struct {int x10}       40b  r1,r2,r3 + [sp+0..27],        tail [sp+28]

  TWO RULES AAPCS64 DOES NOT HAVE, and porting ABIA64ArgPlace here would get
  both wrong:

  1. AN AGGREGATE SPLITS between the core registers and the stack. AAPCS64's
     placer is all-or-nothing -- an argument that does not fit its bank goes to
     the stack ENTIRELY and closes the bank -- and that is simply not this ABI.
  2. THERE IS NO INDIRECT CLASS AT ALL. However large the aggregate, its own
     bytes travel; a 40-byte struct occupies ten words. AAPCS64 hands over a
     pointer past 16 bytes and riscv32 past 8, so arm32 is the only one of the
     three where size never changes the answer.

  What it shares with riscv32 is the alignment rule: an 8-byte-aligned slot
  starts on an even word, for a `double` and an `int64` as much as for a record.
  arm32 already had that for scalars -- it is where __pxx_va_arg_cross32's
  `align` argument came from -- and this extends it to aggregates.

  bytes is the slot's own size, so a caller sizes ceil(bytes/4) words and the
  receiving walk steps the same. slotBytes is the promoted width of a NON-record
  argument and is ignored when recId names a record.
  bug-a-c-the-variadic-struct-abi-is-still-a-pointer-on-aarch64-arm32-and-riscv32 }
procedure ABIA32VaArgDesc(recId, slotBytes: Integer;
                          var bytes, align: Integer; var byValue: Boolean);
begin
  align := 4;
  byValue := True;
  if recId > REC_NONE then
  begin
    bytes := RecSize(recId);
    if bytes < 1 then bytes := 4;
    if recId >= REC_UCLASS_BASE then
      if UClsAlign[recId - REC_UCLASS_BASE] > 4 then align := 8;
    Exit;
  end;
  bytes := slotBytes;
  if bytes < 4 then bytes := 4;
  if bytes > 4 then align := 8;
end;
