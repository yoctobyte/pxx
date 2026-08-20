{ SPDX-License-Identifier: MPL-2.0 }
{ ===== RTTI emission (Phase 1: published-only, streaming-grade) =====

  Emits, for every class with >=1 published member, a compile-time RTTI blob
  into Data[], plus a name->RTTI registry. Layout is OUR own (see defs.inc
  RTTI_* constants); the public reflection API (Phase 2) puts TypInfo names on
  top of it. Cross-references between blobs use AddDataPtrFix (data->data);
  method/proc code addresses use MethodFixups (patched to runtime addresses at
  link time), exactly as the VMT does.

  proto-unit shape:
    needs:  UCls*/UFld*/UMth*/UProp* tables, UClsVMTOffset, UClsSize_,
            Find*/InternStr/Strs/DataPut*/AddDataPtrFix/MethodFixups
    provides: EmitRTTI, EmitPySignatures, DumpRTTITables

  This file is included after elfwriter.inc (DataPut*/PatchDataU64 live there)
  and is driven once from the main program after parsing. }

procedure EmitLayoutRTTI; forward;

function FieldIsManaged(fi: Integer): Boolean;
begin
  FieldIsManaged := False;
  if UFldTk[fi] = Ord(tyAnsiString) then FieldIsManaged := True
  else if UFldIsArray[fi] and (UFldArrLen[fi] = -1) then FieldIsManaged := True
  else if (UFldTk[fi] = Ord(tyRecord)) and RecordHasManagedFields(UFldRec_[fi]) then FieldIsManaged := True;
end;

function FieldIsComInterface(fi: Integer): Boolean;
{ A COM/ARC interface field (tyRecord whose rec is a COM interface): a
  refcounted handle. Used only for CLASS layout descriptors (member kind 4),
  where the release runs OUTSIDE the heap lock — the record path stays a benign
  leak pending a reentrant heap lock
  (bug-a-class-managed-fields-not-finalized-on-destroy). A CORBA interface
  field is NOT managed (plain pointer, no lifetime coupling). }
var fci: Integer;
begin
  FieldIsComInterface := False;
  if UFldTk[fi] <> Ord(tyRecord) then Exit;
  if UFldIsArray[fi] then Exit;
  if UFldRec_[fi] < REC_UCLASS_BASE then Exit;
  fci := UFldRec_[fi] - REC_UCLASS_BASE;
  if (fci >= 0) and (fci < UClsCount) and UClsIsInterface[fci] and UClsIsComInterface[fci] then
    FieldIsComInterface := True;
end;

function ClassFieldNeedsFinal(fi: Integer): Boolean;
{ CLASS-descriptor member predicate: everything the record path manages, plus
  COM interface fields (kind 4) and Variant fields (kind 5 — a variant slot can
  hold a managed string, a promo, or a refcounted NilPy object; the walker
  clears it via PXXVarClear on finalize, feature-nilpy-object-reclamation).
  CLASS descriptors only on purpose: extending FieldIsManaged itself would
  flip records with variant fields into the managed-record codegen paths,
  a much broader change than destroy-time finalize. }
begin
  ClassFieldNeedsFinal := FieldIsManaged(fi) or FieldIsComInterface(fi) or
    ((UFldTk[fi] = Ord(tyVariant)) and not UFldIsArray[fi]) or
    { NilPy only: class-typed fields are refcounted bindings (kind 6) —
      released on finalize so a dying instance drops its children. In Pascal
      mode a class field is a manual-lifetime pointer and stays out. }
    (isNilPy and (UFldTk[fi] = Ord(tyClass)) and not UFldIsArray[fi]);
end;

function RecordManagedFieldCount(ci: Integer): Integer;
var base, cnt, i, managed: Integer;
begin
  managed := 0;
  base := UClsFBase[ci];
  cnt := UClsFCount[ci];
  for i := 0 to cnt - 1 do
  begin
    if FieldIsManaged(base + i) then Inc(managed);
  end;
  RecordManagedFieldCount := managed;
end;

function TokSliceStr(off, len: Integer): AnsiString;
{ Build a real string from a name slice in TokChars (self-host safe: AppendChar). }
var s: AnsiString; i: Integer;
begin
  s := '';
  i := 0;
  while i < len do
  begin
    AppendChar(s, TokChars[off + i]);
    Inc(i);
  end;
  TokSliceStr := s;
end;

function ClassImplementsGuidedInterface(ci: Integer): Boolean;
{ True if this class (or an ancestor) has an IMT for an interface that carries a
  GUID. Such a class needs an RTTI header even with NO published members, because
  TObject.GetInterface reaches its interface table through that header — without
  this a plain `class(TObject, IFoo)` would be invisible to a GUID lookup. }
var i, curr: Integer;
begin
  ClassImplementsGuidedInterface := False;
  curr := ci;
  while curr >= 0 do
  begin
    for i := 0 to IMTCount - 1 do
      if (IMTClass[i] = curr) and UClsHasGuid[IMTIntf[i]] then
      begin
        ClassImplementsGuidedInterface := True;
        Exit;
      end;
    curr := UClsParent[curr];
  end;
end;

function ClassHasPublished(ci: Integer): Boolean;
{ True if this class OR any ancestor declares a published member. A class that
  only inherits published members is still streamable (GetClass must find it),
  so it needs an RTTI header too. }
var base, cnt, i, curr: Integer;
begin
  ClassHasPublished := False;
  curr := ci;
  while curr >= 0 do
  begin
    base := UClsFBase[curr]; cnt := UClsFCount[curr];
    for i := 0 to cnt - 1 do
      if UFldPub[base + i] = 1 then begin ClassHasPublished := True; Exit; end;
    base := UClsMBase[curr]; cnt := UClsMCount[curr];
    for i := 0 to cnt - 1 do
      if UMthPub[base + i] = 1 then begin ClassHasPublished := True; Exit; end;
    base := UClsPBase[curr]; cnt := UClsPCount[curr];
    for i := 0 to cnt - 1 do
      if UPropPub[base + i] = 1 then begin ClassHasPublished := True; Exit; end;
    curr := UClsParent[curr];
  end;
end;

{ Streamable = the class declares or inherits a published member, or implements a
  guided interface. This is what the RTTI REGISTRY (GetClass / .lfm streaming) lists.

  It used to be enough to ask "does this class have an RTTI blob", because a blob was
  only emitted for exactly these classes. That proxy is now WRONG: every class carries
  a blob so that ClassName can answer for it. Registering all of them would let
  GetClass resolve names that were never meant to be streamable -- and it silently
  changed the registry count, which is what test_rtti_reg caught. }
function ClassIsStreamable(ci: Integer): Boolean;
begin
  ClassIsStreamable := (not UClsIsRecord[ci]) and
    (ClassHasPublished(ci) or ClassImplementsGuidedInterface(ci));
end;

procedure DataPutZeros(n: Integer);
var i: Integer;
begin
  i := 0;
  while i < n do begin DataPutB(0); Inc(i); end;
end;

procedure QueueMethCodeFixup(dataPos, procIdx: Integer);
begin
  if MethodFixCount >= MAX_METHFIX then Error('too many method fixups (RTTI)');
  MethodFixups[MethodFixCount].DataPos := dataPos;
  MethodFixups[MethodFixCount].ProcIdx := procIdx;
  Inc(MethodFixCount);
end;

{ Emit an enum type RTTI blob: name ptr, value count, ptr to array of name ptrs.
  Returns the Data[] offset of the header. }
function EmitEnumRTTI(etid: Integer): Integer;
var hdr, arrOff, base, cnt, i, strIdx: Integer;
    nm: AnsiString;
begin
  base := EnumTypeValBase[etid];
  cnt := EnumTypeValCount[etid];
  arrOff := DataLen;
  DataPutZeros(cnt * 8);
  for i := 0 to cnt - 1 do
  begin
    nm := TokSliceStr(EnumValNOff[base + i], EnumValNLen[base + i]);
    strIdx := InternStr(nm);
    AddDataPtrFix(arrOff + i * 8, Strs[strIdx].Offset);
  end;
  hdr := DataLen;
  DataPutZeros(24);
  nm := TokSliceStr(EnumTypeNOff[etid], EnumTypeNLen[etid]);
  strIdx := InternStr(nm);
  AddDataPtrFix(hdr + 0, Strs[strIdx].Offset);
  PatchDataU64(hdr + 8, cnt);
  if cnt > 0 then AddDataPtrFix(hdr + 16, arrOff);
  EmitEnumRTTI := hdr;
end;

{ Fill a PropInfo record at the already-reserved offset piPos for property pri
  belonging to ci. The record (RTTI_PROP_SIZE bytes) must be reserved by the
  caller BEFORE calling this: InternStr appends string data to Data[], so any
  interning done here would otherwise land between consecutive records and
  break the runtime's fixed-stride props[i] indexing. }
procedure EmitPropInfo(ci, pri, piPos: Integer);
var tk, kind, tci, eid, strIdx, fIdx, mIdx, procIdx: Integer;
    nm: AnsiString;
begin
  { name }
  nm := TokSliceStr(UPropNOff[pri], UPropNLen[pri]);
  strIdx := InternStr(nm);
  AddDataPtrFix(piPos + 0, Strs[strIdx].Offset);

  { kind from declared type (enum identity overrides the integer fallback) }
  tk := UPropTk[pri];
  if UPropEnumId[pri] >= 0 then kind := RTTI_KIND_ENUM
  else if tk = Ord(tyString) then kind := RTTI_KIND_STRING
  else if tk = Ord(tyClass) then kind := RTTI_KIND_CLASS
  else if tk = Ord(tySet) then kind := RTTI_KIND_SET
  else if tk = Ord(tyRecord) then
  begin
    tci := UPropRec[pri] - REC_UCLASS_BASE;
    if (tci >= 0) and (tci < UClsCount) and 
       (LowerCase(TokSliceStr(UClsNOff[tci], UClsNLen[tci])) = 'tmethod') then
      kind := RTTI_KIND_METHOD
    else
      kind := RTTI_KIND_INT;
  end
  else kind := RTTI_KIND_INT;
  PatchDataU64(piPos + 8, kind);

  { typeRef: class props -> class RTTI; enum props -> enum RTTI }
  if kind = RTTI_KIND_CLASS then
  begin
    tci := UPropRec[pri] - REC_UCLASS_BASE;
    if (tci >= 0) and (tci < UClsCount) and (UClsRTTIOff[tci] >= 0) then
      AddDataPtrFix(piPos + 16, UClsRTTIOff[tci]);
  end
  else if kind = RTTI_KIND_ENUM then
  begin
    eid := UPropEnumId[pri];
    if (eid >= 0) and (EnumTypeRTTIOff[eid] >= 0) then
      AddDataPtrFix(piPos + 16, EnumTypeRTTIOff[eid]);
  end
  else if kind = RTTI_KIND_SET then
  begin
    { typeRef -> element enum RTTI, so streaming can map member names to bits }
    eid := UPropSetEnumId[pri];
    if (eid >= 0) and (EnumTypeRTTIOff[eid] >= 0) then
      AddDataPtrFix(piPos + 16, EnumTypeRTTIOff[eid]);
  end;

  { getter: field (getKind=0, getRef=byte offset) or method (getKind=1, getRef=code) }
  if UPropReadFLen[pri] > 0 then
  begin
    nm := TokSliceStr(UPropReadFOff[pri], UPropReadFLen[pri]);
    fIdx := FindUField(ci, nm);
    PatchDataU64(piPos + 24, 0);
    if fIdx >= 0 then PatchDataU64(piPos + 32, UFldOff_[fIdx]);
  end
  else if UPropReadMLen[pri] > 0 then
  begin
    nm := TokSliceStr(UPropReadMOff[pri], UPropReadMLen[pri]);
    mIdx := FindUMeth(ci, nm);
    PatchDataU64(piPos + 24, 1);
    if mIdx >= 0 then
    begin
      procIdx := UMthProc_[mIdx];
      if procIdx >= 0 then QueueMethCodeFixup(piPos + 32, procIdx);
    end;
  end;

  { setter }
  if UPropWriteFLen[pri] > 0 then
  begin
    nm := TokSliceStr(UPropWriteFOff[pri], UPropWriteFLen[pri]);
    fIdx := FindUField(ci, nm);
    PatchDataU64(piPos + 40, 0);
    if fIdx >= 0 then PatchDataU64(piPos + 48, UFldOff_[fIdx]);
  end
  else if UPropWriteMLen[pri] > 0 then
  begin
    nm := TokSliceStr(UPropWriteMOff[pri], UPropWriteMLen[pri]);
    mIdx := FindUMeth(ci, nm);
    PatchDataU64(piPos + 40, 1);
    if mIdx >= 0 then
    begin
      procIdx := UMthProc_[mIdx];
      if procIdx >= 0 then QueueMethCodeFixup(piPos + 48, procIdx);
    end;
  end;

  { ordType: type-kind hint (size/sign for ordinals) }
  PatchDataU64(piPos + 56, tk);
end;

{ Fill a MethInfo record (RTTI_METH_SIZE bytes) at the already-reserved offset
  miPos for method mi: name, code, arity (Params incl. Self), return type kind,
  and a pointer to an `arity`-long array of Ord(TTypeKind) param kinds (appended
  at the current tail — like the name InternStr, so it does not split the
  reserved record array). The generic native-call trampoline reads arity +
  param kinds to marshal variant args to each param's type. Record must be
  reserved by the caller first. }
procedure EmitMethInfo(mi, miPos: Integer);
var strIdx, procIdx, arity, p, paramOff, flags: Integer;
    nm: AnsiString;
begin
  nm := TokSliceStr(UMthNOff[mi], UMthNLen[mi]);
  strIdx := InternStr(nm);
  AddDataPtrFix(miPos + 0, Strs[strIdx].Offset);
  procIdx := UMthProc_[mi];
  if procIdx >= 0 then QueueMethCodeFixup(miPos + 8, procIdx);
  arity := 0;
  if procIdx >= 0 then
  begin
    arity := Procs[procIdx].ParamCount;
    PatchDataU64(miPos + 16, arity);
    { retKind 0 = no result (a procedure); a function stores its RetType kind, so
      the trampoline boxes a return value only when there is one. }
    if Procs[procIdx].IsFunc then
      PatchDataU64(miPos + 24, Ord(Procs[procIdx].RetType))
    else
      PatchDataU64(miPos + 24, 0);
  end;
  if arity > 0 then
  begin
    { The param block is `arity` KIND words followed by `arity` NAME pointers —
      one block, one pointer, so the MethInfo record itself does not grow and
      neither lib/rtl/typinfo.pas's mirror nor the three stride consumers move
      (project_rtti_method_table_multi_consumer_stride_landmine). A reader that
      only wants kinds reads the first `arity` words exactly as before.

      Names exist because a reflected caller cannot otherwise bind a KEYWORD
      argument: pyeval had the kwarg's name and nothing to match it against, so
      it appended kwargs POSITIONALLY and `w.put(chars=x, index=y)` silently
      swapped them (bug-nilpy-pyeval-fallback-still-binds-host-kwargs-by-position).
      Reserve the whole block BEFORE interning any name — InternStr appends to
      Data[], and interning mid-reservation would split the array. }
    paramOff := DataLen;
    DataPutZeros(arity * 8 * 2);
    for p := 0 to arity - 1 do
      PatchDataU64(paramOff + p * 8, Ord(Procs[procIdx].Params[p].TypeKind));
    for p := 0 to arity - 1 do
    begin
      strIdx := InternStr(Procs[procIdx].Params[p].Name);
      AddDataPtrFix(paramOff + (arity + p) * 8, Strs[strIdx].Offset);
    end;
    AddDataPtrFix(miPos + 32, paramOff);
  end;
  flags := 0;
  if UMthPub[mi] = 1 then flags := RTTI_METH_FLAG_PUBLISHED;
  if (procIdx >= 0) and (ProcPyStarIdx[procIdx] >= 0) then
    flags := flags or ((ProcPyStarIdx[procIdx] + 1) shl RTTI_METH_STARIDX_SHIFT);
  if flags <> 0 then PatchDataU64(miPos + 40, flags);
end;

{ Fill a FieldInfo record (RTTI_FIELD_SIZE bytes) at fiPos for field fi:
  name ptr, byte offset, type kind, record id (for class/record/aggregate
  fields; REC_NONE otherwise), and a flags word whose bit0 marks a PUBLISHED
  field (the streamer wires a named child into its published field; reflection
  get/set-by-name ignores the bit and reaches any field). Record must be
  reserved by the caller first (InternStr appends to Data[]). }
procedure EmitFieldInfo(fi, fiPos: Integer);
var strIdx, flags: Integer; nm: AnsiString;
begin
  nm := TokSliceStr(UFldNOff[fi], UFldNLen[fi]);
  strIdx := InternStr(nm);
  AddDataPtrFix(fiPos + 0, Strs[strIdx].Offset);
  PatchDataU64(fiPos + 8, UFldOff_[fi]);
  PatchDataU64(fiPos + 16, UFldTk[fi]);
  PatchDataU64(fiPos + 24, UFldRec_[fi]);
  flags := 0;
  if UFldPub[fi] = 1 then flags := flags or RTTI_FIELD_FLAG_PUBLISHED;
  PatchDataU64(fiPos + 32, flags);
end;

{ Emit one PYSIG_SIZE signature record per NilPy `def`, and record its Data[]
  offset in ProcSigOff so a callable value can point at it.

  Static data, deliberately: the record is never allocated and never freed, so a
  variant slot holding its address still owns nothing and the non-owning lifetime
  every callable-bearing tag already had is preserved BY CONSTRUCTION rather than
  by remembering to. That property is why this shape was chosen; see
  feature-n-a-callable-value-carries-its-signature-type.

  Self is excluded from both counts because the user-space call site counts
  user-space arguments -- a method's receiver is supplied by the dispatcher, and
  a plain def has no Self at all. Params[0] is Self exactly when the proc is a
  method, which ProcIsMethod_ answers.

  The defaults array is RESERVED here and left zero. Populating it needs every
  defaulted parameter to have a hidden global holding its def-time value, which
  today exists only for NON-constant defaults (ProcParamDefaultSym); giving the
  constant ones one too is the next increment. Reserved rather than omitted so
  the record layout is final and no consumer has to cope with two shapes. }
function PyProcIsNilPyDef(pi: Integer): Boolean;
{ A def the NilPy frontend parsed -- the MAIN module's own (ProcUnitIdx < 0) or
  an IMPORTED .npy module's. NOT a Pascal routine from pylib/pyeval/the RTL,
  which share the same unit-index space and would otherwise get a record each:
  measured +170 KB of .data on the compiler's own self-build for records nothing
  can reach.
  Imported defs were skipped by the first cut, and the resolver's hard error is
  what caught it -- `describe` reached as a callable value from another module
  had a sentinel and no record. Their defaults matter exactly as much as the
  main module's, so the test is "did NilPy parse it", not "is it local". }
var k: Integer;
begin
  Result := True;
  if ProcUnitIdx[pi] < 0 then Exit;
  for k := 0 to PyModUnitCount - 1 do
    if PyModUnitIdx[k] = ProcUnitIdx[pi] then Exit;
  Result := False;
end;

procedure EmitPySignatures;
var pi, k, nUser, reqN, dfltOff, firstUser, slot, pend, namesOff: Integer;
begin
  for pi := 0 to MAX_PROCS - 1 do ProcSigOff[pi] := -1;
  for pi := 0 to MAX_PROCS - 1 do ProcSigDfltOff[pi] := -1;
  { NilPy compiles only. Without this a PASCAL program emits a record per
    main-program proc: measured +170 KB of .data on the compiler's own
    self-build, for records nothing can ever reach -- a callable value is a
    NilPy construct. The caller's guard excludes C/BASIC/Rust/... but NOT
    Pascal, so the test has to be here. }
  if not isNilPy then Exit;
  { Where an ORPHANED def-time store lands -- see PyDfltScratchOff in defs.inc.
    Emitted unconditionally so the address exists even in a module with no
    unbakeable defaults; 16 bytes is one variant. }
  { PXXDBG=n.procs: the whole proc table, index -> name/arity/unit. The IR and
    AST dumps print a callee as a bare `call a=1508`, and mapping that back by
    hand is how an hour went into a dispatcher that turned out not to be the one
    the call site used. }
  if PxxDbgEnabled('n.procs') then
    for pi := 0 to ProcCount - 1 do
      WriteLn('PXXDBG n.procs pi=', pi, ' name=', Procs[pi].Name,
              ' nparams=', Procs[pi].ParamCount, ' unit=', ProcUnitIdx[pi]);
  PyDfltScratchOff := DataLen;
  DataPutZeros(48);
  for pi := 0 to ProcCount - 1 do
  begin
    { NilPy defs only: a routine declared by the MAIN PROGRAM of a NilPy
      compile. Pascal RTL/pylib routines (ProcUnitIdx >= 0) are never reached
      through a NilPy callable value, and a record for all 2900 procs would be
      pure data bloat.

      NOT ProcPyDefTok, which is what this first used and which was WRONG:
      that array holds the token index of a def that SHADOWS A BUILTIN, and 0
      means "no position recorded" -- so it is overloaded with "position 0" and
      silently dropped any def that is the module's FIRST statement. Measured:
      `def g(...)` at the top of a file produced no record at all, while the
      same def one line below a `print` produced one. A def whose meaning
      depends on where it stands is a different question from whether it IS a
      def, and this pass is asking the second one. }
    if not PyProcIsNilPyDef(pi) then Continue;
    { Is pi a METHOD (Params[0] = Self)? There is no per-proc flag: every other
      site is handed `firstParam` by a caller that knows from context, and this
      pass has no such caller. UMthProc_ is the post-parse source of truth, so
      ask it. Scanned only for NilPy defs, so the cost is defs x methods once. }
    firstUser := 0;
    for k := 0 to UMthCount - 1 do
      if UMthProc_[k] = pi then
      begin
        firstUser := 1;
        Break;
      end;
    nUser := Procs[pi].ParamCount - firstUser;
    if nUser < 0 then nUser := 0;
    reqN := 0;
    for k := firstUser to Procs[pi].ParamCount - 1 do
      if not ProcParamHasDefault[pi * MAX_PROC_PARAMS + k] then Inc(reqN);

    ProcSigOff[pi] := DataLen;
    if PxxDbgEnabled('n.sig') then
      WriteLn('PXXDBG n.sig pi=', pi, ' name=', Procs[pi].Name,
              ' paramCount=', Procs[pi].ParamCount, ' firstUser=', firstUser,
              ' nUser=', nUser, ' reqN=', reqN, ' off=', DataLen);
    DataPutZeros(PYSIG_SIZE);
    QueueMethCodeFixup(ProcSigOff[pi] + PYSIG_OFF_CODE, pi);
    PatchDataU64(ProcSigOff[pi] + PYSIG_OFF_REQN, reqN);
    PatchDataU64(ProcSigOff[pi] + PYSIG_OFF_TOTN, nUser);
    if ProcPyStarIdx[pi] >= 0 then
      PatchDataU64(ProcSigOff[pi] + PYSIG_OFF_STAR, ProcPyStarIdx[pi] + 1);
    if nUser > 0 then
    begin
      dfltOff := DataLen;
      ProcSigDfltOff[pi] := dfltOff;
      { 16 bytes per slot: each is a VARIANT {VType, Payload}, not a pointer. }
      DataPutZeros(nUser * 16);
      AddDataPtrFix(ProcSigOff[pi] + PYSIG_OFF_DFLTS, dfltOff);
      { Mark every slot UNFILLED first, then bake over the ones we can settle
        statically. Zero would read as VT_EMPTY, which is None -- see
        PYSIG_DFLT_UNSET. }
      for k := 0 to nUser - 1 do
        PatchDataU64(dfltOff + k * 16, PYSIG_DFLT_UNSET);
      for k := firstUser to Procs[pi].ParamCount - 1 do
      begin
        if not ProcParamHasDefault[pi * MAX_PROC_PARAMS + k] then Continue;
        slot := dfltOff + (k - firstUser) * 16;
        { A NON-constant default already has a hidden global carrying its
          def-time value (ProcParamDefaultSym); it cannot be baked and is left
          UNSET for the def-time store to fill. Same for a STRING: VT_STRING's
          payload is a MANAGED AnsiString ref, and baking a static pointer into
          a managed slot is how refcount corruption starts. }
        if ProcParamDefaultSym[pi * MAX_PROC_PARAMS + k] >= 0 then
        begin
          { Point the def-time store that PyEvalParamDefault queued at THIS
            slot. The store was built while the header was parsed, before this
            Proc existed, so it names the hidden global instead and the pairing
            is made here -- after every registration site has settled. }
          pend := PyDfltPendFor(ProcParamDefaultGName[pi * MAX_PROC_PARAMS + k]);
          PyDfltPendOff[pend] := slot;
          if PxxDbgEnabled('n.sig') then
            WriteLn('PXXDBG n.sig dflt ', Procs[pi].Name, '.',
                    Procs[pi].Params[k].Name, ' pend=', pend,
                    ' gname=', ProcParamDefaultGName[pi * MAX_PROC_PARAMS + k],
                    ' slot=', slot);
          Continue;
        end;
        if ProcParamDefaultIsStr[pi * MAX_PROC_PARAMS + k] then Continue;
        if ProcParamDefaultIsSet[pi * MAX_PROC_PARAMS + k] then Continue;
        if ProcParamDefaultIsNone[pi * MAX_PROC_PARAMS + k] then
          PatchDataU64(slot, VT_EMPTY)             { None IS VT_EMPTY }
        else if ProcParamDefaultIsBool[pi * MAX_PROC_PARAMS + k] then
        begin
          PatchDataU64(slot, VT_BOOL);
          PatchDataU64(slot + 8, ProcParamDefaultVal[pi * MAX_PROC_PARAMS + k]);
        end
        else if ProcParamDefaultIsFloat[pi * MAX_PROC_PARAMS + k] then
        begin
          { DefaultVal already holds the IEEE-754 bits, as a float TOKEN does. }
          PatchDataU64(slot, VT_DOUBLE);
          PatchDataU64(slot + 8, ProcParamDefaultVal[pi * MAX_PROC_PARAMS + k]);
        end
        else
        begin
          PatchDataU64(slot, VT_INT64);
          PatchDataU64(slot + 8, ProcParamDefaultVal[pi * MAX_PROC_PARAMS + k]);
        end;
      end;
    end;
    { The PARAMETER NAMES, in the same record rather than a second mechanism:
      TotN pointers, then the NUL-terminated names themselves. A keyword
      argument arriving through a callable value has nothing else to match
      against -- the box carries a code address, and the names are the only
      thing that turns `final=True` into a parameter position at run time.
      Emitted here so a proc with nUser = 0 simply leaves the field nil, which
      the dispatcher reads as "no names known" and treats exactly as it did
      before they existed. }
    if nUser > 0 then
    begin
      namesOff := DataLen;
      DataPutZeros(nUser * 8);
      AddDataPtrFix(ProcSigOff[pi] + PYSIG_OFF_NAMES, namesOff);
      for k := firstUser to Procs[pi].ParamCount - 1 do
      begin
        AddDataPtrFix(namesOff + (k - firstUser) * 8, DataLen);
        DataPutZ(Procs[pi].Params[k].Name);
      end;
    end;
  end;
end;

procedure EmitRTTI;
var ci, i, j, k, base, cnt, hdr, strIdx, etid: Integer;
    propCount, methCount, fieldCount, ifaceCount, firstOff, entryOff: Integer;
    regEntries, entryPos, tobjCi: Integer;
    nm: AnsiString;
begin
  RTTIRegistryOff := -1;
  RTTIRegistryCount := 0;
  for ci := 0 to MAX_UCLASS - 1 do UClsRTTIOff[ci] := -1;
  for ci := 0 to MAX_UCLASS - 1 do UClsLayoutOff[ci] := -1;

  { Enum type RTTI first, so prop typeRefs can point at it. }
  for etid := 0 to EnumTypeCount - 1 do
    EnumTypeRTTIOff[etid] := EmitEnumRTTI(etid);

  if UClsCount > 0 then
  begin
    { Pass 1: reserve a header per class so forward type refs resolve.

      EVERY class gets one, not just the published/guided ones. The header is where
      the class NAME lives, and ClassName has to answer for any class at all --
      fpcunit's `GetN(C: TClass)` is handed classes that publish nothing. The
      published-only gate used to make ClassName a coin flip: it worked on a class
      that happened to publish something and returned '' on one that did not.

      Unpublished classes just get zero counts and no prop/meth arrays, so the cost
      is one RTTI_CLS_SIZE header plus an interned name per class. }
    for ci := 0 to UClsCount - 1 do
    begin
      if not UClsIsRecord[ci] then
      begin
        UClsRTTIOff[ci] := DataLen;
        DataPutZeros(RTTI_CLS_SIZE);
      end;
    end;

    { Pass 2: fill headers + emit prop/meth arrays. }
    for ci := 0 to UClsCount - 1 do
    begin
      if UClsRTTIOff[ci] < 0 then continue;
      hdr := UClsRTTIOff[ci];

      { name }
      nm := TokSliceStr(UClsNOff[ci], UClsNLen[ci]);
      strIdx := InternStr(nm);
      AddDataPtrFix(hdr + 0, Strs[strIdx].Offset);

      { parent RTTI. A ROOT class (`class ... end`, or the explicit
        `class(TObject)` spelling, which RegisterBuiltinTObject deliberately
        leaves at parentCi = -1 so no VMT relocates) still descends from TObject
        in the LANGUAGE, and this chain is what answers that question at run
        time. Leaving it nil made `b is TObject` and `TBase.InheritsFrom(TObject)`
        answer FALSE — silently, and for every class in the program — while
        `TDer.InheritsFrom(TBase)` was right, because only the implicit root link
        was missing. Linking it HERE costs nothing: the blob's parent word is
        RTTI, not layout, so the implicit-root VMT model is untouched.
        Interfaces are excluded (an interface does not descend from TObject),
        and TObject itself keeps a nil parent, which is what terminates the walk.
        bug-p-a-class-does-not-inherit-from-tobject-at-run-time }
      if (UClsParent[ci] >= 0) and (UClsRTTIOff[UClsParent[ci]] >= 0) then
        AddDataPtrFix(hdr + 8, UClsRTTIOff[UClsParent[ci]])
      else if (UClsParent[ci] < 0) and (not UClsIsInterface[ci]) then
      begin
        tobjCi := FindUClass('TObject');
        if (tobjCi >= 0) and (tobjCi <> ci) and (UClsRTTIOff[tobjCi] >= 0) then
          AddDataPtrFix(hdr + 8, UClsRTTIOff[tobjCi]);
      end;

      { instance size }
      PatchDataU64(hdr + 16, UClsSize_[ci]);

      { VMT pointer }
      if UClsVMTOffset[ci] >= 0 then
        AddDataPtrFix(hdr + 24, UClsVMTOffset[ci]);

      { ...and the BACKLINK: the word reserved immediately before the VMT points at
        this blob, so an INSTANCE can reach its class RTTI as [[instance+0] - 8].
        The blob->VMT pointer above only goes one way, which is no use to code
        holding an object. This is what published-method reflection dispatches on. }
      if UClsVMTOffset[ci] >= 8 then
        AddDataPtrFix(UClsVMTOffset[ci] - 8, hdr);

      { published properties (own). Reserve the whole array contiguously BEFORE
        filling: EmitPropInfo interns names (which append to Data[]), so records
        must be laid out first or the runtime's props[i] stride breaks. }
      base := UClsPBase[ci]; cnt := UClsPCount[ci];
      propCount := 0;
      for i := 0 to cnt - 1 do
        if UPropPub[base + i] = 1 then Inc(propCount);
      firstOff := -1;
      if propCount > 0 then
      begin
        firstOff := DataLen;
        DataPutZeros(propCount * RTTI_PROP_SIZE);
        k := 0;
        for i := 0 to cnt - 1 do
          if UPropPub[base + i] = 1 then
          begin
            EmitPropInfo(ci, base + i, firstOff + k * RTTI_PROP_SIZE);
            Inc(k);
          end;
      end;
      PatchDataU64(hdr + 32, propCount);
      if propCount > 0 then AddDataPtrFix(hdr + 40, firstOff);

      { ALL methods (own) — same contiguous-reserve-then-fill rule. Every method
        is emitted (not just published) so invoke-by-name reaches any class,
        including NilPy-lowered ones whose methods publish nothing, and the
        trampoline gets each method's signature (feature-lib-pyexec host bridge). }
      base := UClsMBase[ci]; cnt := UClsMCount[ci];
      methCount := cnt;
      firstOff := -1;
      if methCount > 0 then
      begin
        firstOff := DataLen;
        DataPutZeros(methCount * RTTI_METH_SIZE);
        for i := 0 to cnt - 1 do
          EmitMethInfo(base + i, firstOff + i * RTTI_METH_SIZE);
      end;
      PatchDataU64(hdr + 48, methCount);
      if methCount > 0 then AddDataPtrFix(hdr + 56, firstOff);

      { ALL fields (own) — same contiguous-reserve-then-fill rule. Every field
        is emitted (not just published) so field get/set by name reflects any
        class, including NilPy-lowered ones whose fields publish nothing
        (feature-rtti-field-reflection). The per-field flags word keeps the
        published bit, so the streamer still filters to published fields. }
      base := UClsFBase[ci]; cnt := UClsFCount[ci];
      fieldCount := cnt;
      firstOff := -1;
      if fieldCount > 0 then
      begin
        firstOff := DataLen;
        DataPutZeros(fieldCount * RTTI_FIELD_SIZE);
        for i := 0 to cnt - 1 do
          EmitFieldInfo(base + i, firstOff + i * RTTI_FIELD_SIZE);
      end;
      PatchDataU64(hdr + 64, fieldCount);
      if fieldCount > 0 then AddDataPtrFix(hdr + 72, firstOff);

      { Interface table (OWN entries; GetInterface walks the parent chain itself, as
        it does for methods). One 24-byte entry per implemented interface that
        carries a GUID: the 16 raw GUID bytes inline, then a pointer to that
        (class, interface) IMT. This is what makes a GUID lookup possible at all —
        the IMTs already existed, but nothing keyed them by GUID.

        Same contiguous-reserve-then-fill discipline as the prop/meth/field arrays:
        the entries must be laid out before anything else appends to Data[], or the
        runtime's entry[i] stride breaks. }
      { EVERY implemented interface gets an entry, not just the GUID'd ones: the
        interface-call path resolves an interface value's IMT from this table by
        interface ID at run time, which is what lets an interface value be a
        single instance pointer. A GUID-less (CORBA) interface stores a zero GUID
        — it simply never matches a GetInterface lookup, which only ever runs
        with a real IID. }
      ifaceCount := 0;
      for i := 0 to IMTCount - 1 do
        if IMTClass[i] = ci then Inc(ifaceCount);
      firstOff := -1;
      if ifaceCount > 0 then
      begin
        firstOff := DataLen;
        DataPutZeros(ifaceCount * RTTI_IFACE_SIZE);
        k := 0;
        for i := 0 to IMTCount - 1 do
          if IMTClass[i] = ci then
          begin
            entryOff := firstOff + k * RTTI_IFACE_SIZE;
            if UClsHasGuid[IMTIntf[i]] then
              for j := 0 to 15 do
                Data[entryOff + j] := UClsGuidB[IMTIntf[i] * 16 + j];
            AddDataPtrFix(entryOff + 16, IMTOff[i]);
            PatchDataU64(entryOff + 24, IMTIntf[i]);   { interface id = its class index }
            Inc(k);
          end;
      end;
      PatchDataU64(hdr + 80, ifaceCount);
      if ifaceCount > 0 then AddDataPtrFix(hdr + 88, firstOff);
    end;
  end;

  EmitLayoutRTTI;

  if UClsCount > 0 then
  begin
    { Registry: count slot followed by (name ptr, rtti ptr) pairs. Only published
      CLASSES belong here — managed value records also carry a UClsRTTIOff (their
      layout descriptor from EmitLayoutRTTI), but that header begins with a Kind
      word, not a name pointer, so including a record would both inflate the
      count and make the runtime read a garbage name. Exclude records, matching
      the class-RTTI Pass-1 predicate above. }
    regEntries := 0;
    for ci := 0 to UClsCount - 1 do
      if (UClsRTTIOff[ci] >= 0) and ClassIsStreamable(ci) then Inc(regEntries);
    if regEntries > 0 then
    begin
      RTTIRegistryOff := DataLen;
      RTTIRegistryCount := regEntries;
      DataPutZeros(8);                       { count slot }
      PatchDataU64(RTTIRegistryOff, regEntries);
      for ci := 0 to UClsCount - 1 do
      begin
        if (UClsRTTIOff[ci] < 0) or (not ClassIsStreamable(ci)) then continue;
        entryPos := DataLen;
        DataPutZeros(16);
        nm := TokSliceStr(UClsNOff[ci], UClsNLen[ci]);
        strIdx := InternStr(nm);
        AddDataPtrFix(entryPos + 0, Strs[strIdx].Offset);
        AddDataPtrFix(entryPos + 8, UClsRTTIOff[ci]);
      end;
    end;
  end;
end;

{ Map pxx's internal TTypeKind onto FPC's TTypeKind ORDINAL (typinfo.pas
  declares the same 30-member enum, in FPC's own declared order, purely so a
  vendor source doing `array[TTypeKind] of X` or a stray numeric comparison
  keeps working -- feature-pascal-corpus-generics settled that no BYTE-LAYOUT
  parity is needed, but the ordinal values cost nothing to keep faithful and
  the project default is FPC-faithful where it's free (see
  devdocs/progress: FPC-faithful, lax behind --strict-*). Widening this table
  to Extended-precision floats or Unicode variants can wait for a real corpus
  need. }
function PxxTkToFPCKind(tk: Integer): Integer;
begin
  case tk of
    Ord(tyInteger), Ord(tyInt8), Ord(tyUInt8), Ord(tyInt16), Ord(tyUInt16),
    Ord(tyInt32), Ord(tyUInt32), Ord(tyNativeInt), Ord(tyNativeUInt),
    Ord(tyPromoInt32):
      Result := 1;                                        { tkInteger }
    Ord(tyChar): Result := 2;                              { tkChar }
    Ord(tySingle), Ord(tyDouble), Ord(tyExtended): Result := 4; { tkFloat }
    Ord(tySet): Result := 5;                               { tkSet }
    Ord(tyShortString), Ord(tyFixedString), Ord(tyString): Result := 7; { tkSString }
    Ord(tyAnsiString): Result := 9;                        { tkAString }
    Ord(tyVariant): Result := 11;                          { tkVariant }
    Ord(tyRecord): Result := 13;                           { tkRecord }
    Ord(tyClass): Result := 15;                            { tkClass }
    Ord(tyBoolean): Result := 18;                          { tkBool }
    Ord(tyInt64), Ord(tyPromoInt64): Result := 19;         { tkInt64 }
    Ord(tyUInt64): Result := 20;                           { tkQWord }
    Ord(tyPointer): Result := 29;                          { tkPointer }
    else Result := 0;                                      { tkUnknown }
  end;
end;

{ Display name for an ordinal/scalar TypeInfoReq -- purely cosmetic (GetTypeName
  in the facade), so one canonical spelling per pxx tk is fine even though
  several source names alias to it (Integer/LongInt both -> tyInteger, etc). }
function TypeInfoOrdName(tk: Integer): AnsiString;
begin
  case tk of
    Ord(tyInteger):     Result := 'Integer';
    Ord(tyInt8):        Result := 'ShortInt';
    Ord(tyUInt8):       Result := 'Byte';
    Ord(tyInt16):       Result := 'SmallInt';
    Ord(tyUInt16):      Result := 'Word';
    Ord(tyInt32):       Result := 'LongInt';
    Ord(tyUInt32):      Result := 'LongWord';
    Ord(tyNativeInt):   Result := 'NativeInt';
    Ord(tyNativeUInt):  Result := 'NativeUInt';
    Ord(tyInt64):       Result := 'Int64';
    Ord(tyUInt64):      Result := 'QWord';
    Ord(tyBoolean):     Result := 'Boolean';
    Ord(tyChar):        Result := 'Char';
    Ord(tySingle):      Result := 'Single';
    Ord(tyDouble):      Result := 'Double';
    Ord(tyExtended):    Result := 'Extended';
    Ord(tySet):         Result := 'Set';
    Ord(tyVariant):     Result := 'Variant';
    Ord(tyAnsiString):  Result := 'AnsiString';
    Ord(tyShortString), Ord(tyFixedString), Ord(tyString): Result := 'ShortString';
    Ord(tyPointer):     Result := 'Pointer';
    Ord(tyPromoInt32), Ord(tyPromoInt64): Result := 'Integer';
    else Result := '';
  end;
end;

{ Build the uniform "PTypeInfo" header -- {Kind:Int64; NamePtr:PString;
  DataPtr:Pointer}, 24 bytes on every target -- for every widened TypeInfo(T)
  request collected during parsing (RegisterTypeInfoReq). Runs right after
  EmitRTTI so class/record requests can point DataPtr at the ALREADY-emitted
  UClsRTTIOff[ci] blob (the same TClassRTTI/layout-descriptor typinfo.pas
  already reads). Enum TypeInfo() does not go through here at all -- see the
  pasparser_*.inc comment at the TypeInfo() call site. }
procedure EmitTypeInfoHeaders;
var i, hdr, strIdx, ci, kind: Integer; nm: AnsiString;
begin
  for i := 0 to TypeInfoReqCount - 1 do
  begin
    hdr := DataLen;
    DataPutZeros(24);
    if TypeInfoReqCat[i] = TYPEINFO_REQ_CAT_ORD then
    begin
      kind := PxxTkToFPCKind(TypeInfoReqKey[i]);
      PatchDataU64(hdr + 0, kind);
      nm := TypeInfoOrdName(TypeInfoReqKey[i]);
      if nm <> '' then
      begin
        strIdx := InternStr(nm);
        AddDataPtrFix(hdr + 8, Strs[strIdx].Offset);
      end;
      { DataPtr (hdr+16) stays nil: no extra TTypeData descriptor for scalars yet
        (min/max/ordtype) -- add if/when a corpus target actually needs it. }
    end
    else if TypeInfoReqCat[i] = TYPEINFO_REQ_CAT_CLASS then
    begin
      ci := TypeInfoReqKey[i];
      PatchDataU64(hdr + 0, 15); { tkClass }
      nm := TokSliceStr(UClsNOff[ci], UClsNLen[ci]);
      strIdx := InternStr(nm);
      AddDataPtrFix(hdr + 8, Strs[strIdx].Offset);
      if UClsRTTIOff[ci] >= 0 then
        AddDataPtrFix(hdr + 16, UClsRTTIOff[ci]);   { -> TClassRTTI, same blob AN_CLASSREF points at }
    end
    else if TypeInfoReqCat[i] = TYPEINFO_REQ_CAT_ALIAS then
    begin
      { A named type from the alias table. Kind comes from what the alias
        DEFINES, because AliasTk alone cannot say it: a subrange and a
        string[N] both carry an ordinary scalar tk, and only AliasIsSub /
        AliasStrCap distinguish them from the plain rename that shares it.
        Measured against FPC 3.2.2 — see TYPEINFO_REQ_CAT_ALIAS in defs.inc
        for the name rule and why a plain rename does NOT keep its own name. }
      ci := TypeInfoReqKey[i];
      if AliasProcSig[ci] >= 0 then
      begin
        { Both shapes carry a signature; only AliasTk separates them. A method
          pointer is a 16-byte {Code,Data} record (RegisterMethodPtrTypeAlias
          sets tyRecord), a plain procedural type is a bare code address
          (tyPointer). Measured: FPC 3.2.2 says 6 for `procedure(x: Integer) of
          object` and 23 for `procedure(x: Integer)` / `function(x): Integer`. }
        if AliasTk[ci] = Ord(tyRecord) then kind := 6  { tkMethod }
        else kind := 23;                               { tkProcVar }
      end
      else if AliasStrCap[ci] > 0 then kind := 7      { tkSString }
      else kind := PxxTkToFPCKind(AliasTk[ci]);       { subrange -> 1, set -> 5, … }
      PatchDataU64(hdr + 0, kind);
      if (AliasProcSig[ci] >= 0) or (AliasStrCap[ci] > 0) or AliasIsSub[ci] or
         (AliasTk[ci] = Ord(tySet)) then
        nm := GetSliceName(AliasNOff[ci], AliasNLen[ci])   { defines a type: own name }
      else
        nm := TypeInfoOrdName(AliasTk[ci]);                { plain rename: pass through }
      if nm <> '' then
      begin
        strIdx := InternStr(nm);
        AddDataPtrFix(hdr + 8, Strs[strIdx].Offset);
      end;
      { DataPtr stays nil, as for the scalars: no TTypeData descriptor yet.
        The subrange's bounds live in AliasSubLo/Hi and the set's element enum
        in AliasElemTk, so they are recoverable when a consumer needs them. }
    end
    else if TypeInfoReqCat[i] = TYPEINFO_REQ_CAT_ARRAY then
    begin
      { A named array type. ArrTypeIsDyn is the whole decision — measured
        against FPC 3.2.2: `TArr = array[0..3] of Integer` is 12 tkArray,
        `TDyn = array of Integer` is 21 tkDynArray, and both report their own
        name. }
      ci := TypeInfoReqKey[i];
      if ArrTypeIsDyn[ci] then kind := 21 else kind := 12;
      PatchDataU64(hdr + 0, kind);
      nm := ArrTypeName[ci];
      if nm <> '' then
      begin
        strIdx := InternStr(nm);
        AddDataPtrFix(hdr + 8, Strs[strIdx].Offset);
      end;
      { DataPtr stays nil: no TTypeData yet. Element type and bounds are in
        ArrTypeElemTk / ArrTypeDimLo / ArrTypeDimSpan when one is needed. }
    end
    else if TypeInfoReqCat[i] = TYPEINFO_REQ_CAT_RECORD then
    begin
      ci := TypeInfoReqKey[i];
      PatchDataU64(hdr + 0, 13); { tkRecord }
      nm := TokSliceStr(UClsNOff[ci], UClsNLen[ci]);
      strIdx := InternStr(nm);
      AddDataPtrFix(hdr + 8, Strs[strIdx].Offset);
      if UClsRTTIOff[ci] >= 0 then
        AddDataPtrFix(hdr + 16, UClsRTTIOff[ci]);   { -> the record's layout descriptor, if it has one }
    end;
    TypeInfoReqOff[i] := hdr;
  end;
end;

procedure EmitLayoutRTTI;
var
  ci, i, fi, base, cnt, mCount, dCount, mHdr, dynDescOff: Integer;
  hdr, subCi, arrCount, mKind, typeRef: Integer;
  depth, baseKind, elSize, baseTypeRef, k, dynIdx, cCi: Integer;
  targetPtrSize: Integer;



begin
  targetPtrSize := TARGET_PTR_SIZE;

  { Pass 1: pre-allocate RTTI offsets in Data[] }
  for ci := 0 to UClsCount - 1 do
  begin
    if UClsIsRecord[ci] and RecordHasManagedFields(ci + REC_UCLASS_BASE) then
    begin
      UClsRTTIOff[ci] := DataLen;
      mCount := 0;
      dCount := 0;
      base := UClsFBase[ci];
      cnt := UClsFCount[ci];
      for i := 0 to cnt - 1 do
      begin
        fi := base + i;
        if FieldIsManaged(fi) then
        begin
          Inc(mCount);
          if UFldIsArray[fi] and (UFldArrLen[fi] = -1) then
            Inc(dCount);
        end;
      end;
      DataPutZeros(12 + mCount * 16 + dCount * 20);
    end;
  end;

  { Pass 1b: CLASS layout descriptors — same record-descriptor format (so
    PXXRecordRelease consumes it for kinds 1-3) plus member kind 4 = COM
    interface field. Fields are collected over the WHOLE parent chain (UFldOff_
    is the absolute instance offset, so one flat descriptor covers inherited
    members). Backlinked at [VMT-16]; PXXClassFinalize dispatches on the
    instance's RUNTIME class (bug-a-class-managed-fields-not-finalized). }
  for ci := 0 to UClsCount - 1 do
  begin
    if (not UClsIsRecord[ci]) and (not UClsIsInterface[ci]) then
    begin
      mCount := 0;
      dCount := 0;
      cCi := ci;
      while cCi >= 0 do
      begin
        base := UClsFBase[cCi];
        cnt := UClsFCount[cCi];
        for i := 0 to cnt - 1 do
        begin
          fi := base + i;
          if ClassFieldNeedsFinal(fi) then
          begin
            Inc(mCount);
            if UFldIsArray[fi] and (UFldArrLen[fi] = -1) then
              Inc(dCount);
          end;
        end;
        cCi := UClsParent[cCi];
      end;
      if mCount > 0 then
      begin
        UClsLayoutOff[ci] := DataLen;
        DataPutZeros(12 + mCount * 16 + dCount * 20);
      end;
    end;
  end;

  { Pass 2: fill descriptors }
  for ci := 0 to UClsCount - 1 do
  begin
    if UClsIsRecord[ci] and RecordHasManagedFields(ci + REC_UCLASS_BASE) then
    begin
      hdr := UClsRTTIOff[ci];
      PatchDataI32(hdr + 0, 1); { Kind = 1 (Record) }
      PatchDataI32(hdr + 4, UClsSize_[ci]); { Size }

      base := UClsFBase[ci];
      cnt := UClsFCount[ci];
      mCount := RecordManagedFieldCount(ci);

      k := 0;
      dynIdx := 0;
      for i := 0 to cnt - 1 do
      begin
        fi := base + i;
        if FieldIsManaged(fi) then
        begin
          mHdr := hdr + 12 + k * 16;
          PatchDataI32(mHdr + 0, UFldOff_[fi]); { Offset }

          if UFldTk[fi] = Ord(tyAnsiString) then
            mKind := 1
          else if UFldIsArray[fi] and (UFldArrLen[fi] = -1) then
            mKind := 2
          else
            mKind := 3;
          PatchDataI32(mHdr + 4, mKind);

          if UFldIsArray[fi] then
          begin
            if UFldArrLen[fi] = -1 then
              arrCount := 1
            else
              arrCount := UFldArrLen[fi];
          end
          else
            arrCount := 1;
          PatchDataI32(mHdr + 8, arrCount);

          typeRef := 0;
          if mKind = 2 then
          begin
            dynDescOff := hdr + 12 + mCount * 16 + dynIdx * 20;
            typeRef := dynDescOff - (mHdr + 12);

            PatchDataI32(dynDescOff + 0, 2); { Kind = 2 (DynArray) }

            depth := UFldDynDepth[fi];
            if UFldTk[fi] = Ord(tyAnsiString) then
              baseKind := 1
            else if (UFldTk[fi] = Ord(tyRecord)) and RecordHasManagedFields(UFldRec_[fi]) then
              baseKind := 3
            else
              baseKind := 0;

            if depth > 1 then
              elSize := targetPtrSize
            else
            begin
              if baseKind = 1 then
                elSize := targetPtrSize
              else if baseKind = 3 then
                elSize := UClsSize_[UFldRec_[fi] - REC_UCLASS_BASE]
              else
                elSize := TypeSize(IntToTypeKind(UFldTk[fi]));
            end;
            PatchDataI32(dynDescOff + 4, elSize);
            PatchDataI32(dynDescOff + 8, depth);
            PatchDataI32(dynDescOff + 12, baseKind);

            baseTypeRef := 0;
            if baseKind = 3 then
            begin
              subCi := UFldRec_[fi] - REC_UCLASS_BASE;
              if (subCi >= 0) and (subCi < UClsCount) and (UClsRTTIOff[subCi] >= 0) then
                baseTypeRef := UClsRTTIOff[subCi] - (dynDescOff + 16);
            end;
            PatchDataI32(dynDescOff + 16, baseTypeRef);

            Inc(dynIdx);
          end
          else if mKind = 3 then
          begin
            subCi := UFldRec_[fi] - REC_UCLASS_BASE;
            if (subCi >= 0) and (subCi < UClsCount) and (UClsRTTIOff[subCi] >= 0) then
              typeRef := UClsRTTIOff[subCi] - (mHdr + 12);
          end;
          PatchDataI32(mHdr + 12, typeRef);

          Inc(k);
        end;
      end;
      PatchDataI32(hdr + 8, k); { MemberCount }
    end;
  end;

  { Pass 2b: fill CLASS layout descriptors and patch the [VMT-16] backlink. }
  for ci := 0 to UClsCount - 1 do
  begin
    if UClsLayoutOff[ci] >= 0 then
    begin
      hdr := UClsLayoutOff[ci];
      PatchDataI32(hdr + 0, 1); { Kind = 1 (Record-format layout) }
      PatchDataI32(hdr + 4, UClsSize_[ci]); { Size }

      { first count managed members over the chain (dyn sub-desc area base) }
      mCount := 0;
      cCi := ci;
      while cCi >= 0 do
      begin
        base := UClsFBase[cCi];
        cnt := UClsFCount[cCi];
        for i := 0 to cnt - 1 do
          if ClassFieldNeedsFinal(base + i) then Inc(mCount);
        cCi := UClsParent[cCi];
      end;

      k := 0;
      dynIdx := 0;
      cCi := ci;
      while cCi >= 0 do
      begin
        base := UClsFBase[cCi];
        cnt := UClsFCount[cCi];
        for i := 0 to cnt - 1 do
        begin
          fi := base + i;
          if ClassFieldNeedsFinal(fi) then
          begin
            mHdr := hdr + 12 + k * 16;
            PatchDataI32(mHdr + 0, UFldOff_[fi]); { Offset (absolute in instance) }

            if UFldTk[fi] = Ord(tyAnsiString) then
              mKind := 1
            else if UFldIsArray[fi] and (UFldArrLen[fi] = -1) then
              mKind := 2
            else if FieldIsComInterface(fi) then
              mKind := 4
            else if UFldTk[fi] = Ord(tyVariant) then
              mKind := 5                 { Variant slot (PXXVarClear on finalize) }
            else if UFldTk[fi] = Ord(tyClass) then
              mKind := 6                 { object binding (PXXObjRelease on finalize) }
            else
              mKind := 3;
            PatchDataI32(mHdr + 4, mKind);

            if UFldIsArray[fi] then
            begin
              if UFldArrLen[fi] = -1 then
                arrCount := 1
              else
                arrCount := UFldArrLen[fi];
            end
            else
              arrCount := 1;
            PatchDataI32(mHdr + 8, arrCount);

            typeRef := 0;
            if mKind = 2 then
            begin
              dynDescOff := hdr + 12 + mCount * 16 + dynIdx * 20;
              typeRef := dynDescOff - (mHdr + 12);

              PatchDataI32(dynDescOff + 0, 2); { Kind = 2 (DynArray) }

              depth := UFldDynDepth[fi];
              if UFldTk[fi] = Ord(tyAnsiString) then
                baseKind := 1
              else if (UFldTk[fi] = Ord(tyRecord)) and RecordHasManagedFields(UFldRec_[fi]) then
                baseKind := 3
              else
                baseKind := 0;

              if depth > 1 then
                elSize := targetPtrSize
              else
              begin
                if baseKind = 1 then
                  elSize := targetPtrSize
                else if baseKind = 3 then
                  elSize := UClsSize_[UFldRec_[fi] - REC_UCLASS_BASE]
                else
                  elSize := TypeSize(IntToTypeKind(UFldTk[fi]));
              end;
              PatchDataI32(dynDescOff + 4, elSize);
              PatchDataI32(dynDescOff + 8, depth);
              PatchDataI32(dynDescOff + 12, baseKind);

              baseTypeRef := 0;
              if baseKind = 3 then
              begin
                subCi := UFldRec_[fi] - REC_UCLASS_BASE;
                if (subCi >= 0) and (subCi < UClsCount) and (UClsRTTIOff[subCi] >= 0) then
                  baseTypeRef := UClsRTTIOff[subCi] - (dynDescOff + 16);
              end;
              PatchDataI32(dynDescOff + 16, baseTypeRef);

              Inc(dynIdx);
            end
            else if mKind = 3 then
            begin
              subCi := UFldRec_[fi] - REC_UCLASS_BASE;
              if (subCi >= 0) and (subCi < UClsCount) and (UClsRTTIOff[subCi] >= 0) then
                typeRef := UClsRTTIOff[subCi] - (mHdr + 12);
            end
            else if mKind = 4 then
              { COM interface member: typeRef carries the interface id (its UCls
                index), the runtime key PXXIntfRelease dispatches on. }
              typeRef := UFldRec_[fi] - REC_UCLASS_BASE;
            PatchDataI32(mHdr + 12, typeRef);

            Inc(k);
          end;
        end;
        cCi := UClsParent[cCi];
      end;
      PatchDataI32(hdr + 8, k); { MemberCount }

      { backlink: [VMT-16] -> this descriptor }
      if UClsVMTOffset[ci] >= 16 then
        AddDataPtrFix(UClsVMTOffset[ci] - 16, hdr);
    end;
  end;

  for i := 0 to AnonDynArrayCount - 1 do
  begin
    hdr := AnonDynArrayOff[i];
    PatchDataI32(hdr + 0, 2); { Kind = 2 (DynArray) }

    depth := AnonDynArrayDepth[i];
    baseKind := ManagedElemKindLocked(AnonDynArrayBaseTk[i], AnonDynArrayBaseRec[i]);

    if depth > 1 then
      elSize := targetPtrSize
    else
    begin
      if (baseKind = 1) or (baseKind = 4) then
        elSize := targetPtrSize
      else if baseKind = 3 then
        elSize := UClsSize_[AnonDynArrayBaseRec[i] - REC_UCLASS_BASE]
      else
        elSize := AnonDynArrayElSize[i];
    end;
    PatchDataI32(hdr + 4, elSize);
    PatchDataI32(hdr + 8, depth);
    PatchDataI32(hdr + 12, baseKind);

    baseTypeRef := 0;
    if baseKind = 3 then
    begin
      subCi := AnonDynArrayBaseRec[i] - REC_UCLASS_BASE;
      if (subCi >= 0) and (subCi < UClsCount) and (UClsRTTIOff[subCi] >= 0) then
        baseTypeRef := UClsRTTIOff[subCi] - (hdr + 16);
    end
    else if baseKind = 4 then
      { COM interface elements: the SAME word carries the interface id rather
        than a relative offset to a sub-descriptor — the discriminated slot a
        class layout descriptor's kind-4 member already uses (see mKind = 4
        above). builtinheap's walks read it back through baseRecDesc. }
      baseTypeRef := ManagedElemRef(AnonDynArrayBaseTk[i], AnonDynArrayBaseRec[i]);
    PatchDataI32(hdr + 16, baseTypeRef);
  end;
end;

{ Compile-time structural dump (--dump-rtti). Proves names/kinds/offsets and
  resolved proc indices; runtime method *addresses* are validated in Phase 2. }
procedure DumpRTTITables;
var ci, i, base, cnt, pri, tk, mi, fIdx, procIdx, etid, vb: Integer;
    nm: AnsiString;
begin
  writeln('RTTI: registryOff=', RTTIRegistryOff, ' classes=', RTTIRegistryCount);
  for etid := 0 to EnumTypeCount - 1 do
  begin
    nm := TokSliceStr(EnumTypeNOff[etid], EnumTypeNLen[etid]);
    write('enum ', nm, ' count=', EnumTypeValCount[etid], ' rttiOff=', EnumTypeRTTIOff[etid]);
    vb := EnumTypeValBase[etid];
    for i := 0 to EnumTypeValCount[etid] - 1 do
      write(' ', TokSliceStr(EnumValNOff[vb + i], EnumValNLen[vb + i]));
    writeln;
  end;
  for ci := 0 to UClsCount - 1 do
  begin
    if UClsRTTIOff[ci] < 0 then continue;
    nm := TokSliceStr(UClsNOff[ci], UClsNLen[ci]);
    writeln('class ', nm, ' rttiOff=', UClsRTTIOff[ci],
            ' size=', UClsSize_[ci], ' vmtOff=', UClsVMTOffset[ci]);
    base := UClsPBase[ci]; cnt := UClsPCount[ci];
    for i := 0 to cnt - 1 do
    begin
      pri := base + i;
      if UPropPub[pri] <> 1 then continue;
      nm := TokSliceStr(UPropNOff[pri], UPropNLen[pri]);
      tk := UPropTk[pri];
      write('  prop ', nm, ' tk=', tk);
      if UPropEnumId[pri] >= 0 then
        write(' enum=', TokSliceStr(EnumTypeNOff[UPropEnumId[pri]], EnumTypeNLen[UPropEnumId[pri]]));
      if UPropReadFLen[pri] > 0 then
      begin
        fIdx := FindUField(ci, TokSliceStr(UPropReadFOff[pri], UPropReadFLen[pri]));
        if fIdx >= 0 then write(' getField@', UFldOff_[fIdx]);
      end
      else if UPropReadMLen[pri] > 0 then
      begin
        mi := FindUMeth(ci, TokSliceStr(UPropReadMOff[pri], UPropReadMLen[pri]));
        if mi >= 0 then write(' getMethProc=', UMthProc_[mi]);
      end;
      if UPropWriteFLen[pri] > 0 then
      begin
        fIdx := FindUField(ci, TokSliceStr(UPropWriteFOff[pri], UPropWriteFLen[pri]));
        if fIdx >= 0 then write(' setField@', UFldOff_[fIdx]);
      end
      else if UPropWriteMLen[pri] > 0 then
      begin
        mi := FindUMeth(ci, TokSliceStr(UPropWriteMOff[pri], UPropWriteMLen[pri]));
        if mi >= 0 then write(' setMethProc=', UMthProc_[mi]);
      end;
      writeln;
    end;
    base := UClsMBase[ci]; cnt := UClsMCount[ci];
    for i := 0 to cnt - 1 do
    begin
      mi := base + i;
      if UMthPub[mi] <> 1 then continue;
      nm := TokSliceStr(UMthNOff[mi], UMthNLen[mi]);
      procIdx := UMthProc_[mi];
      writeln('  meth ', nm, ' proc=', procIdx);
    end;
  end;
end;
