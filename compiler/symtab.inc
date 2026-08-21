{ SPDX-License-Identifier: MPL-2.0 }
{ ===== User-class helpers (must precede hardcoded record helpers) ===== }

function NilPyUserCode: Boolean;
{ True while compiling code the NilPy USER wrote — the main `.npy`/`.py` program
  OR an imported `.py` module — and false for the Pascal RTL units that are
  loaded into the same compilation.

  The whole NilPy object-reclamation set (zero-init, rebind release, field-store
  ARC, scope-exit release, return-ownership retain) keys on this. It used to be
  spelled `isNilPy and (CurrentUnitIdx < 0)` at each site, which means "the main
  program only": a class defined in an imported `.py` module compiles with
  CurrentUnitIdx >= 0, so NONE of those rules fired for it and its instances
  were never reclaimed. songformatter is exactly that shape — every class lives
  in an imported module — so it got no reclamation at all
  (bug-nilpy-object-reclamation-disabled-inside-py-modules).

  `PyExprMode` is the discriminator that tells a `.py` module from a Pascal
  unit: ParsePyUnit turns it on for a module body, and the Pascal unit path
  (pasparser_prog.inc, CompileUnit) explicitly turns it off. The rules MUST move
  together — zero-init without release leaks, release without zero-init frees
  garbage — which is why they share one predicate instead of nine copies of the
  condition. }
begin
  NilPyUserCode := isNilPy and ((CurrentUnitIdx < 0) or PyExprMode);
end;

function DeclCaseSensitive: Boolean;
{ Should a symbol/proc registered RIGHT NOW be matched case-sensitively?

  Pascal is case-INsensitive (FPC parity) and that is deliberate; Python is
  case-SENSITIVE. NilPy inherited Pascal's rule, so `x` and `X` were one
  variable and `a = A()` rebound the class name to the instance — a silent
  wrong value in the single most idiomatic spelling in Python
  (bug-nilpy-identifiers-are-case-insensitive).

  The split is per-DECLARATION, not per-lookup: FindSym already matches exact
  case first and only falls back to a case-insensitive scan for symbols whose
  SymCaseSensitive is False. So marking only the NilPy user's own symbols
  sensitive keeps every Pascal RTL routine reachable from NilPy code under
  whatever case it is spelled with, while NilPy's own names stop merging.
  Same shape as the C frontend, which forces CaseSensitiveMode around
  ParseCUnit for exactly this reason.

  NilPyUserCode (not `isNilPy`) is the predicate: a Pascal unit compiled into
  the same NilPy compilation parses with PyExprMode off and CurrentUnitIdx >= 0,
  so its symbols keep Pascal's rule. }
begin
  DeclCaseSensitive := CaseSensitiveMode or NilPyUserCode;
end;

function DeclVisible(declUnit: Integer): Boolean; forward;
{ Defined beside VisibilityAllows, but the type-name tables above it call it, and
  the FPC SEED build has none of pxx's declare-anywhere laxness — it is the
  canary that catches this, not `make compiler/pascal26`
  (bug-a-fpc-seed-drift-emitasmx64-forward). }
function UsesRankOf(curUnit, declUnit: Integer): Integer; forward;
procedure IREmitCodeCall(addr: Integer); forward;
procedure EmitDynArrayReleaseForSym(symIdx: Integer); forward;
procedure EmitVariantClear; forward;
procedure EmitManagedRecordReleaseLocked(recId: Integer); forward;
procedure EmitAcquireHeapLock; forward;
procedure EmitReleaseHeapLock; forward;
{$ifndef PXX_NO_AARCH64}procedure EmitLoadVarA64(idx: Integer); forward;{$endif}
{$ifndef PXX_NO_AARCH64}procedure EmitLoadDataRefA64(rd, dataOff: Integer); forward;{$endif}
{$ifndef PXX_NO_AARCH64}procedure EmitA64CopyBytes(countReg, srcReg, dstReg: Integer); forward;{$endif}
{$ifndef PXX_NO_ARM32}procedure EmitArm32CopyBytes(countReg, srcReg, dstReg: Integer); forward;{$endif}
{$ifndef PXX_NO_ARM32}procedure EmitLoadVarArm32(idx: Integer); forward;{$endif}
{$ifndef PXX_NO_ARM32}procedure EmitLoadVar64Arm32(idx: Integer); forward;{$endif}
{$ifndef PXX_NO_ARM32}procedure EmitLoadVarAddrArm32(idx: Integer); forward;{$endif}
{$ifndef PXX_NO_ARM32}procedure EmitLoadDataRefArm32(rd, dataOff: Integer); forward;{$endif}
procedure EmitLoadVarXtensa(idx: Integer); forward;
procedure EmitLoadVar64Xtensa(idx: Integer); forward;
procedure EmitLoadVarRISCV32(idx: Integer); forward;
procedure EmitLoadVar64RISCV32(idx: Integer); forward;
procedure EmitLoadDataRefRISCV32(rd, dataOff: Integer); forward;
procedure EmitLoadImmRISCV32(rd: Integer; v: Int32); forward;
procedure EmitSlotAddrRISCV32(rd, si: Integer); forward;
procedure EmitFrameAddrXtensa(rd: Integer; off: Integer); forward;
procedure EmitLoadConstXtensa(rd: Integer; v: Int32); forward;
{ The xtensa inline-asm engine (asmtext_xtensa.inc) replays `la reg,@fp/@glob/
  @data` through these rather than open-coding a second copy: the frame pointer
  is a7 or a15 depending on XtensaABI, and an out-of-range frame offset needs
  the L32R literal pool. }
procedure EmitLoadGlobAddrXtensa(rd: Integer; bssOff: Integer); forward;
procedure EmitLoadDataRefXtensa(rd: Integer; dataOff: Integer); forward;
procedure EmitCallProc(procIdx: Integer); forward;
procedure EmitManagedLocalCleanup(retSymIdx: Integer); forward;
{ Scope-exit release of a proc's managed locals on ANY target. Body in
  ir_codegen.inc — see the note there for why the six arms had to be one
  procedure. }
procedure EmitManagedLocalCleanupForTarget(retSymIdx: Integer); forward;
{ Normal-return cleanup: unchain this proc's exception cleanup frame (when it
  has one) and then release its managed locals. Body in ir_codegen.inc. }
procedure EmitProcScopeExitCleanupForTarget(retSymIdx: Integer); forward;
function TargetHasProcCleanupFrame: Boolean; forward;
procedure EmitProcCleanupFrameEnterForTarget(var landPatch: Integer); forward;
procedure EmitProcCleanupLandingPadForTarget(landPatch: Integer); forward;
function ProcHasManagedLocalCleanup(procIdx, retSymIdx: Integer): Boolean; forward;
procedure EmitLeaveExceptionFrameX64; forward;


function ULower(const s: AnsiString): AnsiString;
var res: AnsiString; i: Integer; c: Char;
begin
  res := s;
  i := 1;
  while i <= Length(res) do
  begin
    c := res[i];
    if (c >= 'A') and (c <= 'Z') then res[i] := Chr(Ord(c) + 32);
    Inc(i);
  end;
  Result := res;
end;

function UNameMatch(off, len: Integer; const lo: AnsiString): Boolean;
var i: Integer; c: Char;
begin
  Result := False;
  if len <> Length(lo) then Exit;
  i := 0;
  while i < len do
  begin
    c := TokChars[off + i];
    if (c >= 'A') and (c <= 'Z') then c := Chr(Ord(c) + 32);
    if c <> lo[i + 1] then Exit;
    Inc(i);
  end;
  Result := True;
end;

function UNameMatchCS(off, len: Integer; const s: AnsiString): Boolean;
{ Exact, case-SENSITIVE slice match (C struct/union fields — C distinguishes
  `b` from `B`). Mirror of UNameMatch without the ASCII case fold. }
var i: Integer;
begin
  Result := False;
  if len <> Length(s) then Exit;
  i := 0;
  while i < len do
  begin
    if TokChars[off + i] <> s[i + 1] then Exit;
    Inc(i);
  end;
  Result := True;
end;

function TokSlicesMatch(off1, len1, off2, len2: Integer): Boolean;
var i: Integer; c1, c2: Char;
begin
  Result := False;
  if len1 <> len2 then Exit;
  for i := 0 to len1 - 1 do
  begin
    c1 := TokChars[off1 + i];
    c2 := TokChars[off2 + i];
    if (c1 >= 'A') and (c1 <= 'Z') then c1 := Chr(Ord(c1) + 32);
    if (c2 >= 'A') and (c2 <= 'Z') then c2 := Chr(Ord(c2) + 32);
    if c1 <> c2 then Exit;
  end;
  Result := True;
end;

function FindTypeAlias(const name: AnsiString): Integer;
var i, bestRank, r: Integer; lo, name2: AnsiString;
begin
  Result := -1;
  bestRank := -2;
  name2 := name;
  lo := ULower(name2);
  i := 0;
  while i < AliasCount do
  begin
    { A type alias declared in a unit this scope cannot legitimately reach is
      not a candidate — the same non-transitive uses rule the routine and class
      tables apply. Without it `type TE = (a, b, c)` in a unit two hops away
      resolved globally while a record type declared beside it did not, which
      read as one rule with holes and was really two tables
      (bug-pascal-uses-non-transitivity-only-covers-routines-and-types). }
    { …and among the visible ones the LATEST-NAMED unit wins, exactly as for
      classes: `uses a, b` binds b's `TAlias` and b's enum type. Ties keep the
      FIRST row, so a single declaration and two rows from one unit are
      unaffected. bug-p-scope-hiding-covers-routines-but-not-types-and-classes }
    if UNameMatch(AliasNOff[i], AliasNLen[i], lo) and
       DeclVisible(AliasUnitIdx[i]) then
    begin
      r := UsesRankOf(CurrentUnitIdx, AliasUnitIdx[i]);
      if (Result < 0) or (r > bestRank) then begin Result := i; bestRank := r; end;
    end;
    Inc(i);
  end;
  { No fallback here on purpose: a miss is normal. `puint8` and friends resolve
    through the pointer-alias path AFTER this returns -1, so an unresolved name
    at this point says nothing. A debug dump of the whole alias table used to
    fire here for exactly that name and printed to STDOUT — i.e. any program
    mentioning `puint8` (an entirely ordinary name in C-interop Pascal) got a
    dozen lines of compiler internals mixed into its build output, and then
    compiled fine. Removed 2026-08-20. }
end;

procedure RegisterPtrAlias(noff, nlen, elemTk, elemRec, targetNOff, targetNLen: Integer);
begin
  if AliasCount >= MAX_TYPEALIAS then Error('too many type aliases');
  AliasNOff[AliasCount] := noff;
  AliasNLen[AliasCount] := nlen;
  AliasTk[AliasCount] := Ord(tyPointer);
  AliasElemTk[AliasCount] := elemTk;
  AliasElemRec[AliasCount] := elemRec;
  AliasPtrDepth[AliasCount] := 0;
  AliasPtrBaseTk[AliasCount] := Ord(tyUnknown);
  AliasPtrBaseRec[AliasCount] := REC_NONE;
  AliasTargetNOff[AliasCount] := targetNOff;
  AliasTargetNLen[AliasCount] := targetNLen;
  AliasProcSig[AliasCount] := -1;
  AliasUnitIdx[AliasCount] := CurrentUnitIdx;
  Inc(AliasCount);
end;

{ Defined further down this include; RegisterGeneralAlias below needs it to
  recognise a frozen-string alias, and the FPC seed build wants the forward. }
function TypeIsFrozenString(tk: TTypeKind): Boolean; forward;

procedure RegisterGeneralAlias(noff, nlen, tk, rec: Integer);
begin
  if AliasCount >= MAX_TYPEALIAS then Error('too many type aliases');
  AliasNOff[AliasCount] := noff;
  AliasNLen[AliasCount] := nlen;
  AliasTk[AliasCount] := tk;
  AliasElemTk[AliasCount] := tk;
  AliasElemRec[AliasCount] := rec;
  AliasPtrDepth[AliasCount] := 0;
  AliasPtrBaseTk[AliasCount] := Ord(tyUnknown);
  AliasPtrBaseRec[AliasCount] := REC_NONE;
  AliasTargetNOff[AliasCount] := 0;
  AliasTargetNLen[AliasCount] := 0;
  AliasProcSig[AliasCount] := -1;
  { A frozen-string alias keeps its CAPACITY. ParseTypeKind has just run for the
    right-hand side, so LastTypeStrCap holds the N of `T = string[N]`; without
    carrying it here the alias resolved to the KIND alone and every variable and
    record field declared through it truncated at DEFAULT_STR_CAP instead of N —
    while the identical INLINE declaration truncated correctly, which is what
    made it look like string[N] worked.
    bug-a-string-n-type-alias-loses-its-capacity }
  if TypeIsFrozenString(IntToTypeKind(tk)) then
    AliasStrCap[AliasCount] := LastTypeStrCap
  else
    AliasStrCap[AliasCount] := 0;
  AliasUnitIdx[AliasCount] := CurrentUnitIdx;
  Inc(AliasCount);
end;

procedure RegisterMethodPtrTypeAlias(noff, nlen, sigPi, methodRec: Integer);
{ Named method-pointer type: `T = procedure(...) of object`. The value is a
  16-byte {Code,Data} record (methodRec); AliasProcSig carries the call
  signature so an indirect `v(args)` injects Self (Data) and calls Code. }
begin
  if AliasCount >= MAX_TYPEALIAS then Error('too many type aliases');
  AliasNOff[AliasCount] := noff;
  AliasNLen[AliasCount] := nlen;
  AliasTk[AliasCount] := Ord(tyRecord);
  AliasElemTk[AliasCount] := Ord(tyRecord);
  AliasElemRec[AliasCount] := methodRec;
  AliasPtrDepth[AliasCount] := 0;
  AliasPtrBaseTk[AliasCount] := Ord(tyUnknown);
  AliasPtrBaseRec[AliasCount] := REC_NONE;
  AliasTargetNOff[AliasCount] := 0;
  AliasTargetNLen[AliasCount] := 0;
  AliasProcSig[AliasCount] := sigPi;
  AliasUnitIdx[AliasCount] := CurrentUnitIdx;
  Inc(AliasCount);
end;

procedure RegisterProcTypeAlias(noff, nlen, sigPi: Integer);
{ Named procedural type: `T = procedure(...)` / `function(...): R`. The runtime
  value is a code address (pointer-sized), so reuse the pointer alias shape;
  AliasProcSig carries the signature Procs[] index used to marshal an indirect
  call's arguments and return type. }
begin
  if AliasCount >= MAX_TYPEALIAS then Error('too many type aliases');
  AliasNOff[AliasCount] := noff;
  AliasNLen[AliasCount] := nlen;
  AliasTk[AliasCount] := Ord(tyPointer);
  AliasElemTk[AliasCount] := Ord(tyUnknown);
  AliasElemRec[AliasCount] := REC_NONE;
  AliasPtrDepth[AliasCount] := 1;
  AliasPtrBaseTk[AliasCount] := Ord(tyUnknown);
  AliasPtrBaseRec[AliasCount] := REC_NONE;
  AliasTargetNOff[AliasCount] := 0;
  AliasTargetNLen[AliasCount] := 0;
  AliasProcSig[AliasCount] := sigPi;
  AliasUnitIdx[AliasCount] := CurrentUnitIdx;
  Inc(AliasCount);
end;

function FindArrayType(const name: AnsiString): Integer;
{ Latest-named unit wins among the visible rows — see FindUClass.
  bug-p-scope-hiding-covers-routines-but-not-types-and-classes }
var i, bestRank, r: Integer;
begin
  Result := -1;
  bestRank := -2;
  for i := 0 to ArrTypeCount - 1 do
    if CaseEqual(ArrTypeName[i], name) and DeclVisible(ArrTypeUnitIdx[i]) then
    begin
      r := UsesRankOf(CurrentUnitIdx, ArrTypeUnitIdx[i]);
      if (Result < 0) or (r > bestRank) then begin Result := i; bestRank := r; end;
    end;
end;

function FindStrConst(const name: AnsiString): Integer;
{ Innermost-wins, like FindSym: a constant declared in the CURRENT routine beats one
  declared at unit level, and one declared in some OTHER routine is not visible at all.
  Newest-first within each tier, so a redeclaration shadows an earlier one.

  The table was flat and searched oldest-first, so a routine-local const leaked into every
  routine parsed after it AND beat that routine's own const of the same name -- the wrong
  text, silently. bug-pascal-string-const-not-scoped. }
var i: Integer;
begin
  Result := -1;
  for i := StrConstCount - 1 downto 0 do          { the current routine's own }
    if (StrConstOwner[i] = CurProc) and CaseEqual(StrConstName[i], name) and
       DeclVisible(StrConstUnitIdx[i]) then
      begin Result := i; Exit; end;
  for i := StrConstCount - 1 downto 0 do          { else a unit/global-level one }
    if (StrConstOwner[i] = -1) and CaseEqual(StrConstName[i], name) and
       DeclVisible(StrConstUnitIdx[i]) then
      begin Result := i; Exit; end;
end;

function FindSetConst(const name: AnsiString): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to SetConstCount - 1 do
    if CaseEqual(SetConstName[i], name) and DeclVisible(SetConstUnitIdx[i]) then
      begin Result := i; Exit; end;
end;

procedure RegisterSetAlias(noff, nlen, elemEnumId: Integer);
{ Named set type: TFooSet = set of TFoo. Stored in the alias table with
  AliasTk=tySet; AliasElemTk holds the element enum id (or -1). }
begin
  if AliasCount >= MAX_TYPEALIAS then Error('too many type aliases');
  AliasNOff[AliasCount] := noff;
  AliasNLen[AliasCount] := nlen;
  AliasTk[AliasCount] := Ord(tySet);
  AliasElemTk[AliasCount] := elemEnumId;
  AliasElemRec[AliasCount] := REC_NONE;
  AliasPtrDepth[AliasCount] := 0;
  AliasPtrBaseTk[AliasCount] := Ord(tyUnknown);
  AliasPtrBaseRec[AliasCount] := REC_NONE;
  AliasTargetNOff[AliasCount] := 0;
  AliasTargetNLen[AliasCount] := 0;
  AliasProcSig[AliasCount] := -1;
  AliasUnitIdx[AliasCount] := CurrentUnitIdx;
  Inc(AliasCount);
end;

function GetSliceName(off, len: Integer): AnsiString;
var s: AnsiString; i: Integer;
begin
  s := '';
  for i := 0 to len - 1 do
    AppendChar(s, TokChars[off + i]);
  Result := s;
end;



procedure RegisterClassRefAlias(noff, nlen, classRec: Integer);
{ Named metaclass type: TFooClass = class of TFoo. Runtime values are RTTI
  pointers, so reuse the typed-pointer alias representation with a tyClass
  element marker and the base class record id. }
begin
  if AliasCount >= MAX_TYPEALIAS then Error('too many type aliases');
  AliasNOff[AliasCount] := noff;
  AliasNLen[AliasCount] := nlen;
  AliasTk[AliasCount] := Ord(tyPointer);
  AliasElemTk[AliasCount] := Ord(tyClass);
  AliasElemRec[AliasCount] := classRec;
  AliasPtrDepth[AliasCount] := 1;
  AliasPtrBaseTk[AliasCount] := Ord(tyClass);
  AliasPtrBaseRec[AliasCount] := classRec;
  AliasProcSig[AliasCount] := -1;
  AliasUnitIdx[AliasCount] := CurrentUnitIdx;
  Inc(AliasCount);
end;

function FindEnumType(const name: AnsiString): Integer;
{ Latest-named unit wins among the visible rows — see FindUClass.
  bug-p-scope-hiding-covers-routines-but-not-types-and-classes }
var i, bestRank, r: Integer; lo, name2: AnsiString;
begin
  Result := -1;
  bestRank := -2;
  name2 := name;
  lo := ULower(name2);
  i := 0;
  while i < EnumTypeCount do
  begin
    if UNameMatch(EnumTypeNOff[i], EnumTypeNLen[i], lo) and
       DeclVisible(EnumTypeUnitIdx[i]) then
    begin
      r := UsesRankOf(CurrentUnitIdx, EnumTypeUnitIdx[i]);
      if (Result < 0) or (r > bestRank) then begin Result := i; bestRank := r; end;
    end;
    Inc(i);
  end;
end;

function RegisterEnumType(noff, nlen: Integer): Integer;
{ Open a new enum type; value names added via AddEnumVal, then closed by the
  caller via EnumTypeValCount[etid] (set to EnumValCount - ValBase). }
begin
  if EnumTypeCount >= MAX_ENUMTYPE then Error('too many enum types');
  Result := EnumTypeCount;
  EnumTypeNOff[Result] := noff;
  EnumTypeNLen[Result] := nlen;
  EnumTypeValBase[Result] := EnumValCount;
  EnumTypeHasHoles[Result] := False;
  EnumTypeScoped[Result] := False;
  EnumTypeValCount[Result] := 0;
  EnumTypeRTTIOff[Result] := -1;
  EnumTypeUnitIdx[Result] := CurrentUnitIdx;
  Inc(EnumTypeCount);
end;

function RegisterTypeInfoReq(cat, key: Integer): Integer;
{ Dedup a widened TypeInfo(T) use (T = a scalar/string/class/record, NOT an
  enum -- those keep the legacy FindEnumType path). Same (cat, key) returns
  the same request index every time, so a header is emitted once per distinct
  type even if TypeInfo() is written many times over. The actual Data[]
  header is built by EmitTypeInfoHeaders (rtti_emit.inc), which runs after
  EmitRTTI (class/record TypeInfo needs UClsRTTIOff, only known by then). }
var i: Integer;
begin
  i := 0;
  while i < TypeInfoReqCount do
  begin
    if (TypeInfoReqCat[i] = cat) and (TypeInfoReqKey[i] = key) then
    begin
      Result := i;
      Exit;
    end;
    Inc(i);
  end;
  if TypeInfoReqCount >= MAX_TYPEINFO_REQ then Error('too many distinct TypeInfo() uses (MAX_TYPEINFO_REQ)');
  Result := TypeInfoReqCount;
  TypeInfoReqCat[Result] := cat;
  TypeInfoReqKey[Result] := key;
  TypeInfoReqOff[Result] := -1;
  Inc(TypeInfoReqCount);
end;

procedure AddEnumVal(noff, nlen, ordVal: Integer);
begin
  if EnumValCount >= MAX_ENUMVAL then Error('too many enum values');
  EnumValNOff[EnumValCount] := noff;
  EnumValNLen[EnumValCount] := nlen;
  EnumValOrd[EnumValCount] := ordVal;
  Inc(EnumValCount);
end;

procedure EnumTypeOrdRange(etid: Integer; var loOut, hiOut: Integer);
{ The ORDINAL range of an enum type -- the min and max of its members' VALUES,
  not 0..count-1. Those two coincide for a plain `(a, b, c)` and diverge the
  moment an explicit `= N` appears: `(gX = 3, gY = 4, gZ = 9)` runs 3..9, has
  three members, and Low/High/`set of`/`array[T]` all want 3 and 9. Counting
  members instead answered 0 and 2 -- two ordinals that are not even values of
  the type (bug-p-low-high-of-an-enum-with-explicit-values-count-members). }
var i, base, cnt: Integer;
begin
  base := EnumTypeValBase[etid];
  cnt := EnumTypeValCount[etid];
  if cnt <= 0 then begin loOut := 0; hiOut := -1; Exit; end;
  loOut := EnumValOrd[base];
  hiOut := loOut;
  for i := base + 1 to base + cnt - 1 do
  begin
    if EnumValOrd[i] < loOut then loOut := EnumValOrd[i];
    if EnumValOrd[i] > hiOut then hiOut := EnumValOrd[i];
  end;
end;

function FindEnumMemberOrd(etid: Integer; const name: AnsiString; var ordOut: Integer): Boolean;
{ Member lookup within one enum type (TEnum.member resolution). }
var i: Integer;
begin
  Result := False;
  for i := EnumTypeValBase[etid] to EnumTypeValBase[etid] + EnumTypeValCount[etid] - 1 do
    if CaseEqual(GetTokenStrFromRaw(EnumValNOff[i], EnumValNLen[i]), name) then
    begin
      ordOut := EnumValOrd[i];
      Result := True;
      Exit;
    end;
end;

{ The class of that name DECLARED IN a given unit. Two libraries may export
  the same class name — tkinter's `Canvas` and reportlab's — so a QUALIFIED
  reference has to resolve in the unit it names, not by first match.
  decide-class-namespace-scoping. }
{ …matching the spelling EXACTLY. Python is case-sensitive, so `Canvas` (a
  class tkinter exports) and `canvas` (a module reportlab exports) are two
  different names; the unit-alias table folds case and cannot tell them apart,
  so the decision of which is a submodule is made here, on the raw spelling. }
function UnitDeclaresClassExactly(const name: AnsiString; unitIdx: Integer): Boolean;
var i, j: Integer; ok: Boolean;
begin
  UnitDeclaresClassExactly := False;
  for i := 0 to UClsCount - 1 do
  begin
    if UClsUnitIdx[i] <> unitIdx then Continue;
    if UClsNLen[i] <> Length(name) then Continue;
    ok := True;
    for j := 0 to UClsNLen[i] - 1 do
      if TokChars[UClsNOff[i] + j] <> name[j + 1] then begin ok := False; Break; end;
    if ok then begin UnitDeclaresClassExactly := True; Exit; end;
  end;
end;

procedure RecordUsesEdge(fromUnit, toUnit: Integer; iface: Boolean);
{ bug-pascal-uses-is-transitive measurement step: append one `uses` clause to
  the edge table. Called unconditionally (cheap array append) so the table is
  always complete regardless of whether --warn-uses-leak is on; only the WARN
  itself is gated behind the flag. Silently drops past MAX_USES_EDGES — a
  saturated table degrades the count, it must never abort a build. }
begin
  if UsesEdgeCount >= MAX_USES_EDGES then Exit;
  UsesEdgeFrom[UsesEdgeCount] := fromUnit;
  UsesEdgeTo[UsesEdgeCount] := toUnit;
  UsesEdgeIface[UsesEdgeCount] := iface;
  Inc(UsesEdgeCount);
end;

function UnitIsAmbient(unitIdx: Integer): Boolean;
{ builtin/builtinheap are pxx's own System unit — `compiler/builtin/builtin.pas`
  says so outright ("pxx has no separate System unit (System IS the builtin
  layer)"), and every Pascal dialect auto-includes System everywhere with no
  `uses` needed. They are injected by ParseProgram's epilogue
  (`ParseUsesUnit('builtinheap')` / `('builtin')`, compiler/pasparser_proc.inc), never
  written by a user clause, so the edge table structurally cannot show them as
  reachable from anywhere — without this, every unit in the tree reports a leak
  to them and the raw hit counts drown out the real ones. Ambient by design, not
  a leak. }
var lo: AnsiString; i: Integer;
begin
  UnitIsAmbient := False;
  if unitIdx < 0 then Exit;
  lo := Strs[unitIdx].Text;
  if (lo = 'builtin') or (lo = 'builtinheap') then
  begin UnitIsAmbient := True; Exit; end;
  { ...and every other unit the COMPILER injected. Measured under --strict-uses:
    the tk widgetset's `//` lowers to pylib's pyfloormod_i, and tk uses only
    `strings` — nothing in that program's source could have declared the
    dependency, because nothing in the source asked for the helper. Same for
    textfile/math/promocore/softfloat/pxxcio and the mimic_* shims. }
  for i := 0 to AmbientUnitCount - 1 do
    if AmbientUnitIdx[i] = unitIdx then begin UnitIsAmbient := True; Exit; end;
end;

function UnitIsCTranslationUnit(unitIdx: Integer): Boolean;
{ True for a `.c` source pulled in as a unit. See CTUnitIdx in defs.inc: these
  share ONE external-linkage namespace, the way a C program's object files do. }
var i: Integer;
begin
  UnitIsCTranslationUnit := False;
  if unitIdx < 0 then Exit;
  for i := 0 to CTUnitCount - 1 do
    if CTUnitIdx[i] = unitIdx then begin UnitIsCTranslationUnit := True; Exit; end;
end;

function UnitIsPyModule(unitIdx: Integer): Boolean;
{ True for a `.py` MODULE pulled in by an import (ParsePyUnit). Mirrors
  UnitIsCTranslationUnit above; see PyModUnitIdx in defs.inc for why the fact is
  RECORDED rather than inferred from `ProcUnitIdx >= 0`. }
var i: Integer;
begin
  UnitIsPyModule := False;
  if unitIdx < 0 then Exit;
  for i := 0 to PyModUnitCount - 1 do
    if PyModUnitIdx[i] = unitIdx then begin UnitIsPyModule := True; Exit; end;
end;

procedure MarkUnitPyModule(unitIdx: Integer);
var i: Integer;
begin
  if unitIdx < 0 then Exit;
  for i := 0 to PyModUnitCount - 1 do
    if PyModUnitIdx[i] = unitIdx then Exit;
  if PyModUnitCount > 255 then Exit;
  PyModUnitIdx[PyModUnitCount] := unitIdx;
  Inc(PyModUnitCount);
end;

procedure MarkUnitCTranslationUnit(unitIdx: Integer);
var i: Integer;
begin
  if unitIdx < 0 then Exit;
  for i := 0 to CTUnitCount - 1 do
    if CTUnitIdx[i] = unitIdx then Exit;
  if CTUnitCount > 255 then Exit;
  CTUnitIdx[CTUnitCount] := unitIdx;
  Inc(CTUnitCount);
end;

function DeclVisibleBareRoutine(declUnit: Integer;
                               const name: AnsiString): Boolean; forward;
{ DeclVisible plus the qualified-only rule — body beside DeclVisible's. }
function PythonSideDeclaresRoutine(const name: AnsiString;
                                   exceptUnit: Integer): Boolean; forward;
{ …and its helper, whose BODY sits below ProcNameMatches because it calls it —
  the FPC seed build has none of pxx's declare-anywhere laxness and is the canary
  that catches this (bug-a-fpc-seed-drift-emitasmx64-forward). }

function UnitIsQualifiedOnly(unitIdx: Integer): Boolean;
{ True for a Pascal unit a NilPy `import` pulled in — see QualOnlyUnitIdx. }
var i: Integer;
begin
  UnitIsQualifiedOnly := False;
  if unitIdx < 0 then Exit;
  for i := 0 to QualOnlyUnitCount - 1 do
    if QualOnlyUnitIdx[i] = unitIdx then begin UnitIsQualifiedOnly := True; Exit; end;
end;

function UnitIsPxxDialect(unitIdx: Integer): Boolean;
{ True for a unit that declared `{$MODE PXX}` — see PxxDialectUnitIdx. }
var i: Integer;
begin
  UnitIsPxxDialect := False;
  if unitIdx < 0 then Exit;
  for i := 0 to PxxDialectUnitCount - 1 do
    if PxxDialectUnitIdx[i] = unitIdx then begin UnitIsPxxDialect := True; Exit; end;
end;

procedure MarkUnitPxxDialect(unitIdx: Integer);
{ Called from the lexer's {$MODE} handler. CurrentUnitIdx is already the unit's
  string index by the time its LexAppend runs, so the marking lands on the right
  unit without threading anything new through the resolver. In the MAIN program
  CurrentUnitIdx is < 0, which is a real answer rather than an error — the
  directive is then an explicit opt-out by the person compiling. }
begin
  if unitIdx < 0 then begin MainPxxDialect := True; Exit; end;
  if UnitIsPxxDialect(unitIdx) then Exit;
  if PxxDialectUnitCount > 255 then Exit;
  PxxDialectUnitIdx[PxxDialectUnitCount] := unitIdx;
  Inc(PxxDialectUnitCount);
end;

function DialectIsPxx: Boolean;
{ Is the code being compiled RIGHT NOW written in the pxx dialect, i.e. exempt
  from the FPC-parity strict flags? ONE predicate rather than a copy of the
  condition at each strict check — the lesson NilPyUserCode's nine-copy history
  already taught in this file. }
begin
  if CurrentUnitIdx < 0 then DialectIsPxx := MainPxxDialect
  else DialectIsPxx := UnitIsPxxDialect(CurrentUnitIdx);
end;

procedure MarkUnitQualifiedOnly(unitIdx: Integer);
var i: Integer;
begin
  if unitIdx < 0 then Exit;
  for i := 0 to QualOnlyUnitCount - 1 do
    if QualOnlyUnitIdx[i] = unitIdx then Exit;
  if QualOnlyUnitCount > 255 then Exit;
  QualOnlyUnitIdx[QualOnlyUnitCount] := unitIdx;
  Inc(QualOnlyUnitCount);
end;

procedure MarkUnitAmbient(unitIdx: Integer);
var i: Integer;
begin
  if unitIdx < 0 then Exit;
  for i := 0 to AmbientUnitCount - 1 do
    if AmbientUnitIdx[i] = unitIdx then Exit;
  if AmbientUnitCount > 255 then Exit;
  AmbientUnitIdx[AmbientUnitCount] := unitIdx;
  Inc(AmbientUnitCount);
end;

function ClassNameIsAmbientIntrinsic(const lo: AnsiString): Boolean;
{ TObject/TGuid are System-unit intrinsics minted by RegisterBuiltinTObject /
  RegisterBuiltinTGuid (compiler/pasparser_prog.inc) rather than declared by any unit,
  so AddUClass stamps them with whatever CurrentUnitIdx is at ParseProgram time
  (-1, "the program"). Every UNIT that names TObject then looks like it leaked
  through the program — the same ambient-System artifact UnitIsAmbient handles
  one level up, and measured to be 100% of the `-> <program>` bucket (TObject
  and TGuid, nothing else). Filtered by NAME because the rows carry no marker
  and adding a parallel array for an opt-in read-only instrument is not worth
  the shared-state churn; these two names are System's by definition, so a user
  re-declaration is not a leak case worth reporting either. }
begin
  ClassNameIsAmbientIntrinsic := (lo = 'tobject') or (lo = 'tguid');
end;

function PyRecIsPylibOwnClass(rec: Integer): Boolean;
{ True when `rec` names a class declared by pylib itself (TPyList, TPyDict,
  TPyBytes, TPyFile, ...) rather than by user NilPy code.

  NilPy dunder dispatch keys on "the operand is a bare tyClass", but pylib's own
  containers are tyClass too and already carry real semantics — a TPyList
  compares LEXICOGRAPHICALLY, `[1,2] < [1,3]`. Any dispatch branch that means
  "genuine user object" has to rule pylib's rows out first or it captures the
  containers and breaks them.

  Keyed on the DECLARING UNIT rather than a list of class names: the name list
  the `__contains__` guard uses (TPyList/TPyDict/TPyBytes) is the kind of thing
  that rots as pylib grows a container, and this covers every pylib class by
  construction. }
var ci: Integer;
begin
  PyRecIsPylibOwnClass := False;
  if rec < REC_UCLASS_BASE then Exit;
  ci := rec - REC_UCLASS_BASE;
  if (ci < 0) or (ci >= UClsCount) then Exit;
  if UClsUnitIdx[ci] < 0 then Exit;
  PyRecIsPylibOwnClass := (Strs[UClsUnitIdx[ci]].Text = 'pylib');
end;

function VisibilityAllows(curUnit, declUnit: Integer): Boolean;
{ True iff `declUnit` is visible from `curUnit` under the REAL Pascal uses rule:
  declUnit = curUnit, or curUnit's OWN uses clause names it. One hop. Neither
  section re-exports, so there is no closure and no transitivity of any kind.
  Strs[] indices offset by 1 so curUnit = -1 (the main program) indexes slot 0.
  Memoized per (curUnit, UsesEdgeCount) in VisCacheVis: this is called from
  every routine, class, type and symbol lookup, and a clear-plus-scan per query
  would be quadratic in the edge table. The edge count is part of the key
  because clauses are appended as parsing proceeds. }
var
  i, v: Integer;
begin
  if declUnit = curUnit then begin VisibilityAllows := True; Exit; end;
  if UnitIsAmbient(declUnit) then begin VisibilityAllows := True; Exit; end;
  { C's external linkage is FLAT across translation units — an `extern`
    prototype in one .c resolving to a definition in another .c is what the
    language says happens, and no `uses` clause could express it because C has
    none. Pascal's non-transitive rule stops at that boundary.
    bug-c-sibling-translation-units-cannot-see-each-other }
  if UnitIsCTranslationUnit(curUnit) and UnitIsCTranslationUnit(declUnit) then
  begin VisibilityAllows := True; Exit; end;
  { Beyond the cache's range: answer directly, without memoizing. Unreachable
    while ParseUnit caps CompiledUnitCount at 256, and present so that raising
    that cap is a one-line change rather than a silent out-of-bounds read —
    which is exactly the failure the MAX_STRS coupling was one step away from. }
  if (curUnit + 1 > MAX_UNITS) or (declUnit + 1 > MAX_UNITS) then
  begin
    for i := 0 to UsesEdgeCount - 1 do
      if (UsesEdgeFrom[i] = curUnit) and (UsesEdgeTo[i] = declUnit) then
      begin VisibilityAllows := True; Exit; end;
    VisibilityAllows := False;
    Exit;
  end;
  if (VisCacheUnit = curUnit) and (VisCacheEdges = UsesEdgeCount) then
  begin
    VisibilityAllows := VisCacheVis[declUnit + 1];
    Exit;
  end;
  VisCacheUnit := curUnit;
  VisCacheEdges := UsesEdgeCount;
  for i := 0 to MAX_UNITS do VisCacheVis[i] := False;
  VisCacheVis[curUnit + 1] := True;
  { the whole rule: the units curUnit itself named, either section }
  for i := 0 to UsesEdgeCount - 1 do
    if UsesEdgeFrom[i] = curUnit then
    begin
      v := UsesEdgeTo[i];
      VisCacheVis[v + 1] := True;
    end;
  { NO closure. There is deliberately nothing here. A `uses` clause names units
    in the namespace of the unit that WROTE it and in no other — including a
    clause written in the INTERFACE section, which is not a re-export.
    (user, 2026-08-15: "includes should never leak — they are in the namespace
    of the unit that included them, and never in any parent that happened to
    include that unit. no language i know automatically has global scope just
    because some unit included something.")
    This function used to walk interface edges transitively from every visible
    unit, which meant a program `uses`ing one unit could name everything that
    unit's interface reached, arbitrarily deep. FPC rejects all of it.
    Laxness INSIDE a unit (declare-before-use, forward references) is a
    separate and deliberate choice, and is unaffected. }
  VisibilityAllows := VisCacheVis[declUnit + 1];
end;

function DeclVisible(declUnit: Integer): Boolean;
{ The ENFORCEMENT predicate --strict-uses turns on: may the scope being compiled
  see a declaration that lives in `declUnit`? False means the row is skipped
  during lookup, so the name resolves somewhere else or is simply undefined —
  which is what a non-transitive `uses` means (bug-pascal-uses-is-transitive).

  `declUnit < 0` is ALWAYS visible, and that is not a loophole being left open
  by accident: -1 is two things at once in this table — a compiler-registered
  intrinsic (RegisterBuiltin*, and every proc the frontend mints, which
  MatchEligBase's `userOnly` test already reads as "not user code") and a
  routine declared by the main program. The first is System-ambient by
  definition; separating the second would need a marker the rows do not carry,
  and a unit reaching the program's own routine is not a case the corpus shows.
  Same artifact ClassNameIsAmbientIntrinsic handles by name on the class side. }
begin
  DeclVisible := True;
  if DeclVisibilityProbe then Exit;
  if declUnit < 0 then Exit;
  if declUnit = CurrentUnitIdx then Exit;
  DeclVisible := VisibilityAllows(CurrentUnitIdx, declUnit);
end;

function DeclVisibleBareRoutine(declUnit: Integer;
                                const name: AnsiString): Boolean;
{ DeclVisible for a BARE ROUTINE NAME, plus the one thing Python's import rule
  changes: a Pascal unit a NilPy `import` pulled in must not AMBUSH a Python
  builtin of the same name. `import math` links lib/rtl/math, whose Abs/Min/Max/
  Round then joined the candidate set — and which one won was decided by
  overload ranking over a file the user never opened. `max(1.5, 2)` answered 2.0
  where CPython answers the int 2, and the min/max TIE came back reversed.

  NARROW ON PURPOSE, and this is the interesting part. The rule is NOT "an
  imported unit's names are invisible", which is what strict Python would say:
  `import tk` then a bare `TkInit()` is code CPython would reject with a
  NameError, and NilPy accepting what CPython REJECTS is a documented FEATURE of
  this dialect, not a defect (devdocs/dev/nilpy-semantics-divergences.md — the
  compatibility promise runs one way, CPython-works implies NilPy-works). The
  first cut hid every routine and broke three tk examples that use exactly that
  laxness; only the AMBUSH is a bug, because there the user's own working
  meaning silently changes.

  ROUTINES ONLY, for the same reason from the other side. A CLASS from such a
  unit is reached through the qualifier (`class D(mixinproto.Proto)`), but once
  it is a base its members are resolved by the COMPILER, not by a name the user
  wrote — hiding those broke inherited-method lookup outright. Types, constants
  and symbols are the same case. So this sits at the routine lookups rather than
  inside DeclVisible.

  QualNameLookup turns it off for the frontend's own by-name lookups, which is
  how the `math.pow` shim still reaches Power.
  bug-nilpy-import-leaks-the-units-names-into-the-python-namespace }
begin
  DeclVisibleBareRoutine := DeclVisible(declUnit);
  if not DeclVisibleBareRoutine then Exit;
  if QualNameLookup or DeclVisibilityProbe then Exit;
  if not NilPyUserCode then Exit;
  if not UnitIsQualifiedOnly(declUnit) then Exit;
  if PythonSideDeclaresRoutine(name, declUnit) then
    DeclVisibleBareRoutine := False;
end;

procedure WarnUsesLeakHit(const kind, name: AnsiString; curUnit, declUnit: Integer);
{ One line per name that resolved through a unit not reachable from the
  resolving unit's own (transitively-closed, interface-only) uses graph —
  exactly what a real non-transitive uses rule would turn into "undefined
  identifier". Named the (importer, provider) pair, not the call site, per the
  ticket's counting goal: DISTINCT pairs matter more than call-site count. }
var fromName, toName: AnsiString;
begin
  if curUnit < 0 then fromName := '<program>' else fromName := Strs[curUnit].Text;
  if declUnit < 0 then toName := '<program>' else toName := Strs[declUnit].Text;
  Warn('uses-leak: ' + kind + ' ''' + name + ''' resolved from unit ''' +
       fromName + ''' through unreachable unit ''' + toName + '''');
end;

function FindUClassInUnit(const name: AnsiString; unitIdx: Integer): Integer;
var i: Integer; lo, name2: AnsiString;
begin
  Result := -1;
  name2 := name;
  lo := ULower(name2);
  i := 0;
  while i < UClsCount do
  begin
    if (UClsUnitIdx[i] = unitIdx) and UNameMatch(UClsNOff[i], UClsNLen[i], lo) then
    begin
      Result := i;
      Exit;
    end;
    Inc(i);
  end;
end;

function UsesRankOf(curUnit, declUnit: Integer): Integer;
{ How LATE `declUnit` is in curUnit's own uses clause — the LAST edge naming it,
  because `uses a, b` must let b hide a (FPC, and the routine half of
  bug-p-uses-order-does-not-decide-which-unit-wins). -1 for a unit curUnit never
  named: ambient/compiler-minted rows exist for everybody and must not outrank a
  unit the source actually asked for. Edges are appended as clauses are parsed,
  so the edge INDEX is the clause order.
  bug-p-scope-hiding-covers-routines-but-not-types-and-classes }
var i: Integer;
begin
  UsesRankOf := -1;
  { The scope's OWN declaration outranks everything it imported — that half of
    the rule already worked and must survive the ranking. }
  if declUnit = curUnit then begin UsesRankOf := 2147483647; Exit; end;
  for i := 0 to UsesEdgeCount - 1 do
    if (UsesEdgeFrom[i] = curUnit) and (UsesEdgeTo[i] = declUnit) then
      UsesRankOf := i;
end;

function FindUClass(const name: AnsiString): Integer;
var i, bestRank, r: Integer; lo, name2: AnsiString;
begin
  Result := -1;
  bestRank := -2;
  name2 := name;
  lo := ULower(name2);
  { A class declared in the unit being parsed wins over a same-named one
    elsewhere. Two libraries may legitimately export the same class name —
    tkinter's `Canvas` and reportlab's `Canvas` are both spellings their
    applications require — and with one flat namespace the first unit registered
    captured the name everywhere, so the second unit's own methods bound to the
    first unit's class and could not see their own fields.
    bug-pascal-duplicate-class-name-silently-shadows. }
  if CurrentUnitIdx >= 0 then
  begin
    i := 0;
    while i < UClsCount do
    begin
      if (UClsUnitIdx[i] = CurrentUnitIdx) and
         UNameMatch(UClsNOff[i], UClsNLen[i], lo) then begin Result := i; Exit; end;
      Inc(i);
    end;
  end;
  i := 0;
  while i < UClsCount do
  begin
    if UNameMatch(UClsNOff[i], UClsNLen[i], lo) then
    begin
      { NOT gated on CurrentUnitIdx >= 0 any more: every warn site was, so a
        leak into the MAIN PROGRAM — this ticket's own headline repro — was
        never counted, and the "35 pairs" figure is unit-to-unit only.
        UClsUnitIdx = -1 still passes the <> CurrentUnitIdx test at program
        scope, so a compiler-minted class is not reported as a leak to itself. }
      if WarnUsesLeak and (UClsUnitIdx[i] <> CurrentUnitIdx) and
         not ClassNameIsAmbientIntrinsic(lo) and
         not VisibilityAllows(CurrentUnitIdx, UClsUnitIdx[i]) then
        WarnUsesLeakHit('class', name, CurrentUnitIdx, UClsUnitIdx[i]);
      { --strict-uses: a class this scope cannot see is not a candidate, so the
        scan continues to a visible one of the same name rather than stopping at
        the first row. ClassNameIsAmbientIntrinsic keeps TObject/TGuid reachable
        (they are System's, stamped with the program's index). }
      if ClassNameIsAmbientIntrinsic(lo) or DeclVisible(UClsUnitIdx[i]) then
      begin
        { …and among the visible ones the LATEST-NAMED unit wins, rather than
          whichever registered first. `uses a, b` binds b's `Thing` exactly as
          it already binds b's routines: scope hiding shipped for procedures on
          2026-08-10 and reached types not at all, so one program answered
          ROUTINE-B and CLASS-A. FPC says B for both.
          A tie keeps the FIRST row, so nothing moves for the ordinary case of
          one declaration, for two rows from the same unit, or for two ambient
          rows (rank -1 each) — which is what leaves pylib's and sysutils'
          `Exception` merged the way bug-pascal-duplicate-class-name-silently-
          shadows needs. Ranking is over the CLAUSE ORDER, not registration
          order, and only among rows DeclVisible already accepted.
          bug-p-scope-hiding-covers-routines-but-not-types-and-classes }
        r := UsesRankOf(CurrentUnitIdx, UClsUnitIdx[i]);
        if (Result < 0) or (r > bestRank) then
        begin
          Result := i; bestRank := r;
        end;
      end;
    end;
    Inc(i);
  end;
  if Result >= 0 then Exit;
  { class-name alias (`TOptionList = TList;`) — resolve to the target row }
  for i := 0 to UClsAliasCount - 1 do
    if UNameMatch(UClsAliasNOff[i], UClsAliasNLen[i], lo) then
    begin
      Result := UClsAliasCi[i];
      Exit;
    end;
end;

procedure RegisterUClassAlias(noff, nlen, ci: Integer);
begin
  if UClsAliasCount >= MAX_TYPEALIAS then Error('too many class aliases');
  UClsAliasNOff[UClsAliasCount] := noff;
  UClsAliasNLen[UClsAliasCount] := nlen;
  UClsAliasCi[UClsAliasCount]   := ci;
  Inc(UClsAliasCount);
end;

function FindIMT(classCi, intfCi: Integer): Integer;
{ Index into the IMT table for (classCi, intfCi), walking the parent chain so a
  subclass inherits a parent's interface implementation. -1 if none. }
var i, cur: Integer;
begin
  Result := -1;
  cur := classCi;
  while cur >= 0 do
  begin
    for i := 0 to IMTCount - 1 do
      if (IMTClass[i] = cur) and (IMTIntf[i] = intfCi) then begin Result := i; Exit; end;
    cur := UClsParent[cur];
  end;
end;

function RecIsComInterface(recId: Integer): Boolean;
{ True iff this REC ID is a COM/ARC interface UCls (a reference-counted
  single-pointer interface value). Split out of SymIsComInterface because the
  same question has to be asked of an ARRAY's ELEMENT rec, where the symbol-level
  predicate deliberately answers False. }
var ci: Integer;
begin
  Result := False;
  if recId < REC_UCLASS_BASE then Exit;
  ci := recId - REC_UCLASS_BASE;
  if (ci < 0) or (ci >= UClsCount) then Exit;
  Result := UClsIsInterface[ci] and UClsIsComInterface[ci];
end;

function SymIsComInterface(symIdx: Integer): Boolean;
{ True iff the local/var symbol is a COM/ARC interface value (a reference-counted
  single-pointer interface value): modelled as a tyRecord whose rec id is a
  COM-interface UCls. ARRAYS answer False here on purpose — an array's slot is
  not itself a reference — so a caller that cares about `array[..] of IFoo` must
  ask RecIsComInterface about the ELEMENT rec (SymElemIsComInterface). }
begin
  Result := False;
  if (symIdx < 0) or (Syms[symIdx].TypeKind <> tyRecord) or Syms[symIdx].IsArray then Exit;
  { feature-a-typeref-migrate-consumers lane 1: RecName read via SymTR[..].RecId. }
  Result := RecIsComInterface(SymTR[symIdx].RecId);
end;

function SymElemIsComInterface(symIdx: Integer): Boolean;
{ True iff the symbol is a STATIC array whose ELEMENTS are COM/ARC interfaces —
  `keep: array[0..N] of IFoo`. Every managed-local pass keyed on
  SymIsComInterface alone, which answers False for an array, so such a local was
  neither zero-initialised nor released: the first `keep[i] := x` ran the ARC
  release on STACK GARBAGE and dispatched _Release through a junk IMT.
  bug-a-a-local-array-of-interfaces-is-not-zero-initialised }
begin
  Result := (symIdx >= 0) and Syms[symIdx].IsArray and (Syms[symIdx].ArrLen >= 0) and
            (SymElemDynDepth[symIdx] = 0) and (Syms[symIdx].TypeKind = tyRecord) and
            RecIsComInterface(SymTR[symIdx].ElemRec);
end;

function UMemberNameMatch(off, len, cls: Integer; const name, lo: AnsiString): Boolean;
{ Match a class MEMBER name (field / method / property) under the owning class's
  own case rule. `name` is the caller's spelling as written, `lo` its ULower —
  both are passed so neither path has to re-fold per candidate.

  The rule is per-DECLARING-class, which is what makes a mixed hierarchy work:
  a NilPy class deriving from a Pascal/pylib one distinguishes `run` from `Run`
  among its own methods while still reaching the base's `Free`/`Destroy`/
  `GetEnumerator` spelled any way the lowering happens to spell them. }
begin
  if UClsCaseSensFields[cls] then
    UMemberNameMatch := UNameMatchCS(off, len, name)
  else
    UMemberNameMatch := UNameMatch(off, len, lo);
end;

function FindUField(ci: Integer; const name: AnsiString): Integer;
var i, base, cnt: Integer; lo, name2: AnsiString; curr: Integer; hit: Boolean;
begin
  Result := -1;
  name2 := name;
  lo := ULower(name2);
  curr := ci;
  while curr >= 0 do
  begin
    base := UClsFBase[curr];
    cnt  := UClsFCount[curr];
    i := 0;
    while i < cnt do
    begin
      hit := UMemberNameMatch(UFldNOff[base + i], UFldNLen[base + i], curr, name, lo);
      if hit then begin Result := base + i; Exit; end;
      Inc(i);
    end;
    curr := UClsParent[curr];
  end;
end;

function FindUMeth(ci: Integer; const name: AnsiString): Integer;
var i, base, cnt: Integer; lo, name2: AnsiString; curr: Integer; hit: Boolean;
begin
  Result := -1;
  name2 := name;
  lo := ULower(name2);
  curr := ci;
  while curr >= 0 do
  begin
    base := UClsMBase[curr];
    cnt  := UClsMCount[curr];
    i := 0;
    while i < cnt do
    begin
      hit := UMemberNameMatch(UMthNOff[base + i], UMthNLen[base + i], curr, name, lo);
      if hit then begin Result := base + i; Exit; end;
      Inc(i);
    end;
    curr := UClsParent[curr];
  end;
end;

function IsSubclassOf(otherCi, ci: Integer): Boolean;
var curr: Integer;
begin
  Result := False;
  curr := UClsParent[otherCi];
  while curr >= 0 do
  begin
    if curr = ci then begin Result := True; Exit; end;
    curr := UClsParent[curr];
  end;
end;

function FindParentVirtualSlot(parentCi: Integer; const name: AnsiString): Integer;
var curr, mmi: Integer;
begin
  Result := -1;
  curr := parentCi;
  while curr >= 0 do
  begin
    mmi := FindUMeth(curr, name);
    if (mmi >= 0) and (UMthVirSlot[mmi] >= 0) then
    begin
      Result := UMthVirSlot[mmi];
      Exit;
    end;
    curr := UClsParent[curr];
  end;
end;

function ResolveVMTSlotProc(ci, slot: Integer): Integer;
{ Effective proc occupying virtual slot `slot` for class ci: search ci's own
  methods first (an override wins), then walk ancestors. -1 if none. }
var curr, i, base, cnt: Integer;
begin
  Result := -1;
  curr := ci;
  while curr >= 0 do
  begin
    base := UClsMBase[curr]; cnt := UClsMCount[curr];
    for i := 0 to cnt - 1 do
      if UMthVirSlot[base + i] = slot then
      begin
        Result := UMthProc_[base + i];
        Exit;
      end;
    curr := UClsParent[curr];
  end;
end;

function FindUProp(ci: Integer; const name: AnsiString): Integer;
var i, base, cnt: Integer; lo, name2: AnsiString; curr: Integer;
begin
  Result := -1;
  name2 := name;
  lo := ULower(name2);
  curr := ci;
  while curr >= 0 do
  begin
    base := UClsPBase[curr];
    cnt  := UClsPCount[curr];
    i := 0;
    while i < cnt do
    begin
      if UMemberNameMatch(UPropNOff[base + i], UPropNLen[base + i], curr, name, lo) then begin Result := base + i; Exit; end;
      Inc(i);
    end;
    curr := UClsParent[curr];
  end;
end;

{ The default indexed property of a class (walking ancestors), or -1. Drives the
  `obj[i]` shorthand. }
function FindDefaultProp(ci: Integer): Integer;
var i, base, cnt, curr: Integer;
begin
  Result := -1;
  curr := ci;
  while curr >= 0 do
  begin
    base := UClsPBase[curr];
    cnt  := UClsPCount[curr];
    i := 0;
    while i < cnt do
    begin
      if UPropIsDefault[base + i] then begin Result := base + i; Exit; end;
      Inc(i);
    end;
    curr := UClsParent[curr];
  end;
end;

function AddUProperty(ci, noff, nlen, tk, recId: Integer): Integer;
var pri: Integer;
begin
  { Overflow here silently corrupts the sibling UProp* parallel arrays (the
    entry spills into the NEXT array's low indices) -- flipping random flags
    like UPropIsIndexed on unrelated properties, order-dependently
    (bug-property-setter-resolution-uses-order). Fail loudly instead. }
  if UPropCount >= MAX_UPROP then Error('too many class properties (MAX_UPROP)');
  pri := UPropCount;
  UPropNOff[pri] := noff; UPropNLen[pri] := nlen;
  UPropTk[pri] := tk; UPropRec[pri] := recId;
  UPropReadFOff[pri] := 0; UPropReadFLen[pri] := 0;
  UPropReadMOff[pri] := 0; UPropReadMLen[pri] := 0;
  UPropWriteFOff[pri] := 0; UPropWriteFLen[pri] := 0;
  UPropWriteMOff[pri] := 0; UPropWriteMLen[pri] := 0;
  UPropPub[pri] := 0;
  UPropEnumId[pri] := -1;
  UPropSetEnumId[pri] := -1;
  UPropIsIndexed[pri] := False;
  UPropIsDefault[pri] := False;
  UPropCount := UPropCount + 1;
  UClsPCount[ci] := UClsPCount[ci] + 1;
  Result := pri;
end;

function AddUClass(off, len: Integer): Integer;
begin
  if UClsCount >= MAX_UCLASS then Error('too many classes/records (MAX_UCLASS)');
  Result := UClsCount;
  UClsNOff[UClsCount]   := off;
  UClsNLen[UClsCount]   := len;
  UClsSize_[UClsCount]  := 0;
  UClsAlign[UClsCount]  := 1;
  UClsFBase[UClsCount]  := UFldCount;
  UClsFCount[UClsCount] := 0;
  UClsMBase[UClsCount]  := UMthCount;
  UClsMCount[UClsCount] := 0;
  UClsPBase[UClsCount]  := UPropCount;
  UClsPCount[UClsCount] := 0;
  UClsParent[UClsCount] := -1;
  UClsUnitIdx[UClsCount] := CurrentUnitIdx;   { declaring unit — access-control scope }
  UClsVirtCount[UClsCount] := 0;
  UClsVMTOffset[UClsCount] := -1;
  UClsIsRecord[UClsCount] := False;
  UClsSealed[UClsCount] := False;
  UClsAbstractCls[UClsCount] := False;
  UClsIsInterface[UClsCount] := False;
  UClsHelperTk[UClsCount] := -1;
  UClsHelperRec[UClsCount] := REC_NONE;
  UClsForward[UClsCount] := False;
  { NilPy classes are Python classes: `self.c` and `self.C` are two attributes
    and `def Run` is not `def run` (bug-nilpy-identifiers-are-case-insensitive).
    Same reason C sets this for structs; Pascal classes stay case-insensitive. }
  UClsCaseSensFields[UClsCount] := NilPyUserCode;
  UClsCount := UClsCount + 1;
end;

function FindHelperForType(tk: TTypeKind; rec: Integer): Integer;
{ Newest-declared TYPE HELPER whose target matches (tk, rec); -1 if none.
  FPC scoping: the last visible helper wins, hence the downward scan. The two
  string flavours (frozen tyString / managed tyAnsiString) are one family —
  an AnsiString helper serves a frozen-string receiver too. }
var i, want, have: Integer;
begin
  Result := -1;
  want := Ord(tk);
  for i := UClsCount - 1 downto 0 do
  begin
    have := UClsHelperTk[i];
    if have < 0 then continue;
    if (have = want) or
       (((have = Ord(tyString)) or (have = Ord(tyAnsiString))) and
        ((want = Ord(tyString)) or (want = Ord(tyAnsiString)))) then
      if (UClsHelperRec[i] = rec) or (UClsHelperRec[i] = REC_NONE) or (rec = REC_NONE) then
      begin
        Result := i;
        Exit;
      end;
  end;
end;

function EnsureMethodPtrRec: Integer;
{ Record id of the shared 16-byte method-pointer layout {Code@0, Data@8}. Minted
  lazily on the first `procedure(...) of object` type. No named fields are needed:
  the method-pointer assignment (@obj.method) and call read Code/Data by fixed
  offset, so only the 16-byte size + 8-byte alignment matter. }
var ci: Integer;
begin
  if MethodPtrRecId <> REC_NONE then begin Result := MethodPtrRecId; Exit; end;
  ci := AddUClass(0, 0);
  UClsSize_[ci]    := 16;
  UClsAlign[ci]    := 8;
  UClsIsRecord[ci] := True;
  MethodPtrRecId := REC_UCLASS_BASE + ci;
  Result := MethodPtrRecId;
end;

procedure EnsureUFieldCapacity(need: Integer);
{ Grow the UFld* field-pool arrays so index `need-1` is in bounds (the ArrDim arrays
  are 2-D, sized need*MAX_ARR_DIMS). Doubling from 16384; capacity never shrinks across
  the per-frontend UFldCount reset. ALL parallel arrays grow in lockstep. See
  feature-dynamic-compiler-tables. }
var n: Integer;
begin
  if need <= UFldCapacity then Exit;
  if UFldCapacity = 0 then n := 16384 else n := UFldCapacity;
  while n < need do n := n * 2;
  SetLength(UFldNOff, n);       SetLength(UFldNLen, n);         SetLength(UFldOff_, n);
  SetLength(UFldTk, n);         SetLength(UFldRec_, n);         SetLength(UFldAnonRec, n);
  SetLength(UFldPtrElemTk, n);  SetLength(UFldPtrElemRec, n);   SetLength(UFldPtrAlias, n);
  SetLength(UFldProcSig, n);    SetLength(UFldElemProcSig, n);  SetLength(UFldIsArray, n);
  SetLength(UFldArrLen, n);     SetLength(UFldDynDepth, n);     SetLength(UFldPub, n);
  SetLength(UFldVis, n);        SetLength(UFldStrCap, n);       SetLength(UFldIsSub, n);
  SetLength(UFldSubLo, n);      SetLength(UFldSubHi, n);        SetLength(UFldSetEnumId, n);
  SetLength(UFldSetElemTk, n);  SetLength(UFldBitWidth, n);     SetLength(UFldBitShift, n);
  SetLength(UFldBitBytes, n);   SetLength(UFldArrNDims, n);
  SetLength(UFldArrDimLo, n * MAX_ARR_DIMS);   SetLength(UFldArrDimSpan, n * MAX_ARR_DIMS);
  UFldCapacity := n;
end;

procedure AddUField(ci, noff, nlen, byteOff, tk, recId: Integer);
var fi, k, src, dst: Integer;
begin
  EnsureUFieldCapacity(UFldCount + 1);
  { Empty window re-base: AddUClass stamps UClsFBase at CLASS-CREATION time, so a
    frontend that creates struct SHELLS up front then fills fields later (rparser's
    two-pass, so a field type can reference another struct) leaves every empty
    class pointing at the then-current tail. The first field of a NON-first shell
    would append at the live tail while UClsFBase still holds a stale earlier index
    — the window then overlaps an earlier class's fields (bug-uclass-field-window-
    stale-base: two field-bearing structs, second reads the first's slot). Re-anchor
    an empty window to the tail before appending. Safe vs the two special cases
    below: both the anonymous-record relocation and the C parser's manual re-anchor
    only fire for FCount>0; an empty window carries no data to move. }
  if UClsFCount[ci] = 0 then UClsFBase[ci] := UFldCount;
  { The field window [UClsFBase[ci] .. +UClsFCount[ci]) must stay contiguous
    (FindUField/RecordHasManagedFields walk it as a range). A nested anonymous
    record type parsed mid-record (feature-anonymous-record-type) mints its
    own UCls row and registers ITS fields between two of ours — when that
    happened, relocate our fields so far to the tail and re-base. }
  { Strictly BEHIND the tail only: the C struct parser re-anchors UClsFBase[ci]
    to the tail before re-appending buffered fields while UClsFCount[ci] still
    holds a previous definition's count — that manual-rebase state (window
    extending PAST the tail) must be left alone. }
  if (UClsFCount[ci] > 0) and (UClsFBase[ci] + UClsFCount[ci] < UFldCount) then
  begin
    EnsureUFieldCapacity(UFldCount + UClsFCount[ci] + 1);   { relocation writes [dst..dst+UClsFCount) }
    dst := UFldCount;
    for k := 0 to UClsFCount[ci] - 1 do
    begin
      src := UClsFBase[ci] + k;
      UFldNOff[dst+k] := UFldNOff[src];  UFldNLen[dst+k] := UFldNLen[src];
      UFldOff_[dst+k] := UFldOff_[src];  UFldTk[dst+k] := UFldTk[src];
      UFldRec_[dst+k] := UFldRec_[src];  UFldProcSig[dst+k] := UFldProcSig[src];
      UFldElemProcSig[dst+k] := UFldElemProcSig[src];
      UFldAnonRec[dst+k] := UFldAnonRec[src];
      UFldPtrElemTk[dst+k] := UFldPtrElemTk[src];
      UFldPtrElemRec[dst+k] := UFldPtrElemRec[src];
      UFldPtrAlias[dst+k] := UFldPtrAlias[src];
      UFldSetEnumId[dst+k] := UFldSetEnumId[src];
      UFldSetElemTk[dst+k] := UFldSetElemTk[src];
      UFldIsArray[dst+k] := UFldIsArray[src];  UFldArrLen[dst+k] := UFldArrLen[src];
      UFldDynDepth[dst+k] := UFldDynDepth[src];
      UFldArrNDims[dst+k] := UFldArrNDims[src];
      UFldBitWidth[dst+k] := UFldBitWidth[src];
      UFldBitShift[dst+k] := UFldBitShift[src];
      UFldBitBytes[dst+k] := UFldBitBytes[src];
      UFldPub[dst+k] := UFldPub[src];
      UFldVis[dst+k] := UFldVis[src];
      UFldStrCap[dst+k] := UFldStrCap[src];
      UFldIsSub[dst+k] := UFldIsSub[src];
      UFldSubLo[dst+k] := UFldSubLo[src];
      UFldSubHi[dst+k] := UFldSubHi[src];
      for fi := 0 to MAX_ARR_DIMS - 1 do
      begin
        UFldArrDimLo[(dst+k) * MAX_ARR_DIMS + fi]   := UFldArrDimLo[src * MAX_ARR_DIMS + fi];
        UFldArrDimSpan[(dst+k) * MAX_ARR_DIMS + fi] := UFldArrDimSpan[src * MAX_ARR_DIMS + fi];
      end;
    end;
    UClsFBase[ci] := dst;
    UFldCount := UFldCount + UClsFCount[ci];
  end;
  EnsureUFieldCapacity(UFldCount + 1);   { the single-field append below writes slot UFldCount (may have grown via inherit) }
  fi := UFldCount;
  UFldNOff[fi] := noff;  UFldNLen[fi] := nlen;
  UFldOff_[fi] := byteOff; UFldTk[fi] := tk; UFldRec_[fi] := recId;
  UFldAnonRec[fi] := REC_NONE;   { anon-promotion marker; C struct parser overrides for flattened anon members }
  { Procedural-type field: remember the signature so `rec.field(args)` can lower
    to an indirect call (LastTypeProcSig set by ParseTypeKind for the field type;
    a plain proc field is tyPointer, a method-pointer field tyRecord). }
  UFldProcSig[fi] := LastTypeProcSig;
  UFldElemProcSig[fi] := -1;   { ptr-to-fn-ptr field sig: C struct builder overrides post-AddUField; Pascal fields never set it }
  if tk = Ord(tyPointer) then
  begin
    UFldPtrElemTk[fi] := Ord(LastTypePointerElemTk);
    UFldPtrElemRec[fi] := LastTypePointerElemRec;
    UFldPtrAlias[fi] := LastTypePointerAlias;
  end
  else
  begin
    UFldPtrElemTk[fi] := Ord(tyUnknown);
    UFldPtrElemRec[fi] := REC_NONE;
    UFldPtrAlias[fi] := -1;
  end;
  if tk = Ord(tySet) then
  begin
    UFldSetEnumId[fi] := LastTypeSetEnumId;
    UFldSetElemTk[fi] := LastTypeSetElemTk;
  end
  else
  begin
    UFldSetEnumId[fi] := -1;
    UFldSetElemTk[fi] := 0;
  end;
  UFldIsArray[fi] := False;
  UFldArrLen[fi] := 1;
  UFldDynDepth[fi] := 0;
  UFldArrNDims[fi] := 0;
  UFldBitWidth[fi] := 0;
  UFldBitShift[fi] := 0;
  UFldBitBytes[fi] := 0;
  UFldPub[fi] := 0;
  UFldVis[fi] := VIS_PUBLIC;
  UFldStrCap[fi] := 0;
  UFldIsSub[fi] := LastTypeIsSub;
  if LastTypeIsSub then
  begin
    UFldSubLo[fi] := LastTypeSubLo;
    UFldSubHi[fi] := LastTypeSubHi;
  end;
  UFldCount := UFldCount + 1;
  UClsFCount[ci] := UClsFCount[ci] + 1;
end;

procedure AddUMeth(ci, noff, nlen, procIdx: Integer);
var mi, k, src, dst: Integer;
begin
  if UMthCount >= MAX_UMETH then Error('too many class/record methods (MAX_UMETH)');
  { The method window [UClsMBase[ci] .. +UClsMCount[ci]) must stay contiguous
    (FindUMeth walks it as a range). A NESTED specialization inside a class
    body (fgl's `TFPGListEnumeratorSpec = specialize ...` class-local type)
    registers ITS methods between two of ours — relocate ours to the tail and
    re-base, mirroring AddUField's window relocation. }
  if (UClsMCount[ci] > 0) and (UClsMBase[ci] + UClsMCount[ci] < UMthCount) then
  begin
    if UMthCount + UClsMCount[ci] >= MAX_UMETH then
      Error('too many class/record methods (MAX_UMETH)');
    dst := UMthCount;
    for k := 0 to UClsMCount[ci] - 1 do
    begin
      src := UClsMBase[ci] + k;
      UMthNOff[dst+k] := UMthNOff[src];
      UMthNLen[dst+k] := UMthNLen[src];
      UMthProc_[dst+k] := UMthProc_[src];
      UMthVirSlot[dst+k] := UMthVirSlot[src];
      UMthIsStatic[dst+k] := UMthIsStatic[src];
      UMthIsCtor[dst+k] := UMthIsCtor[src];
      UMthPub[dst+k] := UMthPub[src];
      UMthVis[dst+k] := UMthVis[src];
    end;
    UClsMBase[ci] := dst;
    UMthCount := UMthCount + UClsMCount[ci];
    if UMthCount >= MAX_UMETH then Error('too many class/record methods (MAX_UMETH)');
  end;
  mi := UMthCount;
  UMthNOff[mi] := noff; UMthNLen[mi] := nlen; UMthProc_[mi] := procIdx;
  UMthVirSlot[mi] := -1;
  UMthIsStatic[mi] := False;
  UMthIsCtor[mi] := False;
  UMthPub[mi] := 0;
  UMthVis[mi] := VIS_PUBLIC;
  UMthCount := UMthCount + 1;
  UClsMCount[ci] := UClsMCount[ci] + 1;
end;

{ ===== Record Helper Functions ===== }

const
  REC_TTOKEN = 1;
  REC_TSTRENTRY = 2;
  REC_TFIXUP = 3;
  REC_TGLOBFIX = 4;
  REC_TCALLFIX = 5;
  REC_TSYMBOL = 6;
  REC_TPARAM = 7;
  REC_TPROC = 8;
  REC_TRAWTOKEN = 9;
  REC_TMYCLASS = 10;
  REC_TTEMPLATE = 11;
  REC_TSPECIALIZATION = 12;
  REC_TGENERICFUNC = 13;
  REC_TPENDINGGFSPEC = 14;

function IsRecordType(const lo: AnsiString): Integer;
var ci: Integer; lo2: AnsiString;
begin
  Result := REC_NONE;
  if lo = 'TToken' then Result := REC_TTOKEN
  else if lo = 'TStrEntry' then Result := REC_TSTRENTRY
  else if lo = 'TFixup' then Result := REC_TFIXUP
  else if lo = 'TGlobFix' then Result := REC_TGLOBFIX
  else if lo = 'TCallFix' then Result := REC_TCALLFIX
  else if lo = 'TSymbol' then Result := REC_TSYMBOL
  else if lo = 'TParam' then Result := REC_TPARAM
  else if lo = 'TProc' then Result := REC_TPROC
  else if lo = 'TRawToken' then Result := REC_TRAWTOKEN
  else if lo = 'TTemplate' then Result := REC_TTEMPLATE
  else if lo = 'TSpecialization' then Result := REC_TSPECIALIZATION
  else if lo = 'TGenericFunc' then Result := REC_TGENERICFUNC
  else if lo = 'TPendingGFSpec' then Result := REC_TPENDINGGFSPEC
  else if lo = 'TMethodFixup' then Result := REC_TMETHODFIXUP;
  if Result = REC_NONE then
  begin
    lo2 := lo;
    ci := FindUClass(lo2);
    if (ci >= 0) and UClsIsRecord[ci] then Result := REC_UCLASS_BASE + ci;
  end;
end;

{ The CLASS of that name, skipping same-named RECORDS. FindUClass returns the
  first row whatever it is, and the RTL has a `Text` record (the file type), so
  a façade class called Text — the name a tkinter application writes — was
  invisible: `Text(master, wrap=...)` was read as a record TYPECAST, which
  parses with one argument and fails with two.
  decide-class-namespace-scoping. }
function FindUClassNonRecord(const name: AnsiString): Integer;
{ …under the SAME visibility and scope-hiding rule as FindUClass. This scan was
  flat and global, and that is the whole of
  bug-a-tkinters-text-class-captures-the-rtl-text-record-in-other-units: a
  program saying `uses tkinter, configparser` stopped compiling INSIDE
  lib/rtl/configparser.pas, whose own `var f: Text` means the RTL FILE record —
  lib/pcl's `Text = class(Widget)` answered a question asked by a unit that
  never named tkinter, and `Assign(f, path)` then had a class where a record
  belonged. configparser alone compiles; adding tkinter elsewhere in the program
  was the entire difference.

  Preferring the CLASS over a same-named RECORD is still right where the asker
  is a NilPy class position (bug-nilpy-text-class-name-binds-the-rtl-file-record
  wired this predicate in for exactly that). It was only ever wrong because it
  answered for scopes that cannot see the class at all — so the fix is the
  visibility rule, not a fourth mechanism on top of the three lib/pcl already
  carries for the flat namespace. }
var i, bestRank, r: Integer; lo, name2: AnsiString;
begin
  Result := -1;
  bestRank := -2;
  name2 := name;
  lo := ULower(name2);
  for i := 0 to UClsCount - 1 do
    if (not UClsIsRecord[i]) and UNameMatch(UClsNOff[i], UClsNLen[i], lo) and
       (ClassNameIsAmbientIntrinsic(lo) or DeclVisible(UClsUnitIdx[i])) then
    begin
      r := UsesRankOf(CurrentUnitIdx, UClsUnitIdx[i]);
      if (Result < 0) or (r > bestRank) then begin Result := i; bestRank := r; end;
    end;
  if Result >= 0 then Exit;
  { Class-name ALIASES too, exactly as FindUClass resolves them. Without this
    the two predicates disagree about the same name, and the NilPy construction
    intercept (pasparser_lval.inc, `FindUClassNonRecord(...) and next is '('`) stood
    down for an alias while the Pascal typecast branch below it — which asks
    IsClassType, i.e. FindUClass, i.e. alias-AWARE — claimed it. So
    `AliasName(9)` compiled as a hard reinterpret cast of the integer 9 to a
    class pointer and segfaulted on the first member access, while
    `RealName(9)` constructed normally
    (bug-nilpy-from-import-as-alias-is-discarded found it; it is not specific
    to imports — any class alias reached from NilPy had it). }
  for i := 0 to UClsAliasCount - 1 do
    if UNameMatch(UClsAliasNOff[i], UClsAliasNLen[i], lo) and
       (UClsAliasCi[i] >= 0) and (not UClsIsRecord[UClsAliasCi[i]]) then
    begin
      Result := UClsAliasCi[i];
      Exit;
    end;
end;

{ Is there a CLASS of this name? Asks FindUClassNonRecord, not FindUClass:
  FindUClass answers with the FIRST row of that name whatever it is, so testing
  `not UClsIsRecord[ci]` on it answered FALSE whenever a same-named RECORD came
  first — even though a class of that name also existed. The RTL's `Text` (the
  file record) sits ahead of `lib/pcl`'s `Text = class(Widget)`, so
  `IsClassType('Text')` was False and every gate keyed on it stood down: a
  `Text` field fell back to dynamic, `class H(Text)` inherited the record, and
  `self.t = tk.Text(...)` was a compile error, while `Canvas` beside it was
  fine. One predicate, the ticket's three faces.
  bug-nilpy-text-class-name-binds-the-rtl-file-record. }
function IsClassType(const lo: AnsiString): Boolean;
var lo2: AnsiString;
begin
  lo2 := lo;
  Result := FindUClassNonRecord(lo2) >= 0;
end;

const
  BRF_SCALAR8 = 1;
  BRF_STRING = 2;
  BRF_RECORD_ARRAY = 3;
  BRF_SCALAR4 = 4;

function RecSize(rec: Integer): Integer; forward;

function BuiltinRecFieldCount(rec: Integer): Integer;
begin
  Result := 0;
  case rec of
    REC_TTOKEN: Result := 4;
    REC_TSTRENTRY: Result := 3;
    REC_TFIXUP, REC_TGLOBFIX, REC_TCALLFIX, REC_TMYCLASS, REC_TMETHODFIXUP: Result := 2;
    REC_TSYMBOL: Result := 13;
    REC_TPARAM: Result := 5;
    REC_TPROC: Result := 9;
    REC_TRAWTOKEN: Result := 5;
    REC_TTEMPLATE: Result := 4;
    REC_TSPECIALIZATION: Result := 4;
    REC_TGENERICFUNC: Result := 5;
    REC_TPENDINGGFSPEC: Result := 4;
  end;
end;

function BuiltinRecFieldName(rec, idx: Integer): AnsiString;
begin
  Result := '';
  case rec of
    REC_TTOKEN:
      case idx of
        0: Result := 'Kind'; 1: Result := 'SVal';
        2: Result := 'IVal'; 3: Result := 'Line';
      end;
    REC_TSTRENTRY:
      case idx of
        0: Result := 'Text'; 1: Result := 'Offset'; 2: Result := 'Len';
      end;
    REC_TFIXUP:
      case idx of 0: Result := 'CodePos'; 1: Result := 'DataOff'; end;
    REC_TGLOBFIX:
      case idx of 0: Result := 'CodePos'; 1: Result := 'BSSoff'; end;
    REC_TCALLFIX:
      case idx of 0: Result := 'CodePos'; 1: Result := 'ProcIdx'; end;
    REC_TSYMBOL:
      case idx of
        0: Result := 'Name'; 1: Result := 'TypeKind';
        2: Result := 'Kind'; 3: Result := 'Offset';
        4: Result := 'ConstVal'; 5: Result := 'IsArray';
        6: Result := 'ArrLen'; 7: Result := 'ElemType';
        8: Result := 'RecName'; 9: Result := 'ElemRecName';
        10: Result := 'IsRef'; 11: Result := 'PtrElemTk';
        12: Result := 'PtrElemRec';
      end;
    REC_TPARAM:
      case idx of
        0: Result := 'Name'; 1: Result := 'TypeKind';
        2: Result := 'SymIdx'; 3: Result := 'IsRef';
        4: Result := 'IsArray';
      end;
    REC_TPROC:
      case idx of
        0: Result := 'Name'; 1: Result := 'IsFunc';
        2: Result := 'RetType'; 3: Result := 'ParamCount';
        4: Result := 'Params'; 5: Result := 'BodyAddr';
        6: Result := 'FramePatch'; 7: Result := 'RetSymIdx';
        8: Result := 'ScopeBase';
      end;
    REC_TRAWTOKEN:
      case idx of
        0: Result := 'Kind'; 1: Result := 'IVal';
        2: Result := 'Line'; 3: Result := 'SOffset';
        4: Result := 'SLen';
      end;
    REC_TMYCLASS:
      case idx of 0: Result := 'x'; 1: Result := 'y'; end;
    REC_TTEMPLATE:
      case idx of
        0: Result := 'Name'; 1: Result := 'Param';
        2: Result := 'TokStart'; 3: Result := 'TokCount';
      end;
    REC_TSPECIALIZATION:
      case idx of
        0: Result := 'Name'; 1: Result := 'TemplateName';
        2: Result := 'ConcreteType'; 3: Result := 'ConcreteName';
      end;
    REC_TGENERICFUNC:
      case idx of
        0: Result := 'Name'; 1: Result := 'Param';
        2: Result := 'IsFunc'; 3: Result := 'TokStart';
        4: Result := 'TokCount';
      end;
    REC_TPENDINGGFSPEC:
      case idx of
        0: Result := 'GenFuncIdx'; 1: Result := 'ConcreteKind';
        2: Result := 'ConcreteName'; 3: Result := 'SpecName';
      end;
    REC_TMETHODFIXUP:
      case idx of 0: Result := 'DataPos'; 1: Result := 'ProcIdx'; end;
  end;
end;

function BuiltinRecFieldKind(rec, idx: Integer): Integer;
begin
  Result := BRF_SCALAR8;
  case rec of
    REC_TTOKEN:
      if idx = 1 then Result := BRF_STRING;
    REC_TSTRENTRY:
      if idx = 0 then Result := BRF_STRING;
    REC_TSYMBOL:
      if idx = 0 then Result := BRF_STRING;
    REC_TPARAM:
      if idx = 0 then Result := BRF_STRING;
    REC_TPROC:
      if idx = 0 then Result := BRF_STRING
      else if idx = 4 then Result := BRF_RECORD_ARRAY;
    REC_TTEMPLATE:
      if (idx = 0) or (idx = 1) then Result := BRF_STRING;
    REC_TSPECIALIZATION:
      if (idx = 0) or (idx = 1) or (idx = 3) then Result := BRF_STRING;
    REC_TGENERICFUNC:
      if (idx = 0) or (idx = 1) then Result := BRF_STRING;
    REC_TPENDINGGFSPEC:
      if (idx = 2) or (idx = 3) then Result := BRF_STRING;
    REC_TMETHODFIXUP:
      Result := BRF_SCALAR4;
  end;
end;

function BuiltinRecFieldType(rec, idx: Integer): TTypeKind;
begin
  Result := tyInteger;
  if BuiltinRecFieldKind(rec, idx) = BRF_STRING then
  begin
    if PasDefineExists('PXX_MANAGED_STRING') then Result := tyAnsiString
    else Result := tyString;
    Exit;
  end;
  if BuiltinRecFieldKind(rec, idx) = BRF_RECORD_ARRAY then
  begin
    Result := tyRecord;
    Exit;
  end;
  case rec of
    REC_TTOKEN:
      if idx = 2 then Result := tyInt64;
    REC_TRAWTOKEN:
      if idx = 1 then Result := tyInt64;
    REC_TSYMBOL:
      if idx = 4 then Result := tyInt64
      else if (idx = 5) or (idx = 10) then Result := tyBoolean;
    REC_TPARAM:
      if (idx = 3) or (idx = 4) then Result := tyBoolean;
    REC_TPROC:
      if idx = 1 then Result := tyBoolean;
    REC_TGENERICFUNC:
      if idx = 2 then Result := tyBoolean;
  end;
end;

function BuiltinRecFieldRecId(rec, idx: Integer): Integer;
begin
  Result := REC_NONE;
  if (rec = REC_TPROC) and (idx = 4) then Result := REC_TPARAM;
end;

function BuiltinRecFieldArrayCount(rec, idx: Integer): Integer;
begin
  Result := 0;
  { MUST track TProc.Params' declared bound in defs.inc. This descriptor is
    what the compiler uses for its OWN TProc when self-compiling; a stale
    count here silently laid out Procs[] with the old extent while code
    written against the new bound overran into BodyAddr and beyond
    (bug-max-proc-params-32-selfmiscompile: Params[16].Name aliased
    BodyAddr = -1 -> AnsiStrRelease(-1) SIGSEGV). NOTE the value is baked
    into the COMPILING binary, so growing MAX_PROC_PARAMS takes an extra
    self-host generation to converge (gen1 mislays its own Procs; gen2+
    are correct) — reseed with the converged binary. }
  if (rec = REC_TPROC) and (idx = 4) then Result := MAX_PROC_PARAMS;
end;

function BuiltinRecFieldSize(rec, idx: Integer): Integer;
begin
  Result := 8;
  case BuiltinRecFieldKind(rec, idx) of
    BRF_STRING:
      if PasDefineExists('PXX_MANAGED_STRING') then Result := TARGET_PTR_SIZE
      else Result := LOCAL_STR_CAP + 8;
    BRF_RECORD_ARRAY:
      Result := BuiltinRecFieldArrayCount(rec, idx) *
                RecSize(BuiltinRecFieldRecId(rec, idx));
    BRF_SCALAR4:
      Result := 4;
  end;
end;

function BuiltinRecFieldMatches(rec, idx: Integer; const field: AnsiString): Boolean;
begin
  if rec = REC_TMYCLASS then
    Result := ((idx = 0) and ((field = 'x') or (field = 'X'))) or
              ((idx = 1) and ((field = 'y') or (field = 'Y')))
  else
    Result := field = BuiltinRecFieldName(rec, idx);
end;

function RecSize(rec: Integer): Integer;
var i, cnt: Integer;
begin
  Result := 8;
  cnt := BuiltinRecFieldCount(rec);
  if cnt > 0 then
  begin
    Result := 0;
    for i := 0 to cnt - 1 do
      Result := Result + BuiltinRecFieldSize(rec, i);
  end
  else if rec >= REC_UCLASS_BASE then Result := UClsSize_[rec - REC_UCLASS_BASE];
end;

function RecFieldOffset(rec: Integer; const field: AnsiString): Integer;
var fi, i, cnt, off: Integer; field2: AnsiString;
begin
  Result := 0; fi := 0; field2 := field;
  cnt := BuiltinRecFieldCount(rec);
  if cnt > 0 then
  begin
    off := 0;
    for i := 0 to cnt - 1 do
    begin
      if BuiltinRecFieldMatches(rec, i, field) then
      begin
        Result := off;
        Exit;
      end;
      off := off + BuiltinRecFieldSize(rec, i);
    end;
  end
  else if rec >= REC_UCLASS_BASE then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := UFldOff_[fi];
  end;
end;

function RecFieldType(rec: Integer; const field: AnsiString): TTypeKind;
var fi, i, cnt: Integer; field2: AnsiString;
begin
  Result := tyInteger; fi := 0; field2 := field;
  cnt := BuiltinRecFieldCount(rec);
  if cnt > 0 then
  begin
    for i := 0 to cnt - 1 do
      if BuiltinRecFieldMatches(rec, i, field) then
      begin
        Result := BuiltinRecFieldType(rec, i);
        Exit;
      end;
    { A BUILTIN record's field names are compiler-authored, so a miss is always
      a typo — never a legitimate probe. Falling through used to return the
      tyInteger-at-offset-0 default, which STORES to the wrong offset: writing
      `Procs[i].Params[j].ProcSig` (TParam has no such field) clobbered a
      neighbouring field and segfaulted an unrelated NilPy test, with no
      diagnostic. Only the FPC seed canary caught it.

      RequireRecMember cannot cover this: it is gated on recId >= REC_UCLASS_BASE
      and the compiler's own TSymbol/TParam/TProc are builtin records (6/7/8),
      and the statement-lvalue path does not call it at all.
      bug-pascal-unknown-record-field-accepted-in-compiler-source }
    Error('"' + field + '": no such member on this record/class');
  end
  else if rec >= REC_UCLASS_BASE then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := IntToTypeKind(UFldTk[fi]);
  end;
end;

function RecFieldStrCap(rec: Integer; const field: AnsiString): Integer;
{ Frozen fixed-string field capacity: N for a `string[N]` field, 0 for a plain
  `string` field / non-string field / builtin record. Drives the truncating
  store clamp on assignment into the field's inline buffer. }
var fi: Integer;
begin
  Result := 0;
  if rec >= REC_UCLASS_BASE then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field);
    if fi >= 0 then Result := UFldStrCap[fi];
  end;
end;

function RecFieldSubBounds(rec: Integer; const field: AnsiString;
  var lo, hi: Int64): Boolean;
{ True + the retained lo..hi when the field was declared via a named SUBRANGE
  type ({$R+} store checks — feature-pascal-range-checks-r-plus). }
var fi: Integer;
begin
  Result := False;
  if rec >= REC_UCLASS_BASE then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field);
    if (fi >= 0) and UFldIsSub[fi] then
    begin
      lo := UFldSubLo[fi];
      hi := UFldSubHi[fi];
      Result := True;
    end;
  end;
end;

function RecFieldRecId(rec: Integer; const field: AnsiString): Integer;
var fi, i, cnt: Integer; field2: AnsiString;
begin
  Result := REC_NONE; fi := 0; field2 := field;
  cnt := BuiltinRecFieldCount(rec);
  if cnt > 0 then
  begin
    for i := 0 to cnt - 1 do
      if BuiltinRecFieldMatches(rec, i, field) then
      begin
        Result := BuiltinRecFieldRecId(rec, i);
        Exit;
      end;
  end
  else if rec >= REC_UCLASS_BASE then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := UFldRec_[fi];
  end;
end;

{ Procedural-call signature Procs[] index of a (fn-pointer) record field, or -1.
  Used to lower `rec.field(args)` / `p->field(args)` to an indirect call. }
function RecFieldProcSig(rec: Integer; const field: AnsiString): Integer;
var fi: Integer; field2: AnsiString;
begin
  Result := -1; field2 := field;
  if rec >= REC_UCLASS_BASE then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := UFldProcSig[fi];
  end;
end;

{ Pointee call-signature of a POINTER-to-fn-ptr record field (`ft *pf`), or -1.
  Used to lower `(*s.pf)(args)` to an indirect call through the loaded fn-pointer. }
function RecFieldElemProcSig(rec: Integer; const field: AnsiString): Integer;
var fi: Integer; field2: AnsiString;
begin
  Result := -1; field2 := field;
  if rec >= REC_UCLASS_BASE then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := UFldElemProcSig[fi];
  end;
end;

function RecFieldBitWidth(rec: Integer; const field: AnsiString): Integer;
var fi: Integer; field2: AnsiString;
begin
  Result := 0; field2 := field;
  if rec >= REC_UCLASS_BASE then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := UFldBitWidth[fi];
  end;
end;

function RecFieldBitShift(rec: Integer; const field: AnsiString): Integer;
var fi: Integer; field2: AnsiString;
begin
  Result := 0; field2 := field;
  if rec >= REC_UCLASS_BASE then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := UFldBitShift[fi];
  end;
end;

function RecFieldBitBytes(rec: Integer; const field: AnsiString): Integer;
var fi: Integer; field2: AnsiString;
begin
  Result := 0; field2 := field;
  if rec >= REC_UCLASS_BASE then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := UFldBitBytes[fi];
  end;
end;

function ASTNodeIsWholeArray(node: Integer): Boolean;
{ True iff this lvalue node denotes a WHOLE array rather than one element.

  An array's TypeKind IS its element kind, so any pass that decides what an
  assignment means from the type kind alone cannot tell `arr := other` from
  `arr[i] := other` — and for an array of interfaces that mistake lowered the
  whole-array copy into an ARC interface assign over the array HANDLE.
  bug-a-assigning-a-dynamic-array-of-interfaces-is-lowered-as-an-interface-assign }
begin
  Result := False;
  if node < 0 then Exit;
  { An index or a deref has already selected an ELEMENT. }
  if ASTKind[node] <> AN_IDENT then Exit;
  Result := (ASTIVal[node] >= 0) and (ASTIVal[node] < SymCount) and
            Syms[ASTIVal[node]].IsArray;
end;

function RecFieldIsArray(rec: Integer; const field: AnsiString): Boolean;
var fi, i, cnt: Integer; field2: AnsiString;
begin
  Result := False;
  cnt := BuiltinRecFieldCount(rec);
  if cnt > 0 then
  begin
    for i := 0 to cnt - 1 do
      if BuiltinRecFieldMatches(rec, i, field) then
      begin
        Result := BuiltinRecFieldArrayCount(rec, i) > 0;
        Exit;
      end;
  end
  else if rec >= REC_UCLASS_BASE then
  begin
    field2 := field;
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := UFldIsArray[fi];
  end;
end;

function RecFieldArrLen(rec: Integer; const field: AnsiString): Integer;
{ Element count of a static-array field (>=0); -1 for a dynamic-array field or a
  non-array. Only user-class fields carry a recorded length; builtin records
  return -1 (none are static-array open-array sources). }
var fi: Integer; field2: AnsiString;
begin
  Result := -1; field2 := field;
  if (rec >= REC_UCLASS_BASE) and (BuiltinRecFieldCount(rec) = 0) then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := UFldArrLen[fi];
  end;
end;

function RecFieldArrLo(rec: Integer; const field: AnsiString): Integer;
{ LOW BOUND of a 1-D static array FIELD (`c: array[1..3] of Byte`), 0 when the
  field is not one or the bound was never recorded.

  A field array's low bound had nowhere to live: only 2-D-and-up fields filled
  UFldArrDimLo, so `r.c[i]` indexed from the RAW index and never subtracted the
  low. `array[1..3]` wrote one element PAST its extent (clobbering the next
  field), `array[5..7]` wrote five past (off the end of the record, a SIGSEGV),
  and `array[-2..2]` wrote two BEFORE it -- on a class, into the object header,
  so Free crashed. Reads were shifted identically, which is exactly why it
  survived: the field is self-consistent and only its NEIGHBOURS are wrong.

  The bound now lives in dim 0 of the same N-D table for 1-D fields too, while
  UFldArrNDims stays 0/1 so nothing that dispatches on the N-D shape changes.
  bug-p-record-field-array-with-a-non-zero-low-bound-writes-out-of-bounds }
var fi: Integer; field2: AnsiString;
begin
  Result := 0; field2 := field;
  if (rec >= REC_UCLASS_BASE) and (BuiltinRecFieldCount(rec) = 0) then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if (fi >= 0) and UFldIsArray[fi] and (UFldDynDepth[fi] = 0) and
       (UFldArrNDims[fi] <= 1) then
      Result := UFldArrDimLo[fi * MAX_ARR_DIMS];
  end;
end;

function RecFieldArrNDims(rec: Integer; const field: AnsiString): Integer;
{ Dimension count of an array field (1 for a 1-D array); 0 when unknown/non-array. }
var fi: Integer; field2: AnsiString;
begin
  Result := 0; field2 := field;
  if (rec >= REC_UCLASS_BASE) and (BuiltinRecFieldCount(rec) = 0) then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := UFldArrNDims[fi];
  end;
end;

function RecFieldArrDimSpanAt(rec: Integer; const field: AnsiString; d: Integer): Integer;
{ Span (element count) of dimension `d` of a multidim array field; 1 if unknown. }
var fi: Integer; field2: AnsiString;
begin
  Result := 1; field2 := field;
  if (rec >= REC_UCLASS_BASE) and (BuiltinRecFieldCount(rec) = 0) then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if (fi >= 0) and (d >= 0) and (d < UFldArrNDims[fi]) then
      Result := UFldArrDimSpan[fi * MAX_ARR_DIMS + d];
  end;
end;

function RecFieldRowStride(rec: Integer; const field: AnsiString): Integer;
{ Byte stride of one OUTER-dimension row of a multidimensional array field
  (product of the inner dim spans * element size); 0 if the field is not a
  recorded multidim array. Used by the C frontend's partial-index row decay:
  `field[i]` (single subscript of an `[N][M]..` field) yields the row address
  `&field + i*RowStride`. }
var fi, d, inner: Integer; field2: AnsiString; etk: TTypeKind;
begin
  Result := 0; field2 := field;
  if (rec >= REC_UCLASS_BASE) and (BuiltinRecFieldCount(rec) = 0) then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if (fi >= 0) and (UFldArrNDims[fi] >= 2) then
    begin
      inner := 1;
      for d := 1 to UFldArrNDims[fi] - 1 do
        inner := inner * UFldArrDimSpan[fi * MAX_ARR_DIMS + d];
      etk := IntToTypeKind(UFldTk[fi]);
      if etk = tyRecord then
        Result := inner * RecSize(UFldRec_[fi])
      else
        Result := inner * TypeSize(etk);
    end;
  end;
end;

procedure BuiltinLayoutAssert(ok: Boolean; const msg: AnsiString);
begin
  if not ok then
  begin
    writeln('BuiltinLayoutAssert failed: ', msg);
    writeln('REC_TTOKEN size = ', RecSize(REC_TTOKEN));
    writeln('REC_TTOKEN Kind offset = ', RecFieldOffset(REC_TTOKEN, 'Kind'));
    writeln('REC_TTOKEN SVal offset = ', RecFieldOffset(REC_TTOKEN, 'SVal'));
    writeln('REC_TTOKEN IVal offset = ', RecFieldOffset(REC_TTOKEN, 'IVal'));
    writeln('REC_TTOKEN Line offset = ', RecFieldOffset(REC_TTOKEN, 'Line'));
    Error('built-in record layout validation failed: ' + msg);
  end;
end;

procedure CheckBuiltinRecSize(rec, expected: Integer; const name: AnsiString);
begin
  BuiltinLayoutAssert(RecSize(rec) = expected, name);
end;

procedure CheckBuiltinRecField(rec: Integer; const field: AnsiString; off: Integer;
  tk: TTypeKind; recId: Integer; isArray: Boolean);
var
  actOff, actRecId: Integer;
  actTk: TTypeKind;
  actIsArray: Boolean;
begin
  actOff := RecFieldOffset(rec, field);
  actTk := RecFieldType(rec, field);
  actRecId := RecFieldRecId(rec, field);
  actIsArray := RecFieldIsArray(rec, field);
  
  if actOff <> off then
    writeln('Field ', field, ' offset mismatch: expected ', off, ', got ', actOff);
  if actTk <> tk then
    writeln('Field ', field, ' type mismatch: expected ', Ord(tk), ', got ', Ord(actTk));
  if actRecId <> recId then
    writeln('Field ', field, ' recId mismatch: expected ', recId, ', got ', actRecId);
  if actIsArray <> isArray then
    writeln('Field ', field, ' isArray mismatch: expected ', isArray, ', got ', actIsArray);

  BuiltinLayoutAssert(actOff = off, field);
  BuiltinLayoutAssert(actTk = tk, field);
  BuiltinLayoutAssert(actRecId = recId, field);
  BuiltinLayoutAssert(actIsArray = isArray, field);
end;

procedure ValidateBuiltinRecordLayout;
begin
  if PasDefineExists('PXX_MANAGED_STRING') then Exit;

  CheckBuiltinRecSize(REC_TTOKEN, 288, 'TToken');
  CheckBuiltinRecField(REC_TTOKEN, 'Kind', 0, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TTOKEN, 'SVal', 8, tyString, REC_NONE, False);
  CheckBuiltinRecField(REC_TTOKEN, 'IVal', 272, tyInt64, REC_NONE, False);
  CheckBuiltinRecField(REC_TTOKEN, 'Line', 280, tyInteger, REC_NONE, False);

  CheckBuiltinRecSize(REC_TSTRENTRY, 280, 'TStrEntry');
  CheckBuiltinRecField(REC_TSTRENTRY, 'Text', 0, tyString, REC_NONE, False);
  CheckBuiltinRecField(REC_TSTRENTRY, 'Offset', 264, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TSTRENTRY, 'Len', 272, tyInteger, REC_NONE, False);

  CheckBuiltinRecSize(REC_TFIXUP, 16, 'TFixup');
  CheckBuiltinRecField(REC_TFIXUP, 'CodePos', 0, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TFIXUP, 'DataOff', 8, tyInteger, REC_NONE, False);

  CheckBuiltinRecSize(REC_TGLOBFIX, 16, 'TGlobFix');
  CheckBuiltinRecField(REC_TGLOBFIX, 'CodePos', 0, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TGLOBFIX, 'BSSoff', 8, tyInteger, REC_NONE, False);

  CheckBuiltinRecSize(REC_TCALLFIX, 16, 'TCallFix');
  CheckBuiltinRecField(REC_TCALLFIX, 'CodePos', 0, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TCALLFIX, 'ProcIdx', 8, tyInteger, REC_NONE, False);

  CheckBuiltinRecSize(REC_TSYMBOL, 360, 'TSymbol');
  CheckBuiltinRecField(REC_TSYMBOL, 'Name', 0, tyString, REC_NONE, False);
  CheckBuiltinRecField(REC_TSYMBOL, 'TypeKind', 264, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TSYMBOL, 'Kind', 272, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TSYMBOL, 'Offset', 280, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TSYMBOL, 'ConstVal', 288, tyInt64, REC_NONE, False);
  CheckBuiltinRecField(REC_TSYMBOL, 'IsArray', 296, tyBoolean, REC_NONE, False);
  CheckBuiltinRecField(REC_TSYMBOL, 'ArrLen', 304, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TSYMBOL, 'ElemType', 312, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TSYMBOL, 'RecName', 320, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TSYMBOL, 'ElemRecName', 328, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TSYMBOL, 'IsRef', 336, tyBoolean, REC_NONE, False);
  CheckBuiltinRecField(REC_TSYMBOL, 'PtrElemTk', 344, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TSYMBOL, 'PtrElemRec', 352, tyInteger, REC_NONE, False);

  CheckBuiltinRecSize(REC_TPARAM, 296, 'TParam');
  CheckBuiltinRecField(REC_TPARAM, 'Name', 0, tyString, REC_NONE, False);
  CheckBuiltinRecField(REC_TPARAM, 'TypeKind', 264, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TPARAM, 'SymIdx', 272, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TPARAM, 'IsRef', 280, tyBoolean, REC_NONE, False);
  CheckBuiltinRecField(REC_TPARAM, 'IsArray', 288, tyBoolean, REC_NONE, False);

  { TProc trailing-field offsets scale with the Params bound (frozen TParam =
    296 bytes/element), so express them via MAX_PROC_PARAMS. }
  CheckBuiltinRecSize(REC_TPROC, 288 + MAX_PROC_PARAMS * 296 + 32, 'TProc');
  CheckBuiltinRecField(REC_TPROC, 'Name', 0, tyString, REC_NONE, False);
  CheckBuiltinRecField(REC_TPROC, 'IsFunc', 264, tyBoolean, REC_NONE, False);
  CheckBuiltinRecField(REC_TPROC, 'RetType', 272, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TPROC, 'ParamCount', 280, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TPROC, 'Params', 288, tyRecord, REC_TPARAM, True);
  CheckBuiltinRecField(REC_TPROC, 'BodyAddr', 288 + MAX_PROC_PARAMS * 296, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TPROC, 'FramePatch', 288 + MAX_PROC_PARAMS * 296 + 8, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TPROC, 'RetSymIdx', 288 + MAX_PROC_PARAMS * 296 + 16, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TPROC, 'ScopeBase', 288 + MAX_PROC_PARAMS * 296 + 24, tyInteger, REC_NONE, False);

  CheckBuiltinRecSize(REC_TRAWTOKEN, 40, 'TRawToken');
  CheckBuiltinRecField(REC_TRAWTOKEN, 'Kind', 0, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TRAWTOKEN, 'IVal', 8, tyInt64, REC_NONE, False);
  CheckBuiltinRecField(REC_TRAWTOKEN, 'Line', 16, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TRAWTOKEN, 'SOffset', 24, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TRAWTOKEN, 'SLen', 32, tyInteger, REC_NONE, False);

  CheckBuiltinRecSize(REC_TMYCLASS, 16, 'TMyClass');
  CheckBuiltinRecField(REC_TMYCLASS, 'x', 0, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TMYCLASS, 'y', 8, tyInteger, REC_NONE, False);

  CheckBuiltinRecSize(REC_TTEMPLATE, 544, 'TTemplate');
  CheckBuiltinRecField(REC_TTEMPLATE, 'Name', 0, tyString, REC_NONE, False);
  CheckBuiltinRecField(REC_TTEMPLATE, 'Param', 264, tyString, REC_NONE, False);
  CheckBuiltinRecField(REC_TTEMPLATE, 'TokStart', 528, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TTEMPLATE, 'TokCount', 536, tyInteger, REC_NONE, False);

  CheckBuiltinRecSize(REC_TSPECIALIZATION, 800, 'TSpecialization');
  CheckBuiltinRecField(REC_TSPECIALIZATION, 'Name', 0, tyString, REC_NONE, False);
  CheckBuiltinRecField(REC_TSPECIALIZATION, 'TemplateName', 264, tyString, REC_NONE, False);
  CheckBuiltinRecField(REC_TSPECIALIZATION, 'ConcreteType', 528, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TSPECIALIZATION, 'ConcreteName', 536, tyString, REC_NONE, False);

  CheckBuiltinRecSize(REC_TGENERICFUNC, 552, 'TGenericFunc');
  CheckBuiltinRecField(REC_TGENERICFUNC, 'Name', 0, tyString, REC_NONE, False);
  CheckBuiltinRecField(REC_TGENERICFUNC, 'Param', 264, tyString, REC_NONE, False);
  CheckBuiltinRecField(REC_TGENERICFUNC, 'IsFunc', 528, tyBoolean, REC_NONE, False);
  CheckBuiltinRecField(REC_TGENERICFUNC, 'TokStart', 536, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TGENERICFUNC, 'TokCount', 544, tyInteger, REC_NONE, False);

  CheckBuiltinRecSize(REC_TPENDINGGFSPEC, 544, 'TPendingGFSpec');
  CheckBuiltinRecField(REC_TPENDINGGFSPEC, 'GenFuncIdx', 0, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TPENDINGGFSPEC, 'ConcreteKind', 8, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TPENDINGGFSPEC, 'ConcreteName', 16, tyString, REC_NONE, False);
  CheckBuiltinRecField(REC_TPENDINGGFSPEC, 'SpecName', 280, tyString, REC_NONE, False);

  CheckBuiltinRecSize(REC_TMETHODFIXUP, 8, 'TMethodFixup');
  CheckBuiltinRecField(REC_TMETHODFIXUP, 'DataPos', 0, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TMETHODFIXUP, 'ProcIdx', 4, tyInteger, REC_NONE, False);
end;

function RecFieldDynDepth(rec: Integer; const field: AnsiString): Integer;
{ Dynamic-array nesting of a class/record field: 0 if the field is not a
  dynamic array, else 1 for `array of T`, 2 for `array of array of T`, ... }
var fi: Integer; field2: AnsiString;
begin
  Result := 0;
  if rec >= REC_UCLASS_BASE then
  begin
    field2 := field;
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := UFldDynDepth[fi];
  end;
end;

function RecFieldPtrElemTk(rec: Integer; const field: AnsiString): TTypeKind;
{ Pointed-at element type of a pointer-typed class field (for FField[i]). }
var fi: Integer; field2: AnsiString;
begin
  Result := tyUnknown; field2 := field;
  if rec >= REC_UCLASS_BASE then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := IntToTypeKind(UFldPtrElemTk[fi]);
  end;
end;

function RecFieldPtrElemRec(rec: Integer; const field: AnsiString): Integer;
{ Record id pointed at by a pointer-typed class field, else REC_NONE. }
var fi: Integer; field2: AnsiString;
begin
  Result := REC_NONE; field2 := field;
  if rec >= REC_UCLASS_BASE then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := UFldPtrElemRec[fi];
  end;
end;

function RecFieldByteSize(rec: Integer; const field: AnsiString): Integer;
{ The byte size of ONE field, ARRAYS INCLUDED — what `SizeOf(r.F)` must answer.

  RecFieldType reports an array field's ELEMENT kind (UFldTk holds the element
  type), so anything that sized a field as TypeSize(RecFieldType(...)) answered 4
  for an `array[0..2] of Integer` and nothing said so: SizeOf(r.A) was 4 where FPC
  3.2.2 says 12, and the idiomatic `Move(src.A, dst.A, SizeOf(src.A))` /
  `FillChar(r.A, SizeOf(r.A), 0)` touched one element of three while every
  surrounding line read as correct
  (bug-p-sizeof-an-array-field-returns-the-element-size).

  A dynamic-array field is a handle, so pointer width — the same rule SizeOf
  already applies to a named dynamic-array alias. A field whose array extent is
  not recorded keeps the element size rather than inventing one: today's answer
  beats a confidently wrong new one. }
var d, n, cnt, i, acc, erec: Integer; field2: AnsiString; etk: TTypeKind;
begin
  field2 := field;
  etk := RecFieldType(rec, field2);
  erec := RecFieldRecId(rec, field2);
  if (etk = tyRecord) and (erec >= 0) then
    Result := RecSize(erec)
  else
    Result := TypeSize(etk);
  if not RecFieldIsArray(rec, field2) then Exit;
  { a dynamic-array field is a reference }
  if RecFieldDynDepth(rec, field2) > 0 then begin Result := TARGET_PTR_SIZE; Exit; end;
  { builtin descriptor records carry a plain element count and no dim table }
  cnt := BuiltinRecFieldCount(rec);
  if cnt > 0 then
  begin
    for i := 0 to cnt - 1 do
      if BuiltinRecFieldMatches(rec, i, field2) then
      begin
        if BuiltinRecFieldArrayCount(rec, i) > 0 then
          Result := Result * BuiltinRecFieldArrayCount(rec, i);
        Exit;
      end;
    Exit;
  end;
  n := RecFieldArrNDims(rec, field2);
  if n >= 2 then
  begin
    acc := Result;
    for d := 0 to n - 1 do
      acc := acc * RecFieldArrDimSpanAt(rec, field2, d);
    Result := acc;
  end
  else if RecFieldArrLen(rec, field2) > 0 then
    Result := Result * RecFieldArrLen(rec, field2);
end;

function RecordHasManagedFieldsDepth2(recId, depth: Integer; inclIntf: Boolean): Boolean;
{ Class/object references are deliberately unmanaged. Only recurse through
  fixed-size user records and compiler-managed value fields. The depth cap is a
  robustness backstop: a malformed record that (transitively) contains ITSELF
  by value — which a valid C program can't produce, but a struct-tag
  redefinition bug once did — would otherwise recurse without bound and crash
  the compiler. Past the cap, treat as unmanaged rather than fault. }
var ci, base, cnt, i: Integer;
begin
  Result := False;
  if depth > 64 then Exit;
  if recId < REC_UCLASS_BASE then Exit;
  ci := recId - REC_UCLASS_BASE;
  if not UClsIsRecord[ci] then Exit;
  base := UClsFBase[ci];
  cnt := UClsFCount[ci];
  for i := 0 to cnt - 1 do
  begin
    if UFldTk[base + i] = Ord(tyAnsiString) then
      begin Result := True; Exit; end;
    { A dynamic-array field holds a heap handle that must be zero-initialised,
      retained on record copy, and released on finalization. }
    if UFldIsArray[base + i] and (UFldArrLen[base + i] = -1) then
      begin Result := True; Exit; end;
    { A COM/ARC interface field is NOT "managed" for FINALIZATION purposes. It is
      a refcounted handle, but finalizing it under the record heap lock
      deadlocks: record-scope finalization holds the non-reentrant heap spinlock
      and the interface's _Release -> Free -> FreeMem re-acquires it. Correct
      field-level finalization needs the member released OUTSIDE the lock (a
      reentrant heap lock, or a separate unlocked interface pass) — see
      bug-a-class-managed-fields-not-finalized-on-destroy. Until then such a
      field leaks, which is the deliberate benign-over-deadlock trade.

      ZERO-INIT IS A DIFFERENT QUESTION, and answering both with this one
      predicate is what turned that benign leak into a use-after-free. Nilling a
      stack slot at routine entry takes no lock, calls no _Release and cannot
      deadlock — and WITHOUT it `r.f := x` releases whatever stack garbage the
      slot held and dispatches _Release through a junk IMT. So `inclIntf` counts
      an interface field, and only the zero-init caller passes True:
      RecordNeedsZeroInit. Finalization behaviour is unchanged.
      bug-a-a-record-with-an-interface-field-is-not-zero-initialised }
    if inclIntf and RecIsComInterface(UFldRec_[base + i]) then
      begin Result := True; Exit; end;
    if (UFldTk[base + i] = Ord(tyRecord)) and (UFldRec_[base + i] <> recId) and
       RecordHasManagedFieldsDepth2(UFldRec_[base + i], depth + 1, inclIntf) then
      begin Result := True; Exit; end;
  end;
end;

function RecordHasManagedFields(recId: Integer): Boolean;
{ FINALIZATION question: does this record hold fields the scope-exit / destructor
  walk must release? A COM interface field deliberately does NOT count — see the
  note above. }
begin
  Result := RecordHasManagedFieldsDepth2(recId, 0, False);
end;

function ManagedElemKind(elemTk, elemRec: Integer): Integer;
{ THE answer to "what must a container's element walk do for this element type",
  and the only place that answer is written down. It is the `baseKind` the
  runtime array descriptor carries and the four element walks in builtinheap
  (PXXArrayReleaseImmediate, PXXDynArrayRetainImmediate, PXXDynArrayReleaseDepth,
  and PXXDynSetLen through them) switch on:

    0 = nothing managed
    1 = AnsiString element      (PXXStrIncRef / PXXStrDecRef)
    3 = record with managed fields, walked via its layout descriptor
    4 = COM interface element   (PXXIntfAddRef / PXXIntfRelease)

  It exists because that policy was spelled out NINE times — ir.inc's two
  whole-static-array copy branches, ir_codegen.inc's two descriptor allocators,
  rtti_emit.inc's descriptor writer, and this file's four per-target scope-exit
  arms — and every one of them was missing kind 4. That is not four bugs, it is
  one absent case reachable through nine doors, which is exactly the shape
  devdocs/dev/normalise-dont-special-case.md describes: an array of interfaces
  released nothing at scope exit, nothing on SetLength shrink, and nothing on
  whole-array assignment, for the same reason each time. A tenth kind (variant
  elements are the obvious next one) goes HERE, once.

  Note the ORDER: a COM interface is modelled as a tyRecord whose rec id is an
  interface UCls, so the interface test must precede the managed-record test.
  It would answer False anyway (an interface UCls has no managed FIELDS) — which
  is precisely how these elements fell through every walk — but relying on that
  is how the next kind gets mis-ordered. }
begin
  if elemTk = Ord(tyAnsiString) then
    ManagedElemKind := 1
  else if elemTk <> Ord(tyRecord) then
    ManagedElemKind := 0
  else if RecIsComInterface(elemRec) then
    ManagedElemKind := 4
  else if RecordHasManagedFields(elemRec) then
    ManagedElemKind := 3
  else
    ManagedElemKind := 0;
end;

function ManagedElemRef(elemTk, elemRec: Integer): Integer;
{ The second half of the (baseKind, ref) pair every element walk takes. Kind 3
  passes a descriptor ADDRESS (each emit site builds it from elemRec itself);
  kind 4 passes the INTERFACE ID as a plain integer, which is what this returns.
  0 for every other kind, where the argument is unused. }
begin
  if ManagedElemKind(elemTk, elemRec) = 4 then
    ManagedElemRef := elemRec - REC_UCLASS_BASE
  else
    ManagedElemRef := 0;
end;

function ManagedElemKindLocked(elemTk, elemRec: Integer): Integer;
{ ManagedElemKind for an element walk that runs while the CODEGEN HEAP LOCK is
  held — every dynamic-array path on x86-64 (EmitDynArrayReleaseForSym wraps the
  call, and both SetLength lowerings hold the lock from the allocation through
  the release of the old block).

  Kind 4 is refused there, and the refusal is not conservatism: releasing an
  interface element runs _Release -> Destroy -> FreeMem, and the FreeMem
  intrinsic re-acquires this same NON-REENTRANT spinlock, so the program would
  hang rather than leak. That is the identical hazard
  bug-a-class-managed-fields-not-finalized-on-destroy documented and solved for
  class fields by running the kind-4 pass first and UNLOCKED, and the identical
  reason it left the record-field case as a benign leak.

  So under --threadsafe / {$threadsafe on} a dynamic array of interfaces keeps
  the pre-existing leak instead of deadlocking, and every other build — which is
  every build that does not opt into hard locking — releases correctly. STATIC
  arrays are NOT gated: their scope-exit walk is emitted outside any lock (the
  same unlocked shape SymIsComInterface's scalar arm has shipped with for a
  long time), so nothing there can deadlock.

  Lifting this is decide-interface-members-in-aggregates-lock-strategy (Track U):
  it needs a reentrant heap lock or a split unlocked interface pass, and that is
  one decision covering records, classes and containers together. }
begin
  ManagedElemKindLocked := ManagedElemKind(elemTk, elemRec);
  if (ManagedElemKindLocked = 4) and ThreadSafeMode then
    ManagedElemKindLocked := 0;
end;

function RecordNeedsZeroInit(recId: Integer): Boolean;
{ ZERO-INIT question: does this record hold any slot that must start nil so the
  FIRST assignment's release sees an empty slot instead of stack garbage? Same
  walk, plus COM interface fields, which are excluded from finalization but must
  still be nilled. }
begin
  Result := RecordHasManagedFieldsDepth2(recId, 0, True);
end;

{ ===== Central type-query helpers ===== }
{ These are the single authoritative source for size, alignment, and signedness.
  All new code must call these instead of hard-coding numbers. }

function TypeSize(tk: TTypeKind): Integer;
{ Returns byte count needed to store one value of type tk.
  For pointer-sized types, returns TARGET_PTR_SIZE (8 on x86-64). }
begin
  Result := 8; { default / legacy path — pointer-width slot }
  case Ord(tk) of
    { Bootstrap-stable kinds (0-6) }
    0: Result := 8;  { tyUnknown }
    1: Result := 4;  { tyInteger  — signed 32-bit }
    2: Result := 1;  { tyBoolean  — unsigned 8-bit }
    3: Result := 1;  { tyChar }
    4: Result := 8;  { tyString   — struct pointer / inline; caller manages actual buffer }
    5: Result := 8;  { tyRecord   — caller must use RecSize() for full record size }
    6: Result := TARGET_PTR_SIZE;  { tyClass }
    { New precise kinds (7-17) }
    7:  Result := 1;  { tyInt8 }
    8:  Result := 1;  { tyUInt8 }
    9:  Result := 2;  { tyInt16 }
    10: Result := 2;  { tyUInt16 }
    11: Result := 4;  { tyInt32 }
    12: Result := 4;  { tyUInt32 }
    13: Result := 8;  { tyInt64 }
    14: Result := 8;  { tyUInt64 }
    15: Result := TARGET_PTR_SIZE;  { tyNativeInt }
    16: Result := TARGET_PTR_SIZE;  { tyNativeUInt }
    17: Result := TARGET_PTR_SIZE;  { tyPointer }
    18: Result := 4;  { tySingle }
    19: Result := 8;  { tyDouble }
    20: Result := 10; { tyExtended }
    21: Result := 32; { tySet }
    22: Result := 16; { tyVariant — 8-byte tag + 8-byte payload }
    23: Result := TARGET_PTR_SIZE; { tyAnsiString }
    24: Result := 0;  { tyAuto }
    { Promotable int family — {tag, payload}, tag width matches the payload so
      the struct stays naturally aligned (feature-a-promotable-int). }
    29: Result := 1;  { tyBool8 — C99 _Bool, one unsigned byte (same storage as tyUInt8) }
    30: Result := 4;  { tyUCS4Char — a Unicode code point (same storage as tyUInt32) }
    27: Result := 8;  { tyPromoInt32 — two 32-bit NATIVE words: tag + inline payload }
    28: Result := 16; { tyPromoInt64 — two 64-bit NATIVE words: tag + inline payload }
  end;
end;

{ The PROMOTABLE INT family (feature-a-promotable-int). Deliberately NOT
  reported by TypeIsOrdinal or TypeSigned: a promotable int is a {tag, payload}
  struct, not a machine word, so letting the existing integer codegen recognise
  it would silently operate on the tag. Anything that must handle it asks for it
  by name — an unhandled site errors instead of miscompiling. }
function TypeIsPromoInt(tk: TTypeKind): Boolean;
begin
  TypeIsPromoInt := (tk = tyPromoInt32) or (tk = tyPromoInt64);
end;

{ NilPy's `int` is arbitrary precision, so an ARITHMETIC result over machine
  ints has to be promotable even when both operands are native — otherwise a
  value that starts small and grows wraps at 2^63 with no diagnostic, which is
  the wrong way round: the literal that overflows is the case a programmer
  notices, and the accumulator is the case they do not
  (bug-nilpy-int-promotion-decided-statically-so-computed-overflow-wraps,
  decided as decide-nilpy-int-promotion-default option 1).

  Only the operators that can GROW a value are listed. `//`, `%`, `&`, `|`,
  `^` and the comparisons cannot leave the range of their operands, so they
  keep native codegen and cost nothing; `<<` already forces promo at its own
  site in pyparser.inc for the same reason this exists. Division is absent
  because Python's `/` is float.

  This is asked for by NAME at the two binop typing sites rather than folded
  into TypeArithmeticResult, because that routine is shared with Pascal and C,
  where `Integer + Integer` must stay an Integer. }
function PyIntGrowsOp(op: TTokenKind): Boolean;
begin
  PyIntGrowsOp := (op = tkPlus) or (op = tkMinus) or (op = tkStar);
end;

{ A native machine integer, i.e. the operand shape PyIntGrowsOp promotes.
  Boolean is included because a Python bool IS an int and `True + 1` is 2. }
function PyIsMachineIntTk(tk: TTypeKind): Boolean;
begin
  PyIsMachineIntTk := (tk = tyInteger) or (tk = tyInt64) or (tk = tyBoolean) or
                      (tk = tyInt8) or (tk = tyUInt8) or (tk = tyInt16) or
                      (tk = tyUInt16) or (tk = tyInt32) or (tk = tyUInt32) or
                      (tk = tyUInt64) or (tk = tyNativeInt) or (tk = tyNativeUInt);
end;

{ Usable inline width in bits, before the value spills to a heap bignum. The
  boundary is semantically unobservable — the type is arbitrary precision either
  way — so this only ever changes performance, never a result. }
function PromoIntInlineBits(tk: TTypeKind): Integer;
begin
  PromoIntInlineBits := 0;
  if tk = tyPromoInt32 then PromoIntInlineBits := 32
  else if tk = tyPromoInt64 then PromoIntInlineBits := 64;
end;

{ The machine integer type a promotable int's inline payload IS. This is the
  type every promo rvalue lowers to, so all downstream integer codegen applies
  unchanged. Native by construction — the storage class is chosen to match the
  target's word. }
function PromoNativeTk(tk: TTypeKind): TTypeKind;
begin
  PromoNativeTk := tyInt64;
  if tk = tyPromoInt32 then PromoNativeTk := tyInt32;
end;

{ The variant tag a promotable int of this storage class carries. }
function PromoIntVarTag(tk: TTypeKind): Integer;
begin
  PromoIntVarTag := -1;
  if tk = tyPromoInt32 then PromoIntVarTag := VT_PROMO_INT32
  else if tk = tyPromoInt64 then PromoIntVarTag := VT_PROMO_INT64;
end;

{ Per-target default storage class. The distinction is the target's NATIVE int
  size, not an arbitrary width pick: the slot is two native machine words (tag +
  inline payload), so the payload is whatever the core adds in one instruction.
  64-bit hosts get promoInt64; the 32-bit embedded cores get promoInt32, where
  int64 is multi-instruction emulation and 16 bytes per int is expensive in
  scarce SRAM (NilPy on ESP is a project subgoal, so this is not hypothetical).
  A per-value override may still pick the wider class where range analysis
  justifies it — the promotion boundary is semantically unobservable either way. }
function PromoIntDefaultKind: TTypeKind;
begin
  if TARGET_PTR_SIZE >= 8 then PromoIntDefaultKind := tyPromoInt64
  else PromoIntDefaultKind := tyPromoInt32;
end;


function SymNeedsZeroing(i: Integer; var zeroBytes: Integer): Boolean;
begin
  Result := False;
  zeroBytes := 0;
  if Syms[i].IsArray and (Syms[i].ArrLen = -1) then
  begin
    zeroBytes := TARGET_PTR_SIZE;
    Result := True;
  end
  else if Syms[i].IsArray and (Syms[i].ArrLen <> -1) and (SymElemDynDepth[i] > 0) then
  begin
    { Fixed array whose elements are dynamic-array handles (`array[..] of TA`):
      each slot must start nil so SetLength on an element does not release a
      garbage "old" handle. }
    zeroBytes := Syms[i].ArrLen * TARGET_PTR_SIZE;
    Result := True;
  end
  else if Syms[i].TypeKind = tyAnsiString then
  begin
    if Syms[i].IsArray then
      zeroBytes := Syms[i].ArrLen * TARGET_PTR_SIZE
    else
      zeroBytes := TARGET_PTR_SIZE;
    Result := True;
  end
  else if Syms[i].TypeKind = tyVariant then
  begin
    zeroBytes := TypeSize(tyVariant);
    Result := True;
  end
  else if TypeIsPromoInt(Syms[i].TypeKind) then
  begin
    { PROMO_TAG_INLINE is 0, so zeroing the slot leaves the variable holding
      inline 0 — the correct initial value, at no extra cost. Once the heap
      tier lands, this same zeroing is what keeps the tag from ever starting
      as a garbage HEAP marker pointing at a garbage bignum. }
    zeroBytes := TypeSize(Syms[i].TypeKind);
    Result := True;
  end
  else if SymIsComInterface(i) then
  begin
    { COM/ARC interface value: a fat pointer that the ARC path releases on
      overwrite and at scope exit, so it must start nil (all-zero) — otherwise the
      first release dispatches through a garbage IMT. }
    zeroBytes := RecSize(SymTR[i].RecId);
    Result := True;
  end
  else if (Syms[i].TypeKind = tyRecord) and not Syms[i].IsArray and
          RecordHasManagedFields(SymTR[i].RecId) then
  begin
    zeroBytes := RecSize(SymTR[i].RecId);
    Result := True;
  end
  else if (Syms[i].TypeKind = tyRecord) and Syms[i].IsArray and
          RecordHasManagedFields(SymTR[i].ElemRec) then
  begin
    zeroBytes := Syms[i].ArrLen * RecSize(SymTR[i].ElemRec);
    Result := True;
  end;
end;

function TypeAlign(tk: TTypeKind): Integer;
{ Returns alignment requirement (power of 2) for type tk.
  On x86-64 all scalar types are naturally aligned. }
var sz: Integer;
begin
  sz := TypeSize(tk);
  if sz <= 1 then Result := 1
  else if sz <= 2 then Result := 2
  else if sz <= 4 then Result := 4
  else Result := 8;
end;

function AlignTo(value, alignment: Integer): Integer;
begin
  if alignment <= 1 then
    Result := value
  else
    Result := ((value + alignment - 1) div alignment) * alignment;
end;

function TypeSigned(tk: TTypeKind): Boolean;
{ True for signed integer types. }
begin
  Result := False;
  case Ord(tk) of
    1:  Result := True;  { tyInteger  — legacy signed }
    7:  Result := True;  { tyInt8 }
    9:  Result := True;  { tyInt16 }
    11: Result := True;  { tyInt32 }
    13: Result := True;  { tyInt64 }
    15: Result := True;  { tyNativeInt }
  end;
end;

function TypeIsOrdinal(tk: TTypeKind): Boolean;
{ True for integer and character types — types that have a simple ordinal value. }
begin
  Result := False;
  case Ord(tk) of
    1, 2, 3,         { tyInteger, tyBoolean, tyChar — legacy }
    7, 8, 9, 10,     { tyInt8..tyUInt16 }
    11, 12, 13, 14,  { tyInt32..tyUInt64 }
    15, 16, 17,      { tyNativeInt, tyNativeUInt, tyPointer }
    29,              { tyBool8 — C99 _Bool; ordinal for every purpose except conversion }
    30:              { tyUCS4Char — a code point IS an ordinal (FPC: UCS4Char = type LongWord);
                       like tyBool8 it differs only in how it CONVERTS }
      Result := True;
  end;
end;

function TypeIsFloat(tk: TTypeKind): Boolean;
begin
  Result := (Ord(tk) = 18) or (Ord(tk) = 19) or (Ord(tk) = 20);  { tySingle or tyDouble or tyExtended }
end;

function IRVariantUnboxKind(target: TTypeKind): Boolean;
{ Which scalar targets a tyVariant value may be unboxed into. Anything not
  listed keeps the pre-existing lowering (records, sets, classes, pointers —
  none of which a variant payload can stand in for).

  Lives here, not in ir.inc where its only caller used to be, because the NilPy
  *args forwarder needs the same answer when it decides whether an argument may
  be left as a variant for IRLowerCallArg to unbox — and the pasparser_* slices are included
  before ir.inc. It answers a question about a TYPE KIND, so it has no business
  being IR-private in the first place. }
begin
  IRVariantUnboxKind :=
    TypeIsFloat(target) or (target = tyBoolean) or (target = tyChar) or
    (target = tyString) or (target = tyAnsiString) or
    (target = tyInteger) or (target = tyInt8) or (target = tyInt16) or
    (target = tyInt32) or (target = tyInt64) or (target = tyNativeInt) or
    (target = tyUInt8) or (target = tyUInt16) or (target = tyUInt32) or
    (target = tyUInt64) or (target = tyNativeUInt);
end;

function TypeIsPyNumeric(tk: TTypeKind): Boolean;
{ The integer and float kinds — a NUMBER in the Python sense, and nothing else.
  Used to decide whether NilPy's `/` is arithmetic. It must exclude tyClass:
  `Path("a") / "b"` is pathlib's join operator, and routing that through the
  arithmetic helper compiled a path handle as a Double and SEGFAULTED. tyChar,
  tyPointer, tyVariant and the string kinds are excluded for the same reason —
  each has its own `/` meaning or none at all. Booleans are numbers in Python
  (`True / 2` is 0.5), so they are in. }
begin
  Result := False;
  case Ord(tk) of
    1, 2,            { tyInteger, tyBoolean }
    7, 8, 9, 10,     { tyInt8..tyUInt16 }
    11, 12, 13, 14,  { tyInt32..tyUInt64 }
    15, 16,          { tyNativeInt, tyNativeUInt }
    18, 19, 20:      { tySingle, tyDouble, tyExtended }
      Result := True;
  end;
end;

function PyEqDisjointFromString(tk: TTypeKind): Boolean;
{ True for a type that can NEVER compare equal to a string in Python, for
  NilPy's `==`/`!=` string-vs-other fold in pasparser_expr.inc. Numbers, booleans,
  pointers, class handles and nil all qualify: a `str` is equal only to a
  `str`, so the answer is False (True for `!=`) without any comparison.

  Three kinds are deliberately EXCLUDED, and each exclusion is load-bearing:
    - the string kinds themselves — that is the real comparison;
    - tyChar, because a one-character literal can be typed tyChar, so
      `"a" == c` must stay a real comparison rather than fold to False;
    - tyVariant and tyUnknown, because the type is not known until run time
      and a static answer would be a guess. }
begin
  Result := False;
  case Ord(tk) of
    1, 2,            { tyInteger, tyBoolean }
    5, 6,            { tyRecord, tyClass }
    7, 8, 9, 10,     { tyInt8..tyUInt16 }
    11, 12, 13, 14,  { tyInt32..tyUInt64 }
    15, 16, 17,      { tyNativeInt, tyNativeUInt, tyPointer }
    18, 19, 20,      { tySingle, tyDouble, tyExtended }
    21:              { tySet }
      Result := True;
  end;
end;

function TypeIsAggregate(tk: TTypeKind): Boolean;
begin
  Result := (tk = tyRecord) or (tk = tySet);
end;

function TypeIsFrozenString(tk: TTypeKind): Boolean;
{ True for the inline (non-managed) frozen string kinds: the legacy overloaded
  tyString, the classic byte-prefixed tyShortString, and the word-prefixed sized
  tyFixedString. Widen existing `= tyString` codegen checks to this predicate so
  the new kinds route through the frozen-string path without 250 new arms. }
begin
  Result := (tk = tyString) or (tk = tyShortString) or (tk = tyFixedString);
end;

function StrValTk(tk: TTypeKind): Integer;
{ Value (expression) kind of a symbol whose STORAGE kind is given. A frozen
  fixed/short string presents as a plain frozen tyString *value* — they are
  codegen-identical (same inline word-prefixed layout); only the slot SIZE
  differs, and that is carried by the storage kind + SymStrCap. Normalising the
  node value-kind here keeps every existing `= tyString` value check (write,
  concat, compare, ...) working without widening ~150 sites. Returns an Ord. }
begin
  if (tk = tyFixedString) or (tk = tyShortString) then
    Result := Ord(tyString)
  else
    Result := Ord(tk);
end;

function FrozenStrSlotSize(tk: TTypeKind; cap: Integer): Integer;
{ Byte size of an inline frozen fixed-string slot.
  tyFixedString = 8-byte NativeInt length word + cap chars (matches today's
  frozen tyString layout, so it reuses the existing tyString codegen unchanged).
  tyShortString = 1 length byte + cap chars (classic FPC shortstring, cap<=255). }
begin
  if cap <= 0 then cap := DEFAULT_STR_CAP;
  if tk = tyShortString then
    Result := cap + 1
  else
    Result := cap + 8;
end;

{ The RETURN half of the ABI oracle lives in abi.inc with the parameter half —
  these two are the `ReturnVia` query the oracle is meant to own. Implemented
  there, forward-declared here because abi.inc is included after this file.
  feature-a-abi-oracle }
function RetViaHiddenDest(tk: TTypeKind): Boolean; forward;
function ABIRetViaHiddenDestProc(procIdx: Integer): Boolean; forward;
function AggRetCopySize(retSymIdx: Integer): Integer; forward;

function TypeCompareUnsigned(lhs, rhs: TTypeKind): Boolean;
{ The wider operand determines the comparison domain; at equal width a signed
  operand wins (Pascal: the pair widens to the next larger signed type). Values
  are still evaluated in 64-bit registers. }
begin
  Result := False;
  if not (TypeIsOrdinal(lhs) and TypeIsOrdinal(rhs)) then Exit;
  { C integer promotions: an operand narrower than int is promoted to (signed)
    int before the comparison, so a comparison of TWO sub-int operands is SIGNED
    regardless of their own signedness — `(int8)-57 >= (uint16)0` is a signed int
    compare (-57 >= 0 -> false), not unsigned (csmith seed 31039 miscompiled it
    unsigned via the wider-unsigned-operand rule below). A sub-int vs >=int-width
    operand still falls through (the narrow side promotes to int, then the usual
    conversions with the wider operand apply). Pascal keeps its own rule. }
  if CProgramMode and (TypeSize(lhs) < 4) and (TypeSize(rhs) < 4) then Exit;
  if not CProgramMode then
  begin
    { Pascal converts by RANGE, not by rank: the pair widens to a type that HOLDS
      BOTH, and Int64 holds every LongWord, Word and Byte -- so
      `LongWord(3000000000) > SmallInt(-1)` is TRUE even though the unsigned side
      is WIDER. Under the wider-operand rule below (C's) the signed operand
      sign-extended into a huge unsigned value and the answer was FALSE.

      The exception is the one width where no wider signed type EXISTS: an
      8-byte unsigned operand against a NARROWER signed one converts the signed
      side to QWord, so `QWord(9e18) > Integer(-1)` is FALSE. Against Int64 it
      is signed again (FPC 3.2.2 measured, both ways) -- and `div`/`mod` do NOT
      copy that carve-out: `q div i` IS signed in FPC where `q > i` is unsigned.
      That inconsistency is the oracle's, so TypeDivideUnsigned keeps its own
      plainer rule and the two must NOT be merged.

      A non-negative literal operand is normalised to unsigned before this
      (NormalizeUnsignedLiteralOperand), so `q > 10` still compares unsigned. }
    if TypeSigned(lhs) = TypeSigned(rhs) then
      Result := not TypeSigned(lhs)
    else if not TypeSigned(lhs) then
      Result := (TypeSize(lhs) = 8) and (TypeSize(rhs) < 8)
    else
      Result := (TypeSize(rhs) = 8) and (TypeSize(lhs) < 8);
    Exit;
  end;
  if TypeSize(lhs) > TypeSize(rhs) then
    Result := not TypeSigned(lhs)
  else if TypeSize(rhs) > TypeSize(lhs) then
    Result := not TypeSigned(rhs)
  else
  begin
    Result := (not TypeSigned(lhs)) and (not TypeSigned(rhs));
    { C usual arithmetic conversions: at EQUAL rank a signed operand is converted
      to unsigned, so the comparison is UNSIGNED if EITHER operand is unsigned
      (`int64 > 0UL` must be unsigned — csmith seed 8020 miscompiled it signed).
      Only 8-byte needs this here: there is no wider type to widen into and the
      full 64-bit values compare directly; the <8-byte C path is already correct
      via integer promotion, and Pascal keeps its widen-to-larger-signed rule. }
    if CProgramMode and (TypeSize(lhs) = 8) and
       ((not TypeSigned(lhs)) or (not TypeSigned(rhs))) then
      Result := True;
  end;
end;

{ ===== 32-bit call argument marshalling: the shared DECISION =====

  Every 32-bit backend (i386, arm32, riscv32) marshals by-value call arguments
  with a ladder of special cases, and each writes that ladder out once per call
  KIND: direct, indirect (proc-var), and virtual. Three backends x three kinds,
  nine copies that were never meant to differ — and they drifted. IR_VIRTUAL_CALL
  had no ladder AT ALL in any backend for years
  (bug-a-virtual-method-int64-in-and-out-32bit), and once that was fixed a matrix
  test found four more holes: i386's virtual path had no double and no single
  case, arm32's had no single, i386's indirect path had no set, and riscv32's
  indirect path had none of the three.

  What unifies is the DECISION — "how many words does parameter i of proc p
  occupy, and which marshalling shape does it need" — which is ABI logic and
  identical across call kinds by definition. The instruction emission stays
  per-arch. A backend that consults this cannot silently lack a case: it can only
  fail loudly on a class it does not handle.

  DELIBERATELY NOT HERE: the 5..8 byte by-value record. Only riscv32's direct
  path treats it as a pair; every other path on every backend passes such a
  record by ADDRESS, and test_call_arg_marshalling_32bit shows all of them agree
  with FPC today. Folding it in would change working behaviour on eight paths to
  match one. It stays out until someone decides which convention is right —
  filed rather than guessed. }
const
  A32_WORD   = 0;   { one word — ordinals, pointers, handles, any by-ref param }
  A32_PAIR64 = 1;   { two words — a 64-bit INTEGER by value; widen a 32-bit source }
  A32_DOUBLE = 2;   { two words — a Double by value; the value is in the arch float reg }
  A32_SINGLE = 3;   { one word — narrow the double-valued register to single first }
  A32_SET    = 4;   { eight words — copied inline from the set's address }

function Arg32Words(cls: Integer): Integer;
{ Words occupied by an argument of the given class on a 32-bit target. }
begin
  if cls = A32_SET then Arg32Words := TypeSize(tySet) div 4
  else if (cls = A32_PAIR64) or (cls = A32_DOUBLE) then Arg32Words := 2
  else Arg32Words := 1;
end;

function Arg32Class(procIdx, paramIdx: Integer; argTk: TTypeKind): Integer;
{ Classify one by-value call argument. `paramIdx` is the PARAMETER index (Self is
  0 for a method, so a virtual path's counter starts there too); `argTk` is the
  type of the value actually being passed, which matters both for the variadic
  tail and for widening a 32-bit source into a 64-bit parameter.

  A paramIdx at or past ParamCount is a VARIADIC TAIL argument: there is no
  declared parameter to consult, so it classifies by the argument's own type. An
  unknown signature (procIdx < 0) is treated the same way.

  A Single in the tail deliberately stays ONE word rather than promoting to
  double the way C varargs would. That is what every 32-bit path does today and
  this helper was extracted to be behaviour-preserving; whether the promotion is
  missing is a separate question from whether the ladders agree, and folding a
  behaviour change into a de-duplication is how a refactor gets blamed for a bug
  it did not cause. }
var ptk: TTypeKind;
begin
  Arg32Class := A32_WORD;
  if (procIdx < 0) or (paramIdx >= Procs[procIdx].ParamCount) then
  begin
    if (argTk = tyInt64) or (argTk = tyUInt64) then Arg32Class := A32_PAIR64
    else if argTk = tyDouble then Arg32Class := A32_DOUBLE;
    Exit;
  end;
  { A by-reference parameter is the ADDRESS: always one word, whatever it points
    at. The IsArray exception is load-bearing and predates this helper — an open
    array carries IsRef but its 64-bit ELEMENT type is still marshalled as a
    pair by the direct path, so the two flags are not interchangeable. }
  if Procs[procIdx].Params[paramIdx].IsRef and
     (not Procs[procIdx].Params[paramIdx].IsArray) then Exit;
  ptk := Procs[procIdx].Params[paramIdx].TypeKind;
  if (ptk = tySet) and (not Procs[procIdx].Params[paramIdx].IsArray) then
    Arg32Class := A32_SET
  else if (ptk = tyInt64) or (ptk = tyUInt64) then
    Arg32Class := A32_PAIR64
  else if ptk = tyDouble then
    Arg32Class := A32_DOUBLE
  else if ptk = tySingle then
    Arg32Class := A32_SINGLE;
end;

function TypeArithmeticResult(lhs, rhs: TTypeKind): TTypeKind;
{ Integer arithmetic is evaluated as an 8-byte value. Signedness follows the
  same widening rule as relational comparisons. }
begin
  { A promotable int is INFECTIOUS: mixing one with any ordinary integer yields a
    promotable int, never the machine type. Losing precision at the boundary is
    exactly the cliff this type exists to remove, so the wider storage class
    wins. Checked before the signedness rule because promo has no unsigned form. }
  if TypeIsPromoInt(lhs) or TypeIsPromoInt(rhs) then
  begin
    { Always the 64-bit class today. Keeping a promo32 op in its own 32-bit
      class would be the principled rule — the op then traps in the operands'
      own width — but the backend's {$Q+} overflow check only covers 64-bit
      ops (measured: `{$Q+} c: Integer; c := c + 2000000000` wraps silently,
      see bug-a-qplus-misses-32bit-overflow). Computing in 64-bit is what makes
      the trap real, so promo32 stays declaration-blocked until that check
      exists rather than shipping a class that silently truncates. }
    Result := tyPromoInt64;
    Exit;
  end;
  if TypeCompareUnsigned(lhs, rhs) then
    Result := tyUInt64
  else
    Result := tyInt64;
end;

function TypeArithmeticResultOp(lhs, rhs: TTypeKind; op: TTokenKind): TTypeKind;
{ Operator-aware integer promotion, matching FPC's range-based result type.
  Most operators keep the TypeCompareUnsigned widening (e.g. LongWord * LongWord
  can reach ~2^64, so it stays UInt64). SUBTRACTION of unsigned operands can go
  negative, and FPC yields a signed Int64 unless a true 64-bit unsigned operand
  (UInt64/QWord/NativeUInt) forces UInt64 — so `cardinal(3) - cardinal(5)` = -2,
  not 2^64-2, while `qword - qword` stays unsigned. }
begin
  if TypeIsPromoInt(lhs) or TypeIsPromoInt(rhs) then
  begin
    Result := TypeArithmeticResult(lhs, rhs);
    Exit;
  end;
  if (op = tkMinus) and (lhs <> tyUInt64) and (rhs <> tyUInt64) and
     (lhs <> tyNativeUInt) and (rhs <> tyNativeUInt) then
    Result := tyInt64
  else
    Result := TypeArithmeticResult(lhs, rhs);
end;

{ `div`/`mod` read BOTH operands, exactly like a comparison does: the pair
  widens to a type that holds both, so `Word div SmallInt` is a SIGNED division
  (FPC 3.2.2 answers -1 for `40000 div -25536`, not 0). Keying on the dividend
  alone made EVERY unsigned-over-signed division unsigned -- Word/SmallInt,
  Byte/ShortInt, LongWord/Integer and QWord/Int64 all diverged from FPC, while
  every signed dividend agreed. That is the same double case TypeCompareUnsigned
  already got right for comparisons, so this delegates to it rather than growing
  a second rule: the two must answer the same question the same way, C's usual
  arithmetic conversions (sub-int promotion, unsigned-wins at equal 8-byte rank)
  included. A non-ordinal divisor -- synthesized IR tagged tyUnknown -- keeps the
  old dividend-only rule, so internally generated divisions are untouched. }
function TypeDivideUnsigned(dividend, divisor: TTypeKind): Boolean;
begin
  Result := False;
  if not TypeIsOrdinal(dividend) then Exit;
  if not TypeIsOrdinal(divisor) then
  begin
    { synthesized IR carries no divisor type; keep the old dividend-only rule }
    Result := not TypeSigned(dividend);
    Exit;
  end;
  if CProgramMode then
  begin
    { C converts by RANK, not by range: at equal rank the unsigned operand wins
      (`u / -1` is unsigned), and a sub-int pair promotes to signed int. That is
      TypeCompareUnsigned's job already. }
    Result := TypeCompareUnsigned(dividend, divisor);
    Exit;
  end;
  { Pascal converts by RANGE: the pair widens to a type holding both, which is
    signed the moment either operand is -- `LongWord div SmallInt` is signed even
    though the unsigned side is WIDER, because Int64 holds both. A positive
    literal divisor is normalised to unsigned before this (see
    NormalizeUnsignedDivLiteral), so `q div 10` stays unsigned. }
  Result := (not TypeSigned(dividend)) and (not TypeSigned(divisor));
end;

{ The 32-bit backends' 64-bit PAIR path (i386/arm32/riscv32) picks ONE
  signedness for the whole operation, from "either operand is UInt64". That is
  the arithmetic/shift rule and it stays; `div`/`mod` must follow the two-operand
  divide rule instead, or `QWord div Int64` divides unsigned on those targets
  while x86-64 and aarch64 divide signed. Same question, one answer, every
  target. }
function TypeBinop64Unsigned(op: Integer; lhs, rhs: TTypeKind): Boolean;
begin
  if (op = Ord(tkDiv)) or (op = Ord(tkMod)) then
    Result := TypeDivideUnsigned(lhs, rhs)
  else
    Result := (lhs = tyUInt64) or (rhs = tyUInt64);
end;

function TypeDivideResult(dividend, divisor: TTypeKind): TTypeKind;
begin
  { `div`/`mod` on a promotable int stay promotable. This sits ahead of the
    signedness rule because the tkDiv/tkMod arms in the binop typing sites run
    BEFORE the promo arm — without it `a div 1000000` typed as Int64, the promo
    lowering never fired, and the generated code divided two slot ADDRESSES. }
  if TypeIsPromoInt(dividend) then
  begin
    Result := dividend;
    Exit;
  end;
  if TypeDivideUnsigned(dividend, divisor) then
    Result := tyUInt64
  else
    Result := tyInt64;
end;

{ `div`/`mod` typed from BOTH operands. TypeDivideResult reads the divisor for
  signedness but takes its WIDTH class from the dividend, which is wrong for the
  promotable class: `5 // (j +
  1)` has a machine-int dividend and an ARBITRARY-PRECISION divisor, so the node
  typed Int64, the promo divisor's slot ADDRESS was used as the number, and the
  answer was garbage (0 for `//`, the dividend itself for `%`). The divisor
  cannot widen the RESULT, but it does decide which lowering must run. }
function TypeDivideResultPair(dividend, divisor: TTypeKind): TTypeKind;
begin
  if TypeIsPromoInt(divisor) then
    TypeDivideResultPair := tyPromoInt64
  else
    TypeDivideResultPair := TypeDivideResult(dividend, divisor);
end;

function TypeIsPointerSized(tk: TTypeKind): Boolean;
{ True for types that occupy exactly TARGET_PTR_SIZE bytes: Pointer, NativeInt,
  NativeUInt, tyClass. These grow with the target pointer width. }
begin
  Result := False;
  case Ord(tk) of
    6,       { tyClass }
    15, 16,  { tyNativeInt, tyNativeUInt }
    17,      { tyPointer }
    23:      { tyAnsiString }
      Result := True;
  end;
end;

{ ===== Symbol table ===== }

function StrEqual(const s1, s2: AnsiString): Boolean;
var len, i: Integer;
begin
  Result := False;
  len := Length(s1);
  if len = Length(s2) then
  begin
    Result := True;
    for i := 1 to len do
    begin
      if s1[i] <> s2[i] then Result := False;
    end;
  end;
end;

function ParamNameEq(pi: Integer; const declared, given: AnsiString): Boolean;
{ Match a keyword-argument name against a declared parameter name under the
  CALLEE's case rule — the same per-declaration split DeclCaseSensitive applies
  to symbols. A NilPy `def f(Alpha=1, alpha=2)` has two distinct parameters and
  `f(Alpha=10, alpha=20)` must bind them separately; a Pascal RTL routine called
  from NilPy keeps FPC's case-insensitive names. }
begin
  if (pi >= 0) and (pi < ProcCount) and ProcCaseSensitive[pi] then
    ParamNameEq := StrEqual(declared, given)
  else
    ParamNameEq := CaseEqual(declared, given);
end;

function IsBlockVisible(symBlockId, curBlockId: Integer): Boolean;
var b: Integer;
begin
  if not EnableLazyVar then
  begin
    Result := True;
    Exit;
  end;
  b := curBlockId;
  while b <> -1 do
  begin
    if b = symBlockId then
    begin
      Result := True;
      Exit;
    end;
    if b = 0 then Break;
    b := BlockParent[b];
  end;
  Result := False;
end;

{ True if `nm` would resolve to a program/unit GLOBAL that FindSym is currently
  hiding ONLY because of decl-order gating (declared textually later than the
  routine being compiled). Lets undefined-name error sites give a clearer hint.
  Cost is irrelevant — only called on an error path that aborts the compile. }
{ True if `nm` would resolve to a main-program ROUTINE that the require-forward
  gate is hiding (header below the body being compiled). Error-path hint only. }
function HiddenByForwardOrder(const nm: AnsiString): Boolean;
var i: Integer;
begin
  Result := False;
  if not RequireForward then Exit;
  for i := 0 to ProcCount-1 do
    if (ProcHdrTok[i] > CurBodyHdrTok) and
       (StrEqual(Procs[i].Name, nm) or
        ((not ProcCaseSensitive[i]) and CaseEqual(Procs[i].Name, nm))) then
    begin
      Result := True;
      Exit;
    end;
end;

function HiddenByDeclOrder(const nm: AnsiString): Boolean;
var i: Integer;
begin
  Result := False;
  if not DeclOrderStrict then Exit;
  for i := SymCount-1 downto 0 do
    if (Syms[i].Kind = skGlobal) and (SymDeclTok[i] > CurBodyHdrTok) and
       IsBlockVisible(SymBlockId[i], CurBlockId) and
       (StrEqual(Syms[i].Name, nm) or
        ((not SymCaseSensitive[i]) and CaseEqual(Syms[i].Name, nm))) then
    begin
      Result := True;
      Exit;
    end;
end;

{ Same fold+FNV, masked to the (larger) symbol bucket count. }
function SymNameFoldHash(const s: AnsiString): Integer;
var i, b: Integer; h: LongWord;
begin
  h := LongWord($811C9DC5);
  for i := 1 to Length(s) do
  begin
    b := Ord(s[i]);
    if (b >= 65) and (b <= 90) then b := b + 32;
    h := (h xor LongWord(b)) * LongWord($01000193);
  end;
  Result := Integer(h and LongWord(SYM_HASH_SIZE - 1));
end;

procedure SymHashReset;
var i: Integer;
begin
  for i := 0 to SYM_HASH_SIZE - 1 do
    SymHashHead[i] := -1;
end;

{ Push a just-registered slot onto its bucket, newest-first. MUST be called at
  the moment the slot becomes visible (the Inc(SymCount) in the Alloc*
  functions), NOT when the name is first assigned — the linear scans were
  bounded by SymCount, so a lookup made while a registration is still filling
  in its fields must not see the in-flight slot. }
procedure SymHashInsert(idx: Integer);
var b: Integer;
begin
  b := SymNameFoldHash(Syms[idx].Name);
  SymHashPrev[idx] := SymHashHead[b];
  SymHashHead[b] := idx;
end;

{ Truncate the symbol table to newCount, unlinking the removed range from the
  hash. Descending order: the highest live idx is always its bucket's current
  head, so each pop is O(1). Replaces bare `SymCount := savedSC` at scope
  exits — a bare truncation would leave dead heads pointing at slots the next
  scope re-registers under different names. }
procedure SymRollbackTo(newCount: Integer);
{ Leaving a routine: unhash every symbol it declared, so none of them stays
  visible, and hand the indices back.

  EXCEPT a routine-local typed CONST (and its run-once init guard). Those have
  BSS storage, and their symbol INDEX outlives the routine's parse because the
  -O2 inliner copies the body into every caller -- the copy is verified when
  SymCount has already come back down, so a reused index reads as "invalid IR
  symbol reference in load_sym", one past the end. Unhash them like everything
  else (visibility is by hash chain, and they must not stay visible), but keep
  the high-water mark above them so nothing else is ever allocated there.
  Costs a few dead slots in a routine that has one.
  bug-p-a-routine-local-typed-const-is-reinitialised-on-every-call }
var i, keepTo: Integer;
begin
  keepTo := newCount;
  for i := SymCount - 1 downto newCount do
  begin
    SymHashHead[SymNameFoldHash(Syms[i].Name)] := SymHashPrev[i];
    if SymStaticLocal[i] and (i >= keepTo) then keepTo := i + 1;
  end;
  SymCount := keepTo;
end;

function FindSym(const name: AnsiString): Integer;
var i: Integer; lo: AnsiString;
begin
  lo := name;
  { Inside an FPC named-result operator body the declared result name is an
    alias of Result (feature-pascal-operator-decl-fpc-compat). }
  if (OpResultAlias <> '') and CaseEqual(lo, OpResultAlias) then lo := 'Result';
  { Exact-case match first, innermost scope out (preserves shadowing). A global
    variable declared textually after the current routine is hidden (decl-order
    gating, DeclOrderStrict) so it cannot bind — declare-before-use, FPC-parity.
    Hash chain is NEWEST-first, so walking it is the linear downto order. }
  i := SymHashHead[SymNameFoldHash(lo)];
  while i >= 0 do
  begin
    if StrEqual(Syms[i].Name, lo) and IsBlockVisible(SymBlockId[i], CurBlockId)
       and DeclVisible(SymUnitIdx[i])
       and not (DeclOrderStrict and (Syms[i].Kind = skGlobal) and (not SymStaticLocal[i])
                and (SymDeclTok[i] > CurBodyHdrTok)) then
    begin
      if DebugTrace then writeln('FindSym: ', lo, ' -> ', i);
      Result := i;
      Exit;
    end;
    i := SymHashPrev[i];
  end;
  { Case-insensitive fallback for case-insensitive symbols only (same folded
    bucket holds every case variant). }
  i := SymHashHead[SymNameFoldHash(lo)];
  while i >= 0 do
  begin
    if (not SymCaseSensitive[i]) and CaseEqual(Syms[i].Name, lo) and
       IsBlockVisible(SymBlockId[i], CurBlockId)
       and DeclVisible(SymUnitIdx[i])
       and not (DeclOrderStrict and (Syms[i].Kind = skGlobal) and (not SymStaticLocal[i])
                and (SymDeclTok[i] > CurBodyHdrTok)) then
    begin
      if DebugTrace then writeln('FindSym: ', lo, ' -> ', i, ' (ci)');
      Result := i;
      Exit;
    end;
    i := SymHashPrev[i];
  end;

  if DebugTrace then writeln('FindSym: ', lo, ' -> -1');
  if DebugTrace and StrEqual(lo, 'ELF_HEADER_SIZE') then
  begin
    writeln('FindSym failed for ELF_HEADER_SIZE. lo = ', lo);
    writeln('SymCount = ', SymCount);
    for i := 0 to SymCount-1 do
      writeln('  Sym ', i, ': ', Syms[i].Name);
  end;
  Result := -1;
end;

function FindCompiledUnit(const name: AnsiString): Integer;
var i, j, unitIdx: Integer; lo: AnsiString;
begin
  lo := name;
  for j := 1 to Length(lo) do
    if lo[j] in ['A'..'Z'] then
      lo[j] := Chr(Ord(lo[j]) + 32);
  for i := 0 to CompiledUnitCount - 1 do
  begin
    unitIdx := CompiledUnits[i];
    if Strs[unitIdx].Text = lo then
    begin
      Result := unitIdx;
      Exit;
    end;
  end;
  Result := -1;
end;

function FindUnitOrAlias(const name: AnsiString): Integer;
{ Like FindCompiledUnit, but also resolves a `uses .. as alias` name to the REAL
  unit's Strs[] index (symbols are tagged with that index, so the qualifier must
  match it — feature-uses-alias-as). }
var i, j: Integer; lo: AnsiString;
begin
  { An explicit alias WINS over a unit that happens to carry the same name. The
    alias was written on purpose (`import tkinter as tk`), while the same-named
    unit is usually one pulled in transitively — lib/pcl/tk.pas is exactly that
    case, and letting it win made `tk.Tk_()` resolve against the wrong unit and
    report the member as undefined. This is also Python's own rule: the alias
    rebinds the name in this module's namespace. }
  lo := name;
  for j := 1 to Length(lo) do
    if lo[j] in ['A'..'Z'] then lo[j] := Chr(Ord(lo[j]) + 32);
  { Chase the alias CHAIN, not one link: the NilPy shim mapping registers
    `<module> -> mimic_<module>` as an alias too, so `import pkga.sub as ps`
    is ps -> pkga_sub -> mimic_pkga_sub, and stopping at the first hop left the
    qualifier pointing at a unit that was never compiled. Bounded by the table
    size, so a cyclic pair cannot spin. }
  j := 0;
  while j < UnitAliasCount do
  begin
    i := 0;
    while (i < UnitAliasCount) and (Strs[UnitAliasName[i]].Text <> lo) do Inc(i);
    if i >= UnitAliasCount then Break;
    Result := UnitAliasReal[i];
    lo := Strs[Result].Text;
    Inc(j);
  end;
  if j > 0 then Exit;
  Result := FindCompiledUnit(name);
end;

function FindSymInUnit(const name: AnsiString; unitIdx: Integer): Integer;
var i: Integer;
begin
  i := SymHashHead[SymNameFoldHash(name)];
  while i >= 0 do
  begin
    if (SymUnitIdx[i] = unitIdx) and StrEqual(Syms[i].Name, name) then
    begin
      Result := i;
      Exit;
    end;
    i := SymHashPrev[i];
  end;
  i := SymHashHead[SymNameFoldHash(name)];
  while i >= 0 do
  begin
    if (SymUnitIdx[i] = unitIdx) and (not SymCaseSensitive[i]) and
       CaseEqual(Syms[i].Name, name) then
    begin
      Result := i;
      Exit;
    end;
    i := SymHashPrev[i];
  end;
  Result := -1;
end;

procedure StampDeclSeq(symIdx: Integer);
{ Record a program/unit global var's declaration token so FindSym can hide it from
  routines whose body is positioned before it (declare-before-use for globals,
  FPC-parity). Locals/params/consts/types are not skGlobal, so they are never
  stamped and stay visible as before. Only source-order globals registered during
  the declaration pre-scan are gated; synthetic globals allocated while compiling a
  body (e.g. the string-Result slot) run with PreScanPass=False and stay visible. }
begin
  if PreScanPass and (Syms[symIdx].Kind = skGlobal) then
    { Record the declaration's SOffset (immutable char-pool position, monotonic in
      lex/source order), NOT the token INDEX: token indices are renumbered by pass-2
      excisions/inserts while SOffsets never move, keeping decl-order stable — see
      the CurBodyHdrTok note in ParseSubroutine (bug-impl-prescan-late-include-var-section). }
    SymDeclTok[symIdx] := Tokens[TokPos].SOffset;
end;

procedure SymSyncTypeRef(idx: Integer);
{ feature-a-typeref-migrate-consumers lane 1 (see devdocs/dev/type-identity-as-substrate.md
  and devdocs/progress/working/feature-a-typeref-migrate-consumers.md). Mirrors the
  existing per-symbol type-identity fields into SymTR[idx] as ONE literal, direct
  copy — no re-derivation, no semantic reinterpretation. Call this after every site
  that writes any of: TypeKind, RecName, ElemType, ElemRecName, IsArray, ArrLen,
  PtrElemTk, PtrElemRec, SymProcSig[idx], SymDynDepth[idx]. ADDITIVE ONLY: nothing
  reads SymTR yet, so this function existing/being called cannot change compiler
  behaviour; it only keeps the new array from silently going stale ahead of the
  read-migration step. Do NOT call this from a hot inner loop unrelated to symbol
  type mutation — it's meant to sit right after the old-field writes it mirrors.
  SymTR is a PARALLEL ARRAY, not a TSymbol field — see the SymTR declaration
  comment in defs.inc for why a TSymbol field breaks the self-host bootstrap. }
begin
  SymTR[idx].Kind       := Syms[idx].TypeKind;
  SymTR[idx].RecId      := Syms[idx].RecName;
  SymTR[idx].ElemTk     := Ord(Syms[idx].ElemType);
  SymTR[idx].ElemRec    := Syms[idx].ElemRecName;
  SymTR[idx].PtrBaseTk  := Ord(Syms[idx].PtrElemTk);
  SymTR[idx].PtrBaseRec := Syms[idx].PtrElemRec;
  if Syms[idx].IsArray then
    SymTR[idx].ArrLen := Syms[idx].ArrLen
  else
    SymTR[idx].ArrLen := -1;
  SymTR[idx].ProcSig  := SymProcSig[idx];
  SymTR[idx].DynDepth := SymDynDepth[idx];
end;

procedure EnsureSymCapacity(need: Integer);
{ Grow Syms + all ~30 parallel Sym* arrays (and SymHashPrev) so index `need-1` is in
  bounds. Called at each Alloc* chokepoint; doubling from 16384; capacity never shrinks
  across the per-frontend SymCount reset. ALL parallel arrays grow in lockstep — a
  missed one is a silent out-of-bounds. See feature-dynamic-compiler-tables. }
var n: Integer;
begin
  if need <= SymCapacity then Exit;
  if SymCapacity = 0 then n := 16384 else n := SymCapacity;
  while n < need do n := n * 2;
  SetLength(Syms, n);              SetLength(SymCaseSensitive, n);  SetLength(SymUnitIdx, n);
  SetLength(SymDynDepth, n);       SetLength(SymDeclTypeNOff, n);   SetLength(SymDeclTypeNLen, n);
  SetLength(SymElemDynDepth, n);   SetLength(SymDynElemRowLen, n);  SetLength(SymDynElemRowLo, n);
  SetLength(SymGenSlot, n);        SetLength(SymProcSig, n);        SetLength(SymElemProcSig, n);
  SetLength(SymSetEnumId, n);      SetLength(SymEnumId, n);         SetLength(SymSetElemTk, n);
  SetLength(SymStrCap, n);         SetLength(SymIsSub, n);          SetLength(SymSubLo, n);
  SetLength(SymSubHi, n);          SetLength(SymPtrDepth, n);       SetLength(SymPtrBaseTk, n);
  SetLength(SymPtrBaseRec, n);     SetLength(SymPtrElemArrLen, n);  SetLength(SymPtrElemNDims, n);  SetLength(SymArrNDims, n);
  SetLength(SymRTTIOff, n);        SetLength(SymIsHiddenArgTemp, n); SetLength(SymBlockId, n);
  SetLength(SymStaticLocal, n);
  SetLength(SymDeclTok, n);        SetLength(SymHashPrev, n);       SetLength(SymPtrPointeeConst, n);
  SetLength(SymCLongRank, n);      SetLength(SymTR, n);
  SetLength(SymCellPtr, n);
  { the two per-DIMENSION tables ride the same index, MAX_ARR_DIMS to a symbol }
  SetLength(SymArrDimLo, n * MAX_ARR_DIMS);   SetLength(SymArrDimSpan, n * MAX_ARR_DIMS);
  SymCapacity := n;
end;

function AllocVar(const name: AnsiString; tk: TTypeKind): Integer;
var sz, align: Integer;
begin
  EnsureSymCapacity(SymCount + 1);
  Syms[SymCount].Name     := name;
  Syms[SymCount].TypeKind := tk;
  Syms[SymCount].ConstVal := 0;
  SymCLongRank[SymCount]  := 0;
  Syms[SymCount].IsArray  := False;
  Syms[SymCount].ArrLen   := 0;
  SymDeclTypeNOff[SymCount] := 0; SymDeclTypeNLen[SymCount] := 0;
  SymDynDepth[SymCount] := 0;
  SymElemDynDepth[SymCount] := 0;
  SymArrNDims[SymCount] := 0;
  SymGenSlot[SymCount] := -1;
  SymProcSig[SymCount] := -1;
  SymElemProcSig[SymCount] := -1;
  SymSetEnumId[SymCount] := -1;
  SymEnumId[SymCount] := -1;
  SymSetElemTk[SymCount] := 0;
  SymStrCap[SymCount] := 0;
  SymIsSub[SymCount] := LastTypeIsSub;
  if LastTypeIsSub then
  begin
    SymSubLo[SymCount] := LastTypeSubLo;
    SymSubHi[SymCount] := LastTypeSubHi;
  end;
  SymPtrDepth[SymCount] := 0;
  SymCellPtr[SymCount] := -1;
  SymPtrBaseTk[SymCount] := Ord(tyUnknown);
  SymPtrBaseRec[SymCount] := REC_NONE;
  SymPtrElemArrLen[SymCount] := 0;
  SymPtrElemNDims[SymCount] := 0;
  SymDynElemRowLen[SymCount] := 0;
  SymDynElemRowLo[SymCount] := 0;
  if TypeIsFrozenString(tk) and (tk <> tyString) then
    SymStrCap[SymCount] := LastTypeStrCap;
  SymRTTIOff[SymCount] := -1;
  SymIsHiddenArgTemp[SymCount] := False;
  SymStaticLocal[SymCount] := AllocStaticLocal;
  SymBlockId[SymCount] := CurBlockId;
  Syms[SymCount].ElemType := tyInteger;
  if tk = tyAnsiString then
    Syms[SymCount].ElemType := tyChar;
  Syms[SymCount].RecName  := LastTypeRecId;
  Syms[SymCount].IsRef    := False;
  SymCaseSensitive[SymCount] := DeclCaseSensitive;
  SymUnitIdx[SymCount] := CurrentUnitIdx;
  Syms[SymCount].PtrElemTk := tyUnknown;
  Syms[SymCount].PtrElemRec := REC_NONE;
  if tk = tyPointer then
  begin
    Syms[SymCount].PtrElemTk := LastTypePointerElemTk;
    Syms[SymCount].PtrElemRec := LastTypePointerElemRec;
    SymPtrDepth[SymCount] := LastTypePointerDepth;
    SymPtrBaseTk[SymCount] := LastTypePointerBaseTk;
    SymPtrBaseRec[SymCount] := LastTypePointerBaseRec;
  end;

  if tk = tyAuto then
  begin
    Syms[SymCount].Offset := 0;
    if (CurProc < 0) or AllocStaticLocal then
      Syms[SymCount].Kind := skGlobal
    else
      Syms[SymCount].Kind := skLocal;
  end
  else
  begin
    sz := TypeSize(tk);
    if tk = tyString then
    begin
      { A NAMED global frozen string reserves the full capacity (it may hold any
        string / be reset). A hidden temp (name = '', e.g. a concat result
        materialised as a call argument in the main body) never needs 8 MB — give
        it the bounded local capacity, like the same temp inside a procedure
        (bug-ansistring-concat-arg-static-bloat: each such main-scope site
        otherwise reserved ~8 MB of BSS). }
      if (CurProc < 0) and (name <> '') then sz := STRING_CAP + 8
      else sz := LOCAL_STR_CAP + 8;
    end
    else if (tk = tyFixedString) or (tk = tyShortString) then
      sz := FrozenStrSlotSize(tk, SymStrCap[SymCount])
    else if tk = tyRecord then sz := RecSize(LastTypeRecId);
    if (tk = tyRecord) and (LastTypeRecId >= REC_UCLASS_BASE) and
       (UClsAlign[LastTypeRecId - REC_UCLASS_BASE] > TARGET_PTR_SIZE) then
      align := UClsAlign[LastTypeRecId - REC_UCLASS_BASE]
    else
      align := TypeAlign(tk);

    if (CurProc < 0) or AllocStaticLocal then
    begin
      BSSSize := AlignTo(BSSSize, align);
      Syms[SymCount].Kind   := skGlobal;
      Syms[SymCount].Offset := BSSSize;
      Inc(BSSSize, sz);
    end
    else
    begin
      FrameSize := AlignTo(FrameSize + sz, align);
      Syms[SymCount].Kind   := skLocal;
      Syms[SymCount].Offset := -FrameSize;
    end;
  end;
  SymSyncTypeRef(SymCount);
  Result := SymCount; SymHashInsert(Result); Inc(SymCount); StampDeclSeq(Result);
end;

{ The ABI oracle answers both parameter-slot questions now — the SIZE rule that
  used to live here as ParamSlotIsPointer, and the SLOT-HOLDS rule the five
  backends each wrote out longhand. Implemented in abi.inc, which is included
  after this file (it needs TypeIsFrozenString), so the forwards live here.
  feature-a-abi-oracle }
function ABIParamSlotIsPointer(tk: TTypeKind; isRef, isArray: Boolean): Boolean; forward;
function ABIParamSlotHoldsValueAddr(symIdx: Integer): Boolean; forward;

function ParamSize(idx: Integer): Integer;
begin
  if ABIParamSlotIsPointer(Syms[idx].TypeKind, Syms[idx].IsRef, Syms[idx].IsArray) then
    Result := TARGET_PTR_SIZE
  else
    Result := TypeSize(Syms[idx].TypeKind);
end;

function AllocParam(const name: AnsiString; tk: TTypeKind; isRef, isArray: Boolean): Integer;
var sz, align: Integer;
begin
  EnsureSymCapacity(SymCount + 1);
  SymDeclTypeNOff[SymCount] := 0; SymDeclTypeNLen[SymCount] := 0;
  Syms[SymCount].Name     := name;
  Syms[SymCount].TypeKind := tk;
  Syms[SymCount].ConstVal := 0;
  Syms[SymCount].IsArray  := isArray;
  Syms[SymCount].ArrLen   := 0;
  if isArray then Syms[SymCount].ArrLen := 1000;
  SymDynDepth[SymCount] := 0;
  SymElemDynDepth[SymCount] := 0;
  { Reset recycled parallel-array fields — a stale SymArrNDims >= 2 from a
    popped local reappearing under a new symbol at the same slot made a 1-D
    named-array param index with the old N-D dims (silent stride corruption;
    bug-transitive-dns_cache-import-corrupts-managed-strings). }
  SymArrNDims[SymCount] := 0;
  { Same recycled-slot landmine for the lazy-var block id: a param reusing the
    slot of a popped MID-BLOCK local (an on-handler binder, a lifted temp)
    inherited that dead block and IsBlockVisible filtered the param out of
    FindSym — every routine following a `try..except on E: ... do` lost its
    params (blcksock's SetLinger, bug-on-handler-poisons-next-proc-params). }
  SymBlockId[SymCount] := CurBlockId;
  SymGenSlot[SymCount] := -1;
  SymProcSig[SymCount] := -1;
  SymElemProcSig[SymCount] := -1;
  SymSetEnumId[SymCount] := -1;
  SymEnumId[SymCount] := -1;
  SymSetElemTk[SymCount] := 0;
  SymStrCap[SymCount] := 0;
  SymIsSub[SymCount] := LastTypeIsSub;
  if LastTypeIsSub then
  begin
    SymSubLo[SymCount] := LastTypeSubLo;
    SymSubHi[SymCount] := LastTypeSubHi;
  end;
  SymPtrDepth[SymCount] := 0;
  SymCellPtr[SymCount] := -1;
  SymPtrBaseTk[SymCount] := Ord(tyUnknown);
  SymPtrBaseRec[SymCount] := REC_NONE;
  SymPtrElemArrLen[SymCount] := 0;
  SymPtrElemNDims[SymCount] := 0;
  SymDynElemRowLen[SymCount] := 0;
  SymDynElemRowLo[SymCount] := 0;
  if TypeIsFrozenString(tk) and (tk <> tyString) then
    SymStrCap[SymCount] := LastTypeStrCap;
  SymRTTIOff[SymCount] := -1;
  Syms[SymCount].ElemType := tk;
  Syms[SymCount].RecName  := LastTypeRecId;
  Syms[SymCount].IsRef    := isRef;
  Syms[SymCount].Kind     := skParam;
  SymCaseSensitive[SymCount] := DeclCaseSensitive;
  SymUnitIdx[SymCount] := CurrentUnitIdx;
  Syms[SymCount].PtrElemTk := tyUnknown;
  Syms[SymCount].PtrElemRec := REC_NONE;
  if tk = tyPointer then
  begin
    Syms[SymCount].PtrElemTk := LastTypePointerElemTk;
    Syms[SymCount].PtrElemRec := LastTypePointerElemRec;
    SymPtrDepth[SymCount] := LastTypePointerDepth;
    SymPtrBaseTk[SymCount] := LastTypePointerBaseTk;
    SymPtrBaseRec[SymCount] := LastTypePointerBaseRec;
  end;

  if (tk = tyRecord) and not isRef and not isArray and (RecSize(LastTypeRecId) <= 8) then
  begin
    { A genuinely by-value record (not var/const/out, not forced to by-ref by
      size -- that only happens for RecSize > 8) is stored inline in this
      param's own slot, not behind a pointer -- so the slot must hold the
      whole record, not just one machine word. On a 64-bit target
      TARGET_PTR_SIZE (8) already covers any RecSize <= 8, so this is a
      no-op there; on a 32-bit target (TARGET_PTR_SIZE = 4) a 5-8 byte
      record previously got only a 4-byte slot, so writing its second word
      (e.g. the arm32 by-value record-arg fix in ir_codegen_arm32.inc /
      pasparser_proc.inc's prologue spill) silently overflowed into whatever symbol's
      slot happened to sit right after it
      (bug-arm32-record-byvalue-over-4-bytes-abi-gap). Never smaller than
      TARGET_PTR_SIZE, matching the existing tiny-record (<=4-byte) case. }
    sz := RecSize(LastTypeRecId);
    if sz < TARGET_PTR_SIZE then sz := TARGET_PTR_SIZE;
  end
  else if ABIParamSlotIsPointer(tk, isRef, isArray) then
    sz := TARGET_PTR_SIZE
  else
    sz := TypeSize(tk);

  if ABIParamSlotIsPointer(tk, isRef, isArray) then
    align := TARGET_PTR_SIZE
  else
    align := TypeAlign(tk);
  FrameSize := AlignTo(FrameSize + sz, align);
  Syms[SymCount].Offset := -FrameSize;
  SymSyncTypeRef(SymCount);
  Result := SymCount; SymHashInsert(Result); Inc(SymCount); StampDeclSeq(Result);
end;

function DoubleBitsToSingleBits(bits: Int64): Integer;
{ Narrow an IEEE-754 double's BITS to a single's bits, by letting the host do
  the conversion. A float const literal is recorded as the DOUBLE's bit
  pattern whatever the declared element type is, so baking a `array of Single`
  by copying the low 4 bytes of that pattern produces garbage -- measured:
  (0.0, -1.5, 2.5, 1e30) read back as (0, 0, 0, 3.06e-4).

  The host's narrowing is the right oracle rather than a hand-rolled
  exponent/mantissa rebias: every host this compiler builds on is IEEE-754
  round-to-nearest-even, which is exactly what the target's cvtsd2ss (or its
  equivalent) would have done on the startup-store path this replaces. }
var d: Double; f: Single; pd: ^Int64; pf: ^Integer;
begin
  pd := @d; pd^ := bits;
  f := d;
  pf := @f; Result := pf^;
end;

function TypedConstBakeable(tk: TTypeKind): Boolean;
{ Can an element of this type be written into .data as raw little-endian bytes
  from the ordinal the const parser recorded? Deliberately a SHORT list: an
  ordinal or a float, nothing whose value is a handle, an address or a
  layout. A string element is a heap handle built at startup, a record element
  is a field list, a pointer element is a fixup -- each of those needs the
  existing per-element init path and gets it, because promotion is all-or-
  nothing per array. }
begin
  Result := TypeIsOrdinal(tk) or (tk = tyDouble) or (tk = tySingle);
  if Result and (TypeSize(tk) <> 1) and (TypeSize(tk) <> 2) and
     (TypeSize(tk) <> 4) and (TypeSize(tk) <> 8) then
    Result := False;
end;

function TryBakeConstArrayIntoData(symIdx, firstPI, bssBefore, bssAfterAlloc: Integer): Boolean;
{ Turn a just-parsed typed const ARRAY from "BSS + one generated store per
  element at startup" into initialised .data.

  Measured before this existed: a 696-entry `array of UInt64` cost **+20,152
  bytes of CODE** and zero bytes of data -- ~29 bytes of machine code per
  element, run at program start, in every binary that links the unit, whether
  or not it ever reads the array. Int64, Double and Cardinal all did the same,
  so it was every typed const array, not a 64-bit case. sysutils' 696-entry
  Eisel-Lemire power-of-ten table alone carried ~31 KB of that
  (bug-a-a-typed-const-array-is-built-by-startup-code-not-stored-as-data).
  It is worst exactly where it hurts most: on xtensa a 10 KB table became
  ~40 KB of flash plus a boot-time fill.

  The storage moves to .data via DATA_SYM_BIAS -- see that constant for why a
  bias rather than a flag or a sentinel. .data is WRITABLE here (one RWX
  PT_LOAD), which is required, not incidental: FPC's {$J+} writable typed
  constants are a real feature and a read-only section would turn a working
  program into a fault.

  All-or-nothing per array, and it fails CLOSED: any element the const parser
  recorded as something other than a plain ordinal/float literal (a string, a
  `@proc`, a class ref, a record field list, a set) leaves the whole array on
  the existing startup-store path. Rejecting is always correct; promoting
  something unbakeable would be silent wrong data.

  Refused for object/shared output: those writers emit RELOCATIONS against a
  section symbol rather than patching an absolute address, so a data-resident
  global needs a different section index there. Not done yet, and refusing is
  what keeps that honest. }
var k, n, esz, base, b: Integer; v: Int64; elemTk: TTypeKind;
begin
  Result := False;
  if EmitObjMode or EmitSharedMode then Exit;
  if (symIdx < 0) or not Syms[symIdx].IsArray then Exit;
  if Syms[symIdx].Kind <> skGlobal then Exit;
  n := Syms[symIdx].ArrLen;
  if n <= 0 then Exit;
  if PendingInitCount - firstPI <> n then Exit;
  elemTk := Syms[symIdx].ElemType;
  if not TypedConstBakeable(elemTk) then Exit;
  if SymElemDynDepth[symIdx] > 0 then Exit;
  if SymIsSub[symIdx] then Exit;    { a subrange element still stores its ordinal, but leave the narrow cases alone until one is measured }
  esz := TypeSize(elemTk);

  { Every recorded init must be a plain literal for THIS array, in element
    order, covering the whole extent. Kind 0 is an ordinal, kind 3 a float
    whose IEEE bits are already in Val. Anything else -> refuse. }
  for k := firstPI to PendingInitCount - 1 do
  begin
    if PendingInitSym[k] <> symIdx then Exit;
    if PendingInitFOff[k] <> -1 then Exit;
    if (PendingInitKind[k] <> 0) and (PendingInitKind[k] <> 3) then Exit;
    if PendingInitElem[k] <> Syms[symIdx].ConstVal + (k - firstPI) then Exit;
  end;

  base := AlignTo(DataLen, TypeAlign(elemTk));
  if base + n * esz >= MAX_DATA then Exit;   { out of data space: keep the old path rather than fail the compile }
  for k := firstPI to PendingInitCount - 1 do
  begin
    v := PendingInitVal[k];
    { A float literal always arrives as the DOUBLE's bits; a Single element
      needs them narrowed, not truncated. }
    if elemTk = tySingle then v := DoubleBitsToSingleBits(v);
    for b := 0 to esz - 1 do
      Data[base + (k - firstPI) * esz + b] := Byte((v shr (8 * b)) and $FF);
  end;
  DataLen := base + n * esz;

  Syms[symIdx].Offset := DATA_SYM_BIAS + base;
  PendingInitCount := firstPI;
  { Reclaim the BSS the array was already given -- otherwise the fix would
    trade 20 KB of code for 5.5 KB of dead BSS and the RAM half of the ticket
    would still be open. Only when the array is still the LAST thing allocated:
    the const initialiser parse allocates no globals today, but rolling back
    over something that did would alias two symbols onto one address, and that
    is a bug nothing would report. Not reclaiming merely wastes space. }
  if BSSSize = bssAfterAlloc then BSSSize := bssBefore;
  Result := True;
end;

function AllocArray(const name: AnsiString; elemType: TTypeKind; lo, hi: Integer): Integer;
var elemSize, totalSize, align: Integer;
begin
  EnsureSymCapacity(SymCount + 1);
  SymDeclTypeNOff[SymCount] := 0; SymDeclTypeNLen[SymCount] := 0;
  if LastTypeElemDynDepth > 0 then
  begin
    { Element is itself a dynamic array (`array[..] of TDynAlias`): each slot holds
      a pointer-sized heap handle. The base element type/rec stay in
      elemType/LastTypeRecId; SymElemDynDepth (set below) marks the slots dynamic. }
    elemSize := TARGET_PTR_SIZE;
    align := TARGET_PTR_SIZE;
  end
  else if elemType = tyString then
  begin
    if CurProc < 0 then elemSize := STRING_CAP + 8
    else elemSize := LOCAL_STR_CAP + 8;
    align := TARGET_PTR_SIZE;
  end
  else if (elemType = tyFixedString) or (elemType = tyShortString) then
  begin
    elemSize := FrozenStrSlotSize(elemType, LastTypeStrCap);
    align := TARGET_PTR_SIZE;
  end
  else if elemType = tyRecord then
  begin
    elemSize := RecSize(LastTypeRecId);
    if (LastTypeRecId >= REC_UCLASS_BASE) and
       (UClsAlign[LastTypeRecId - REC_UCLASS_BASE] > TARGET_PTR_SIZE) then
      align := UClsAlign[LastTypeRecId - REC_UCLASS_BASE]
    else
      align := TARGET_PTR_SIZE;
  end
  else
  begin
    elemSize := TypeSize(elemType);
    align := TypeAlign(elemType);
  end;

  totalSize := (hi - lo + 1) * elemSize;
  Syms[SymCount].Name     := name;
  Syms[SymCount].TypeKind := elemType;
  Syms[SymCount].ConstVal := lo;   { lo bound stored in ConstVal }
  Syms[SymCount].IsArray  := True;
  Syms[SymCount].ArrLen   := hi - lo + 1;
  SymDynDepth[SymCount] := 0;
  SymElemDynDepth[SymCount] := LastTypeElemDynDepth;
  SymArrNDims[SymCount] := 0;
  SymProcSig[SymCount] := -1;
  SymElemProcSig[SymCount] := -1;
  SymRTTIOff[SymCount] := -1;
  { Match AllocVar: reset recycled parallel-array fields (see AllocDynArray). }
  SymGenSlot[SymCount] := -1;
  SymSetEnumId[SymCount] := -1;
  SymEnumId[SymCount] := -1;
  SymSetElemTk[SymCount] := 0;
  SymStrCap[SymCount] := 0;
  SymIsSub[SymCount] := LastTypeIsSub;
  if LastTypeIsSub then
  begin
    SymSubLo[SymCount] := LastTypeSubLo;
    SymSubHi[SymCount] := LastTypeSubHi;
  end;
  SymPtrDepth[SymCount] := 0;
  SymCellPtr[SymCount] := -1;
  SymPtrBaseTk[SymCount] := Ord(tyUnknown);
  SymPtrBaseRec[SymCount] := REC_NONE;
  SymPtrElemArrLen[SymCount] := 0;
  SymPtrElemNDims[SymCount] := 0;
  SymDynElemRowLen[SymCount] := 0;
  SymDynElemRowLo[SymCount] := 0;
  if (elemType = tyFixedString) or (elemType = tyShortString) then
    SymStrCap[SymCount] := LastTypeStrCap;
  SymIsHiddenArgTemp[SymCount] := False;
  SymStaticLocal[SymCount] := AllocStaticLocal;
  SymBlockId[SymCount] := CurBlockId;
  Syms[SymCount].ElemType := elemType;
  Syms[SymCount].ElemRecName := LastTypeRecId;
  Syms[SymCount].IsRef    := False;
  Syms[SymCount].PtrElemTk := tyUnknown;
  Syms[SymCount].PtrElemRec := REC_NONE;
  SymCaseSensitive[SymCount] := DeclCaseSensitive;
  SymUnitIdx[SymCount] := CurrentUnitIdx;
  if elemType = tyPointer then
  begin
    Syms[SymCount].PtrElemTk := LastTypePointerElemTk;
    Syms[SymCount].PtrElemRec := LastTypePointerElemRec;
    SymPtrDepth[SymCount] := LastTypePointerDepth;
    SymPtrBaseTk[SymCount] := LastTypePointerBaseTk;
    SymPtrBaseRec[SymCount] := LastTypePointerBaseRec;
  end;

  if (CurProc < 0) or AllocStaticLocal then
  begin
    BSSSize := AlignTo(BSSSize, align);
    Syms[SymCount].Kind   := skGlobal;
    Syms[SymCount].Offset := BSSSize;
    Inc(BSSSize, totalSize);
  end
  else
  begin
    FrameSize := AlignTo(FrameSize + totalSize, align);
    Syms[SymCount].Kind   := skLocal;
    Syms[SymCount].Offset := -FrameSize;
  end;
  LastTypeElemDynDepth := 0;   { consumed }
  SymSyncTypeRef(SymCount);
  Result := SymCount; SymHashInsert(Result); Inc(SymCount); StampDeclSeq(Result);
end;

function AllocDynArray(const name: AnsiString; elemType: TTypeKind; depth: Integer): Integer;
{ Dynamic array (array of T): a pointer-sized slot holding a heap data pointer.
  ArrLen = -1 marks the symbol as dynamic (static arrays always have ArrLen >= 1).
  depth is the nesting count: 1 for `array of T`, 2 for `array of array of T`...
  elemType is the BASE element type at the deepest level. }
begin
  EnsureSymCapacity(SymCount + 1);
  SymDeclTypeNOff[SymCount] := 0; SymDeclTypeNLen[SymCount] := 0;
  Syms[SymCount].Name        := name;
  Syms[SymCount].TypeKind    := elemType;
  Syms[SymCount].ConstVal    := 0;            { lower bound: dynamic arrays are 0-based }
  Syms[SymCount].IsArray     := True;
  Syms[SymCount].ArrLen      := -1;           { -1 = dynamic }
  SymDynDepth[SymCount] := depth;
  SymElemDynDepth[SymCount] := 0;
  SymArrNDims[SymCount] := 0;
  SymProcSig[SymCount] := -1;
  SymElemProcSig[SymCount] := -1;
  SymRTTIOff[SymCount] := -1;
  { Reset the same recycled parallel-array fields AllocVar does — symbol slots
    are reused after a proc body restores SymCount, so a stale SymBlockId here
    would make a dyn-array global declared after a method (whose for-in/locals
    occupied this slot) invisible to FindSym ('undefined variable'). }
  SymGenSlot[SymCount] := -1;
  SymSetEnumId[SymCount] := -1;
  SymEnumId[SymCount] := -1;
  SymSetElemTk[SymCount] := 0;
  SymStrCap[SymCount] := 0;
  SymIsSub[SymCount] := LastTypeIsSub;
  if LastTypeIsSub then
  begin
    SymSubLo[SymCount] := LastTypeSubLo;
    SymSubHi[SymCount] := LastTypeSubHi;
  end;
  SymPtrDepth[SymCount] := 0;
  SymCellPtr[SymCount] := -1;
  SymPtrBaseTk[SymCount] := Ord(tyUnknown);
  SymPtrBaseRec[SymCount] := REC_NONE;
  SymPtrElemArrLen[SymCount] := 0;
  SymPtrElemNDims[SymCount] := 0;
  { `array of T` where T is a named FIXED array: the parser leaves the row
    shape in LastTypeDynElemRowLen/Lo; stamp it (depth-1 only) and reset. }
  if (depth = 1) and (LastTypeDynElemRowLen > 0) then
  begin
    SymDynElemRowLen[SymCount] := LastTypeDynElemRowLen;
    SymDynElemRowLo[SymCount]  := LastTypeDynElemRowLo;
  end
  else
  begin
    SymDynElemRowLen[SymCount] := 0;
    SymDynElemRowLo[SymCount] := 0;
  end;
  LastTypeDynElemRowLen := 0;   { consumed; caller re-sets per name in a multi-name decl }
  LastTypeDynElemRowLo := 0;
  if (elemType = tyFixedString) or (elemType = tyShortString) then
    SymStrCap[SymCount] := LastTypeStrCap;
  SymIsHiddenArgTemp[SymCount] := False;
  SymStaticLocal[SymCount] := AllocStaticLocal;
  SymBlockId[SymCount] := CurBlockId;
  Syms[SymCount].ElemType    := elemType;
  Syms[SymCount].ElemRecName := LastTypeRecId;
  Syms[SymCount].IsRef       := False;
  Syms[SymCount].PtrElemTk := tyUnknown;
  Syms[SymCount].PtrElemRec := REC_NONE;
  SymCaseSensitive[SymCount] := DeclCaseSensitive;
  SymUnitIdx[SymCount] := CurrentUnitIdx;
  if elemType = tyPointer then
  begin
    Syms[SymCount].PtrElemTk := LastTypePointerElemTk;
    Syms[SymCount].PtrElemRec := LastTypePointerElemRec;
    SymPtrDepth[SymCount] := LastTypePointerDepth;
    SymPtrBaseTk[SymCount] := LastTypePointerBaseTk;
    SymPtrBaseRec[SymCount] := LastTypePointerBaseRec;
  end;
  if CurProc < 0 then
  begin
    BSSSize := AlignTo(BSSSize, TARGET_PTR_SIZE);
    Syms[SymCount].Kind   := skGlobal;
    Syms[SymCount].Offset := BSSSize;
    Inc(BSSSize, TARGET_PTR_SIZE);
  end
  else
  begin
    FrameSize := AlignTo(FrameSize + TARGET_PTR_SIZE, TARGET_PTR_SIZE);
    Syms[SymCount].Kind   := skLocal;
    Syms[SymCount].Offset := -FrameSize;
  end;
  SymSyncTypeRef(SymCount);
  Result := SymCount; SymHashInsert(Result); Inc(SymCount); StampDeclSeq(Result);
end;

function AllocTemp: Integer;
begin Result := AllocVar('', tyInteger); end;

function CharConstSymOf(const name: AnsiString): Integer;
{ The symbol index of a CHAR constant of this name, or -1. A one-character
  untyped const is typed Char rather than a one-character string
  (bug-pascal-ord-of-a-one-char-string-const-is-its-address), so the const-
  expression concatenator has to recognise one as an operand the way it already
  recognises a named string const. Deliberately narrow: skConst AND tyChar, so
  a same-named variable or a char PARAMETER cannot be mistaken for one. }
var i: Integer;
begin
  CharConstSymOf := -1;
  i := FindSym(name);
  if i < 0 then Exit;
  if (Syms[i].Kind = skConst) and (Syms[i].TypeKind = tyChar) then
    CharConstSymOf := i;
end;

function AddConst(const name: AnsiString; tk: TTypeKind; v: Int64): Integer;
begin
  EnsureSymCapacity(SymCount + 1);
  Syms[SymCount].Name     := name;
  Syms[SymCount].TypeKind := tk;
  Syms[SymCount].Kind     := skConst;
  Syms[SymCount].ConstVal := v;
  Syms[SymCount].Offset   := 0;
  Syms[SymCount].IsRef    := False;
  Syms[SymCount].IsArray  := False;
  Syms[SymCount].ArrLen   := 0;
  SymArrNDims[SymCount] := 0;   { slot recycling — see AllocParam }
  SymBlockId[SymCount] := CurBlockId;   { slot recycling — see AllocParam }
  SymEnumId[SymCount] := -1;    { slot recycling — every Alloc* must reset EVERY parallel array }
  SymCaseSensitive[SymCount] := DeclCaseSensitive;
  SymUnitIdx[SymCount] := CurrentUnitIdx;
  SymSyncTypeRef(SymCount);
  Result := SymCount; SymHashInsert(Result); Inc(SymCount); StampDeclSeq(Result);
end;

{ ===== Variable load/store ===== }

{ Register calling convention (feature-callconv-register-args, -O2 x86-64): if
  idx is a param currently resident in r14/r15, return that register number (14
  or 15), else 0. O(RcResidentCount<=2). Non-x86-64 and -O0/-O1 keep the count at
  0, so this always returns 0 there and the residency emit paths never fire. }
function ResidentRegOf(idx: Integer): Integer;
var k: Integer;
begin
  ResidentRegOf := 0;
  for k := 0 to RcResidentCount - 1 do
    if RcResidentSym[k] = idx then
    begin
      ResidentRegOf := RcResidentReg[k];
      Exit;
    end;
end;

{ -O3 float loop residency (x86-64): if idx is a tyDouble local/param currently
  resident in xmm8..xmm13, return that xmm number, else 0. Assigned by
  UnifiedResidencyAssign; the registers are callee-saved in the pxx internal
  ABI (§5b) and the boundary wraps cover extern/indirect/coswitch/longjmp, so
  the cache is never stale mid-body. }
function FloatResidentXmmOf(idx: Integer): Integer;
var k: Integer;
begin
  FloatResidentXmmOf := 0;
  for k := 0 to FrResidentCount - 1 do
    if FrResidentSym[k] = idx then
    begin
      FloatResidentXmmOf := 8 + k;
      Exit;
    end;
end;

procedure EmitLoadVar(idx: Integer);
var tk: TTypeKind; sz: Integer; sgn: Boolean; rreg: Integer;
begin
  { Resident param read: mov rax, r14/r15 (the frame slot is authoritative but the
    register is a same-value cache — a correctly size/sign-extended value was
    loaded into it at body entry, and every store re-extends it). }
  rreg := ResidentRegOf(idx);
  if rreg <> 0 then
  begin
    EmitB($4C); EmitB($89); EmitB($C0 or ((rreg - 8) shl 3));         { mov rax, r12..r15 }
    Exit;
  end;
  tk := Syms[idx].TypeKind;
  sz := TypeSize(tk);
  sgn := TypeSigned(tk);

  if TypeIsFloat(tk) then
  begin
    { -O3 float loop residency: the value lives in xmm8/xmm9 (call-free body,
      tyDouble only — see UnifiedResidencyAssign). Same contract as a frame
      load: value in xmm0. }
    rreg := FloatResidentXmmOf(idx);
    if rreg <> 0 then
    begin
      EmitB($41); EmitB($0F); EmitB($28); EmitB($C0 or (rreg - 8));  { movaps xmm0, xmm8/xmm9 }
      Exit;
    end;
    if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
    begin
      EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[idx].Offset);  { mov rax, [rbp+off] }
      if tk = tySingle then
      begin
        EmitB($F3); EmitB($0F); EmitB($10); EmitB($00);                { movss xmm0, [rax] }
        EmitB($F3); EmitB($0F); EmitB($5A); EmitB($C0);                { cvtss2sd xmm0, xmm0 }
      end
      else if tk = tyExtended then
      begin
        EmitB($48); EmitB($83); EmitB($EC); EmitB($08);                 { sub rsp, 8 }
        EmitB($DB); EmitB($28);                                          { fldt [rax] }
        EmitB($DD); EmitB($1C); EmitB($24);                             { fstpl [rsp] }
        EmitB($F2); EmitB($0F); EmitB($10); EmitB($04); EmitB($24);    { movsd xmm0, [rsp] }
        EmitB($48); EmitB($83); EmitB($C4); EmitB($08);                 { add rsp, 8 }
      end
      else
        begin EmitB($F2); EmitB($0F); EmitB($10); EmitB($00); end;      { movsd xmm0, [rax] }
    end
    else case Syms[idx].Kind of
      skLocal, skParam:
        if tk = tySingle then
        begin
          EmitB($F3); EmitB($0F); EmitB($10); EmitB($85); EmitI32(Syms[idx].Offset);  { movss xmm0, [rbp+off] }
          EmitB($F3); EmitB($0F); EmitB($5A); EmitB($C0);                            { cvtss2sd xmm0, xmm0 }
        end
        else if tk = tyExtended then
        begin
          EmitB($48); EmitB($83); EmitB($EC); EmitB($08);               { sub rsp, 8 }
          EmitB($DB); EmitB($AD); EmitI32(Syms[idx].Offset);            { fldt [rbp+off] }
          EmitB($DD); EmitB($1C); EmitB($24);                           { fstpl [rsp] }
          EmitB($F2); EmitB($0F); EmitB($10); EmitB($04); EmitB($24);  { movsd xmm0, [rsp] }
          EmitB($48); EmitB($83); EmitB($C4); EmitB($08);               { add rsp, 8 }
        end
        else
          begin EmitB($F2); EmitB($0F); EmitB($10); EmitB($85); EmitI32(Syms[idx].Offset); end;  { movsd xmm0, [rbp+off] }
      skGlobal:
        if tk = tySingle then
        begin
          EmitB($F3); EmitB($0F); EmitB($10); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset);  { movss xmm0, [abs] }
          EmitB($F3); EmitB($0F); EmitB($5A); EmitB($C0);                                             { cvtss2sd xmm0, xmm0 }
        end
        else if tk = tyExtended then
        begin
          EmitB($48); EmitB($83); EmitB($EC); EmitB($08);               { sub rsp, 8 }
          EmitB($DB); EmitB($2C); EmitB($25); EmitGlobRef(Syms[idx].Offset);  { fldt [abs32] }
          EmitB($DD); EmitB($1C); EmitB($24);                           { fstpl [rsp] }
          EmitB($F2); EmitB($0F); EmitB($10); EmitB($04); EmitB($24);  { movsd xmm0, [rsp] }
          EmitB($48); EmitB($83); EmitB($C4); EmitB($08);               { add rsp, 8 }
        end
        else
          begin EmitB($F2); EmitB($0F); EmitB($10); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end; { movsd xmm0, [abs] }
      skConst: MovRaxImm(Syms[idx].ConstVal);
    end;
    Exit;
  end;

  if (Syms[idx].Kind = skParam) and Syms[idx].IsRef and
     (tk <> tyString) then
  begin
    { by-reference scalar: load pointer from slot, then load pointed value }
    EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[idx].Offset);
    if sz = 1 then
    begin
      if sgn then
        begin EmitB($48); EmitB($0F); EmitB($BE); EmitB($00); end { movsx rax, byte [rax] }
      else
        begin EmitB($48); EmitB($0F); EmitB($B6); EmitB($00); end;{ movzx rax, byte [rax] }
    end
    else if sz = 2 then
    begin
      if sgn then
        begin EmitB($48); EmitB($0F); EmitB($BF); EmitB($00); end { movsx rax, word [rax] }
      else
        begin EmitB($48); EmitB($0F); EmitB($B7); EmitB($00); end;{ movzx rax, word [rax] }
    end
    else if sz = 4 then
    begin
      if sgn then
        begin EmitB($48); EmitB($63); EmitB($00); end { movsxd rax, dword [rax] }
      else
        begin EmitB($8B); EmitB($00); end;{ mov eax, dword [rax] (zero-extends to rax) }
    end
    else
      begin EmitB($48); EmitB($8B); EmitB($00); end; { mov rax, [rax] }
  end
  else if (Syms[idx].Kind = skParam) and (tk = tyString) then
  begin
    { param slot holds pointer P to string struct; load P then deref for length }
    EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[idx].Offset); { mov rax, [rbp+off] = P }
    EmitB($48); EmitB($8B); EmitB($00);                              { mov rax, [P] = length }
  end
  else
  begin
    case Syms[idx].Kind of
      skLocal, skParam:
        begin
          if sz = 1 then
          begin
            if sgn then
              begin EmitB($48); EmitB($0F); EmitB($BE); EmitB($85); EmitI32(Syms[idx].Offset); end
            else
              begin EmitB($48); EmitB($0F); EmitB($B6); EmitB($85); EmitI32(Syms[idx].Offset); end;
          end
          else if sz = 2 then
          begin
            if sgn then
              begin EmitB($48); EmitB($0F); EmitB($BF); EmitB($85); EmitI32(Syms[idx].Offset); end
            else
              begin EmitB($48); EmitB($0F); EmitB($B7); EmitB($85); EmitI32(Syms[idx].Offset); end;
          end
          else if sz = 4 then
          begin
            if sgn then
              begin EmitB($48); EmitB($63); EmitB($85); EmitI32(Syms[idx].Offset); end
            else
              begin EmitB($8B); EmitB($85); EmitI32(Syms[idx].Offset); end;
          end
          else
            begin EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[idx].Offset); end;
        end;
      skGlobal:
        begin
          if sz = 1 then
          begin
            if sgn then
              begin EmitB($48); EmitB($0F); EmitB($BE); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end
            else
              begin EmitB($48); EmitB($0F); EmitB($B6); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
          end
          else if sz = 2 then
          begin
            if sgn then
              begin EmitB($48); EmitB($0F); EmitB($BF); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end
            else
              begin EmitB($48); EmitB($0F); EmitB($B7); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
          end
          else if sz = 4 then
          begin
            if sgn then
              begin EmitB($48); EmitB($63); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end
            else
              begin EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
          end
          else
            begin EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
        end;
      skConst:
        MovRaxImm(Syms[idx].ConstVal);
    end;
  end;
end;

{ -O3 store->reload elimination: rax already holds the value that was just
  stored into `idx`, so the reload's only remaining job is the WIDTH fixup.
  EmitStoreVar wrote exactly the low TypeSize(tk) bytes of rax to the slot, and
  EmitLoadVar's extension is a pure function of (size, signedness) of those same
  bytes — so re-extending rax in place gives the identical value without
  touching memory. 8-byte slots need nothing at all.

  MUST MOVE TOGETHER WITH EmitLoadVar's scalar else-branch: the two extension
  choices are the same table, and a load that started extending differently
  would leave this one behind. Only reached for syms ReloadElimSym admits
  (ordinal/pointer, non-resident, non-managed), which is exactly that branch. }
procedure EmitReExtendRax(idx: Integer);
var tk: TTypeKind; sz: Integer; sgn: Boolean;
begin
  tk := Syms[idx].TypeKind;
  sz := TypeSize(tk);
  sgn := TypeSigned(tk);
  if sz >= 8 then Exit;
  if sz = 1 then
  begin
    if sgn then
      begin EmitB($48); EmitB($0F); EmitB($BE); EmitB($C0); end   { movsx rax, al }
    else
      begin EmitB($48); EmitB($0F); EmitB($B6); EmitB($C0); end;  { movzx rax, al }
  end
  else if sz = 2 then
  begin
    if sgn then
      begin EmitB($48); EmitB($0F); EmitB($BF); EmitB($C0); end   { movsx rax, ax }
    else
      begin EmitB($48); EmitB($0F); EmitB($B7); EmitB($C0); end;  { movzx rax, ax }
  end
  else
  begin
    if sgn then
      begin EmitB($48); EmitB($63); EmitB($C0); end               { movsxd rax, eax }
    else
      begin EmitB($89); EmitB($C0); end;                          { mov eax, eax (zero-extends) }
  end;
end;

{ -O1 pass 2 (leaf-sym operand direct load): load a plain scalar local/param/
  global straight into RCX, so a BINOP right operand that is a side-effect-free
  IR_LOAD_SYM skips the push-left / eval-right-into-rax / mov rcx,rax / pop-rax
  dance. Mirrors EmitLoadVar's scalar else-branch byte-for-byte with the reg
  field switched rax(000)->rcx(001): [rbp+disp] ModRM 85->8D, [abs] ModRM+SIB
  04 25->0C 25, mov eax->mov ecx (8B). Guarded by LeafSymRcxLoadable, which
  admits only skLocal/skParam(non-ref)/skGlobal non-float, non-string,
  non-array scalars — every managed/float/by-ref/frozen path stays on the
  general push/pop route untouched. }
function LeafSymRcxLoadable(node: Integer): Boolean;
var idx: Integer; tk: TTypeKind;
begin
  LeafSymRcxLoadable := False;
  if IRKind[node] <> IR_LOAD_SYM then Exit;
  idx := IRA[node];
  if Syms[idx].IsArray then Exit;
  tk := Syms[idx].TypeKind;
  if TypeIsFloat(tk) then Exit;
  if (tk = tyString) or (tk = tyAnsiString) then Exit;
  if TypeIsFrozenString(tk) then Exit;
  if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then Exit;
  case Syms[idx].Kind of
    skLocal, skParam, skGlobal: LeafSymRcxLoadable := True;
  end;
end;

{ -O3 W1 operand scheduler (x86-64): is this value subtree PROVEN safe to emit
  while a live value is parked in r8/r9 — and free of observable side effects
  (so it may also be emitted before, instead of after, a leaf left operand)?
  Whitelist of IR kinds whose x86-64 emission touches only rax/rcx/rdx/xmm0/
  xmm1 (+cl shifts), performs no call and no store. Everything not listed is
  UNSAFE by default, so a new IR op stays on the push/pop path until someone
  proves it here. Deliberate exclusions with reasons:
  - IR_BINOP op=tkIn: its emit code uses r8 as a scratch (bit-index mask).
  - string-typed BINOPs (operands or result): AnsiString concat/compare CALL
    runtime helpers (clobber all caller-saved); frozen tyString concat inlines
    a copy loop through rsi/rdi/rdx/r8/r10/r11.
  - IR_CALL / IR_CALL_IND / IR_VIRTUAL_CALL: calls clobber r8-r11 — and a call
    is the side effect the mirror reorder must never move across.
  - IR_DYNUNIQUE / anything InLValueWrite-sensitive that can call (COW clone):
    both transform sites additionally gate on `not InLValueWrite`, and the
    IR_INDEX read paths admitted here emit plain derefs only. }
function ScratchSafeSubtree(node: Integer): Boolean;
var op: TTokenKind; nt, lt, rt: TTypeKind;
begin
  ScratchSafeSubtree := False;
  if node < 0 then Exit;
  case IRKind[node] of
    IR_CONST_INT, IR_CONST_STR, IR_CONST_DATA,
    IR_LOAD_SYM, IR_LEA, IR_SLOTADDR, IR_DYNDATA:
      ScratchSafeSubtree := True;
    IR_NEG, IR_NOT, IR_FIELD, IR_LOAD_MEM:
      ScratchSafeSubtree := ScratchSafeSubtree(IRA[node]);
    IR_INDEX:
      ScratchSafeSubtree := ScratchSafeSubtree(IRA[node]) and
                            ScratchSafeSubtree(IRB[node]);
    IR_BINOP:
      begin
        op := IntToTokenKind(IRC[node]);
        if op = tkIn then Exit;
        nt := IntToTypeKind(IRTk[node]);
        lt := IntToTypeKind(IRTk[IRA[node]]);
        rt := IntToTypeKind(IRTk[IRB[node]]);
        if (nt = tyAnsiString) or TypeIsFrozenString(nt) or (nt = tyVariant) then Exit;
        if (lt = tyAnsiString) or TypeIsFrozenString(lt) or (lt = tyVariant) or (lt = tySet) then Exit;
        if (rt = tyAnsiString) or TypeIsFrozenString(rt) or (rt = tyVariant) or (rt = tySet) then Exit;
        ScratchSafeSubtree := ScratchSafeSubtree(IRA[node]) and
                              ScratchSafeSubtree(IRB[node]);
      end;
  end;
end;

procedure EmitLoadVarRcx(idx: Integer);
var tk: TTypeKind; sz: Integer; sgn: Boolean; rreg: Integer;
begin
  { Resident param direct-load into rcx: mov rcx, r14/r15. }
  rreg := ResidentRegOf(idx);
  if rreg <> 0 then
  begin
    EmitB($4C); EmitB($89); EmitB($C1 or ((rreg - 8) shl 3));         { mov rcx, r12..r15 }
    Exit;
  end;
  tk := Syms[idx].TypeKind;
  sz := TypeSize(tk);
  sgn := TypeSigned(tk);
  case Syms[idx].Kind of
    skLocal, skParam:
      begin
        if sz = 1 then
        begin
          if sgn then
            begin EmitB($48); EmitB($0F); EmitB($BE); EmitB($8D); EmitI32(Syms[idx].Offset); end
          else
            begin EmitB($48); EmitB($0F); EmitB($B6); EmitB($8D); EmitI32(Syms[idx].Offset); end;
        end
        else if sz = 2 then
        begin
          if sgn then
            begin EmitB($48); EmitB($0F); EmitB($BF); EmitB($8D); EmitI32(Syms[idx].Offset); end
          else
            begin EmitB($48); EmitB($0F); EmitB($B7); EmitB($8D); EmitI32(Syms[idx].Offset); end;
        end
        else if sz = 4 then
        begin
          if sgn then
            begin EmitB($48); EmitB($63); EmitB($8D); EmitI32(Syms[idx].Offset); end
          else
            begin EmitB($8B); EmitB($8D); EmitI32(Syms[idx].Offset); end;
        end
        else
          begin EmitB($48); EmitB($8B); EmitB($8D); EmitI32(Syms[idx].Offset); end;
      end;
    skGlobal:
      begin
        if sz = 1 then
        begin
          if sgn then
            begin EmitB($48); EmitB($0F); EmitB($BE); EmitB($0C); EmitB($25); EmitGlobRef(Syms[idx].Offset); end
          else
            begin EmitB($48); EmitB($0F); EmitB($B6); EmitB($0C); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
        end
        else if sz = 2 then
        begin
          if sgn then
            begin EmitB($48); EmitB($0F); EmitB($BF); EmitB($0C); EmitB($25); EmitGlobRef(Syms[idx].Offset); end
          else
            begin EmitB($48); EmitB($0F); EmitB($B7); EmitB($0C); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
        end
        else if sz = 4 then
        begin
          if sgn then
            begin EmitB($48); EmitB($63); EmitB($0C); EmitB($25); EmitGlobRef(Syms[idx].Offset); end
          else
            begin EmitB($8B); EmitB($0C); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
        end
        else
          begin EmitB($48); EmitB($8B); EmitB($0C); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
      end;
  end;
end;

{ Reload a resident param's frame slot into its r14/r15 cache with the canonical
  size/sign extension (by temporarily de-listing it so EmitLoadVar reads memory).
  Called after a store to keep the register byte-equal to a fresh load. }
procedure RegcallRefreshResident(idx: Integer);
var k, rreg, saved: Integer;
begin
  rreg := 0; saved := -1;
  for k := 0 to RcResidentCount - 1 do
    if RcResidentSym[k] = idx then begin rreg := RcResidentReg[k]; saved := k; Break; end;
  if rreg = 0 then Exit;
  RcResidentSym[saved] := -1;      { de-list: force a frame load }
  EmitLoadVar(idx);                { rax = re-extended value from the frame slot }
  RcResidentSym[saved] := idx;     { re-list }
  EmitB($49); EmitB($89); EmitB($C0 or (rreg - 8));                 { mov r12..r15, rax }
end;

{ Reload every float resident's register cache from its authoritative frame
  slot (dual-write keeps the frame current). Emitted on the IR_EXC_ENTER
  landing pad after the pool restore: a resident stored-to inside the try block
  has a newer frame value than the try-entry pool snapshot. No-op when
  FrResidentCount = 0 (-O0/-O2, non-x86-64), so those tiers stay byte-identical.
  Touches only xmm8..xmm13 — never rax/xmm0. }
procedure FloatResidencyRefreshAll;
var k: Integer;
begin
  for k := 0 to FrResidentCount - 1 do
  begin
    EmitB($F2); EmitB($44); EmitB($0F); EmitB($10);
    EmitB($85 or (k shl 3)); EmitI32(Syms[FrResidentSym[k]].Offset);  { movsd xmm(8+k), [rbp+off] }
  end;
end;

{ pxx internal ABI boundary (optimization-architecture.md §5b): save / restore
  the whole xmm8..13 callee-saved pool to this body's reserved frame slots.
  Needed wherever the callee-saved discipline can't hold: a SysV extern (all
  XMM volatile), an indirect call (target unprovable), a coroutine switch (the
  other context's code owns the registers meanwhile), and a try-entry (a raise
  longjmp skips the epilogues of every unwound frame, losing their save-iff-
  used restores). Saving the FULL pool — not just this body's residents —
  protects residents belonging to frames further up the call stack. rbp-
  relative movsd only: never touches rsp, rax, arg registers or xmm0..7, so it
  is safe between argument marshalling and the call, and between the call and
  its return-value bridging. No-op unless FxSaveOn (-O3 x86-64 non-asm bodies
  only), so -O0/-O2 stay byte-identical. }
procedure EnsurePendingInitCapacity(n: Integer);
{ Grow the PendingInit* tables to hold index n (see defs.inc — dynamic since
  quickjs; the old fixed cap silently dropped C global initializers). }
var cap: Integer;
begin
  cap := Length(PendingInitSym);
  if n < cap then Exit;
  if cap = 0 then cap := MAX_PENDING_INITS;
  while cap <= n do cap := cap * 2;
  SetLength(PendingInitSym, cap);
  SetLength(PendingInitElem, cap);
  SetLength(PendingInitVal, cap);
  SetLength(PendingInitValAux, cap);
  SetLength(PendingInitKind, cap);
  SetLength(PendingInitTk, cap);
  SetLength(PendingInitFOff, cap);
  SetLength(PendingInitFLen, cap);
end;

function PendingInitHasRoom(n: Integer): Boolean;
{ Boolean wrapper for use inside compound `if` conditions: grows, never full. }
begin
  EnsurePendingInitCapacity(n);
  Result := True;
end;

procedure FloatPoolSave;
var k: Integer;
begin
  if not FxSaveOn then Exit;
  for k := 0 to FR_RESIDENT_MAX - 1 do
  begin
    EmitB($F2); EmitB($44); EmitB($0F); EmitB($11);
    EmitB($85 or (k shl 3)); EmitI32(FxSaveBase + 8 * k);   { movsd [rbp+slot k], xmm(8+k) }
  end;
end;

procedure FloatPoolRestore;
var k: Integer;
begin
  if not FxSaveOn then Exit;
  for k := 0 to FR_RESIDENT_MAX - 1 do
  begin
    EmitB($F2); EmitB($44); EmitB($0F); EmitB($10);
    EmitB($85 or (k shl 3)); EmitI32(FxSaveBase + 8 * k);   { movsd xmm(8+k), [rbp+slot k] }
  end;
end;

procedure EmitStoreVar(idx: Integer);
var tk: TTypeKind; sz: Integer;
begin
  tk := Syms[idx].TypeKind;
  sz := TypeSize(tk);

  if TypeIsFloat(tk) then
  begin
    if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
    begin
      EmitB($48); EmitB($8B); EmitB($8D); EmitI32(Syms[idx].Offset);  { mov rcx, [rbp+off] }
      if tk = tySingle then
      begin
        EmitB($F2); EmitB($0F); EmitB($5A); EmitB($C0);                { cvtsd2ss xmm0, xmm0 }
        EmitB($F3); EmitB($0F); EmitB($11); EmitB($01);                { movss [rcx], xmm0 }
      end
      else if tk = tyExtended then
      begin
        EmitB($48); EmitB($83); EmitB($EC); EmitB($08);                { sub rsp, 8 }
        EmitB($F2); EmitB($0F); EmitB($11); EmitB($04); EmitB($24);   { movsd [rsp], xmm0 }
        EmitB($DD); EmitB($04); EmitB($24);                            { fldl [rsp] }
        EmitB($48); EmitB($83); EmitB($C4); EmitB($08);                { add rsp, 8 }
        EmitB($DB); EmitB($39);                                         { fstpt [rcx] }
      end
      else
        begin EmitB($F2); EmitB($0F); EmitB($11); EmitB($01); end;     { movsd [rcx], xmm0 }
    end
    else case Syms[idx].Kind of
      skLocal, skParam:
        if tk = tySingle then
        begin
          EmitB($F2); EmitB($0F); EmitB($5A); EmitB($C0);                           { cvtsd2ss xmm0, xmm0 }
          EmitB($F3); EmitB($0F); EmitB($11); EmitB($85); EmitI32(Syms[idx].Offset); { movss [rbp+off], xmm0 }
        end
        else if tk = tyExtended then
        begin
          EmitB($48); EmitB($83); EmitB($EC); EmitB($08);              { sub rsp, 8 }
          EmitB($F2); EmitB($0F); EmitB($11); EmitB($04); EmitB($24); { movsd [rsp], xmm0 }
          EmitB($DD); EmitB($04); EmitB($24);                          { fldl [rsp] }
          EmitB($48); EmitB($83); EmitB($C4); EmitB($08);              { add rsp, 8 }
          EmitB($DB); EmitB($BD); EmitI32(Syms[idx].Offset);           { fstpt [rbp+off] }
        end
        else
          begin EmitB($F2); EmitB($0F); EmitB($11); EmitB($85); EmitI32(Syms[idx].Offset); end; { movsd [rbp+off], xmm0 }
      skGlobal:
        if tk = tySingle then
        begin
          EmitB($F2); EmitB($0F); EmitB($5A); EmitB($C0);                                      { cvtsd2ss xmm0, xmm0 }
          EmitB($F3); EmitB($0F); EmitB($11); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); { movss [abs], xmm0 }
        end
        else if tk = tyExtended then
        begin
          EmitB($48); EmitB($83); EmitB($EC); EmitB($08);              { sub rsp, 8 }
          EmitB($F2); EmitB($0F); EmitB($11); EmitB($04); EmitB($24); { movsd [rsp], xmm0 }
          EmitB($DD); EmitB($04); EmitB($24);                          { fldl [rsp] }
          EmitB($48); EmitB($83); EmitB($C4); EmitB($08);              { add rsp, 8 }
          EmitB($DB); EmitB($3C); EmitB($25); EmitGlobRef(Syms[idx].Offset);  { fstpt [abs32] }
        end
        else
          begin EmitB($F2); EmitB($0F); EmitB($11); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end; { movsd [abs], xmm0 }
      skConst: Error('cannot assign to constant');
    end;
    { -O3 float loop residency dual-write: the frame slot was just written from
      xmm0; mirror the value into the resident xmm8/xmm9 cache. tyDouble only
      (no narrowing happened above), so register == a fresh frame load. }
    if FloatResidentXmmOf(idx) <> 0 then
    begin
      EmitB($44); EmitB($0F); EmitB($28);
      EmitB($C0 or ((FloatResidentXmmOf(idx) - 8) shl 3));  { movaps xmm8/xmm9, xmm0 }
    end;
    Exit;
  end;

  if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
  begin
    EmitB($48); EmitB($8B); EmitB($8D); EmitI32(Syms[idx].Offset);
    if sz = 1 then
      begin EmitB($88); EmitB($01); end
    else if sz = 2 then
      begin EmitB($66); EmitB($89); EmitB($01); end
    else if sz = 4 then
      begin EmitB($89); EmitB($01); end
    else
      begin EmitB($48); EmitB($89); EmitB($01); end;
  end
  else case Syms[idx].Kind of
    skLocal, skParam:
      begin
        if sz = 1 then
          begin EmitB($88); EmitB($85); EmitI32(Syms[idx].Offset); end
        else if sz = 2 then
          begin EmitB($66); EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset); end
        else if sz = 4 then
          begin EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset); end
        else
          begin EmitB($48); EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset); end;
      end;
    skGlobal:
      begin
        if sz = 1 then
          begin EmitB($88); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end
        else if sz = 2 then
          begin EmitB($66); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end
        else if sz = 4 then
          begin EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end
        else
          begin EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
      end;
    skConst: Error('cannot assign to constant');
  end;
  { Resident param dual-write (feature-callconv-register-args): the frame slot
    was just written above; refresh the r14/r15 cache so it stays byte-equal to a
    fresh load. Reload through EmitLoadVar (with this sym temporarily de-listed so
    it reads the frame, not the stale register) to reuse the exact size/sign
    extension every other load applies, then copy into the resident register. }
  if ResidentRegOf(idx) <> 0 then
    RegcallRefreshResident(idx);
end;

procedure EmitCmpRaxVar(idx: Integer);
{ cmp rax, var }
begin
  case Syms[idx].Kind of
    skLocal, skParam:
      begin EmitB($48); EmitB($3B); EmitB($85); EmitI32(Syms[idx].Offset); end;
    skGlobal:
      begin EmitB($48); EmitB($3B); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
    skConst:
      begin
        { cmp rax, imm32 }
        EmitB($48); EmitB($3D); EmitI32(Syms[idx].ConstVal);
      end;
  end;
end;

{ ===== String helpers ===== }

procedure EmitStoreStrLen(idx: Integer);
begin
  if (Syms[idx].Kind = skParam) and (Syms[idx].TypeKind = tyString) then
  begin
    { param slot holds pointer P; store rax (length) into [P] }
    EmitB($48); EmitB($8B); EmitB($8D); EmitI32(Syms[idx].Offset); { mov rcx, [rbp+off] = P }
    EmitB($48); EmitB($89); EmitB($01);                              { mov [P], rax }
  end
  else
  begin
    case Syms[idx].Kind of
      skLocal, skParam:
        begin EmitB($48); EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset); end;
      skGlobal:
        begin EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
    end;
  end;
end;

procedure EmitLoadStrLen(idx: Integer);
{ Load length of string variable into rcx }
begin
  if (Syms[idx].Kind = skParam) and (Syms[idx].TypeKind = tyString) then
  begin
    EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[idx].Offset); { mov rax, [rbp+off] = P }
    EmitB($48); EmitB($8B); EmitB($08);                              { mov rcx, [rax] }
  end
  else
  begin
    case Syms[idx].Kind of
      skLocal, skParam:
        begin EmitB($48); EmitB($8B); EmitB($8D); EmitI32(Syms[idx].Offset); end; { mov rcx, [rbp+off] }
      skGlobal:
        begin EmitB($48); EmitB($8B); EmitB($0C); EmitB($25); EmitGlobRef(Syms[idx].Offset); end; { mov rcx, [abs] }
    end;
  end;
end;

procedure EmitLeaStrDataRdi(idx: Integer);
begin
  if (Syms[idx].Kind = skParam) and (Syms[idx].TypeKind = tyString) then
  begin
    { param slot holds pointer P; data at P+8 }
    EmitB($48); EmitB($8B); EmitB($BD); EmitI32(Syms[idx].Offset); { mov rdi, [rbp+off] = P }
    EmitB($48); EmitB($83); EmitB($C7); EmitB($08);                  { add rdi, 8 → P+8 }
  end
  else
  begin
    case Syms[idx].Kind of
      skLocal, skParam:
        begin EmitB($48); EmitB($8D); EmitB($BD); EmitI32(Syms[idx].Offset + 8); end;
      skGlobal:
        begin EmitB($48); EmitB($8D); EmitB($3C); EmitB($25); EmitGlobRef(Syms[idx].Offset + 8); end;
    end;
  end;
end;

procedure EmitLeaStrDataRsi(idx: Integer);
begin
  if (Syms[idx].Kind = skParam) and (Syms[idx].TypeKind = tyString) then
  begin
    { param slot holds pointer P; data at P+8 }
    EmitB($48); EmitB($8B); EmitB($B5); EmitI32(Syms[idx].Offset); { mov rsi, [rbp+off] = P }
    EmitB($48); EmitB($83); EmitB($C6); EmitB($08);                  { add rsi, 8 → P+8 }
  end
  else
  begin
    case Syms[idx].Kind of
      skLocal, skParam:
        begin EmitB($48); EmitB($8D); EmitB($B5); EmitI32(Syms[idx].Offset + 8); end;
      skGlobal:
        begin EmitB($48); EmitB($8D); EmitB($34); EmitB($25); EmitGlobRef(Syms[idx].Offset + 8); end;
    end;
  end;
end;

procedure EmitwriteStrVar(idx: Integer);
{ sys_write the string variable at Syms[idx] }
begin
  if (Syms[idx].Kind = skParam) and TypeIsFrozenString(Syms[idx].TypeKind) then
  begin
    { param slot holds pointer P; length at [P], data at P+8. ALL frozen
      string kinds — the `= tyString` key missed tyFixedString/tyShortString
      params, which then read the slot as an inline string and dumped wild
      memory (bug-pascal-writeln-shortstring-param). }
    EmitB($48); EmitB($8B); EmitB($B5); EmitI32(Syms[idx].Offset); { mov rsi, [rbp+off] = P }
    EmitB($48); EmitB($8B); EmitB($16);                              { mov rdx, [P] = length }
    EmitB($48); EmitB($83); EmitB($C6); EmitB($08);                  { add rsi, 8 → P+8 }
  end
  else
  begin
    case Syms[idx].Kind of
      skLocal, skParam:
        begin EmitB($48); EmitB($8B); EmitB($95); EmitI32(Syms[idx].Offset); end;
      skGlobal:
        begin EmitB($48); EmitB($8B); EmitB($14); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
    end;
    EmitLeaStrDataRsi(idx);
  end;
  MovRaxImm(SYS_WRITE); MovRdiImm(CurWriteFd); EmitSyscall;
end;

procedure EmitStrAssignLiteral(dstIdx, litOff, litLen: Integer);
{ s := 'literal': store length, rep movsb the literal bytes }
begin
  { Store length into [bss+Offset] }
  MovRaxImm(litLen);
  EmitStoreStrLen(dstIdx);
  if litLen > 0 then
  begin
    { mov rcx, litLen }
    EmitB($48); EmitB($B9); EmitI64(litLen);
    { lea rdi, [bss+Offset+8] }
    EmitLeaStrDataRdi(dstIdx);
    { mov rsi, data_addr (literal bytes in data section) }
    EmitB($48); EmitB($BE); EmitDataRef(litOff + 8);
    { rep movsb }
    EmitB($F3); EmitB($A4);
  end;
end;

procedure EmitStrAssignVar(dstIdx, srcIdx: Integer);
{ s := t: copy length then rep movsb the data }
begin
  { rax = src length }
  EmitLoadVar(srcIdx);
  { store length to dst }
  EmitStoreStrLen(dstIdx);
  { rcx = length (for rep) }
  EmitB($48); EmitB($89); EmitB($C1);   { mov rcx, rax }
  { lea rdi, [bss+dst.Offset+8] }
  EmitLeaStrDataRdi(dstIdx);
  { lea rsi, [bss+src.Offset+8] }
  EmitLeaStrDataRsi(srcIdx);
  { rep movsb }
  EmitB($F3); EmitB($A4);
end;

procedure EmitArgvToString(dstIdx: Integer);
var inRangePatch, doneOutPatch: Integer;
begin
  { On entry: rax = argv index. Copy argv[rax] C-string to global string dstIdx. }
  { Bounds check: an out-of-range index (>= argc, or negative) yields '' rather
    than dereferencing a NULL/out-of-bounds argv slot (which segfaulted). argc is
    at [initial_rsp]. }
  EmitB($48); EmitB($8B); EmitB($0C); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);  { mov rcx, [initial_rsp] }
  EmitB($48); EmitB($8B); EmitB($09);               { mov rcx, [rcx] = argc }
  EmitB($48); EmitB($39); EmitB($C8);               { cmp rax, rcx }
  EmitB($72); inRangePatch := CodeLen; EmitB(0);    { jb in_range (unsigned: 0<=index<argc) }
  EmitB($48); EmitB($31); EmitB($C0);               { xor rax, rax }
  EmitStoreStrLen(dstIdx);                           { dst := '' }
  EmitB($EB); doneOutPatch := CodeLen; EmitB(0);    { jmp done }
  Code[inRangePatch] := Byte(CodeLen - (inRangePatch + 1));
  EmitB($48); EmitB($C1); EmitB($E0); EmitB($03);   { shl rax, 3 }
  EmitB($48); EmitB($8B); EmitB($0C); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
  EmitB($48); EmitB($83); EmitB($C1); EmitB($08);   { add rcx, 8 }
  EmitB($48); EmitB($01); EmitB($C8);               { add rax, rcx }
  EmitB($48); EmitB($8B); EmitB($00);               { mov rax, [rax] }
  EmitB($48); EmitB($89); EmitB($C6);               { mov rsi, rax }
  EmitB($48); EmitB($31); EmitB($C9);               { xor rcx, rcx }
  EmitB($80); EmitB($3C); EmitB($0E); EmitB($00);   { cmp byte [rsi+rcx], 0 }
  EmitB($74); EmitB($05);                           { je +5 }
  EmitB($48); EmitB($FF); EmitB($C1);               { inc rcx }
  EmitB($EB); EmitB($F5);                           { jmp -11 }
  EmitB($48); EmitB($89); EmitB($C8);               { mov rax, rcx }
  EmitStoreStrLen(dstIdx);
  EmitLeaStrDataRdi(dstIdx);
  EmitB($F3); EmitB($A4);
  Code[doneOutPatch] := Byte(CodeLen - (doneOutPatch + 1));
end;

procedure EmitTerminateString(idx: Integer);
begin
  { Linux path syscalls need a trailing NUL beyond the Pascal length. }
  EmitLoadVar(idx);
  EmitLeaStrDataRdi(idx);
  EmitB($C6); EmitB($04); EmitB($07); EmitB($00); { mov byte [rdi+rax], 0 }
end;

procedure EmitLoadFile(pathIdx, dstIdx: Integer);
begin
  { open(path, O_RDONLY) }
  EmitTerminateString(pathIdx);
  EmitLeaStrDataRdi(pathIdx);
  MovRsiImm(0);
  MovRdxImm(0);
  MovRaxImm(SYS_OPEN);
  EmitSyscall;
  EmitB($50);                                      { save fd }

  { read(fd, dst.data, STRING_CAP) }
  EmitB($48); EmitB($89); EmitB($C7);              { mov rdi, rax }
  EmitLeaStrDataRsi(dstIdx);
  MovRdxImm(STRING_CAP);
  MovRaxImm(SYS_READ);
  EmitSyscall;

  { If rax is negative (error), clamp it to 0 }
  EmitB($48); EmitB($85); EmitB($C0);              { test rax, rax }
  EmitB($79); EmitB($0A);                          { jns skip }
  MovRaxImm(0);                                    { mov rax, 0 }
  { skip }

  EmitStoreStrLen(dstIdx);

  { close(fd) }
  EmitB($5F);                                      { pop rdi }
  MovRaxImm(SYS_CLOSE);
  EmitSyscall;
end;

procedure EmitStrCmp(aIdx, bIdx: Integer; eq: Boolean);
{ rax = 1 if (a=b), 0 otherwise.  eq=False → rax = 1 if (a<>b). }
var skipJmp, okJmp: Integer;
begin
  { Compare lengths first }
  EmitLoadVar(aIdx);
  EmitB($48); EmitB($3B); EmitB($04); EmitB($25); EmitGlobRef(Syms[bIdx].Offset);
  { jne → not equal }
  EmitB($0F); EmitB($85); skipJmp := CodeLen; EmitI32(0);
  { Lengths equal — compare bytes; rcx = length }
  EmitLoadVar(aIdx);
  EmitB($48); EmitB($89); EmitB($C1);
  { lea rdi, [a_data] }
  EmitB($48); EmitB($8D); EmitB($3C); EmitB($25); EmitGlobRef(Syms[aIdx].Offset + 8);
  { lea rsi, [b_data] }
  EmitB($48); EmitB($8D); EmitB($34); EmitB($25); EmitGlobRef(Syms[bIdx].Offset + 8);
  { repe cmpsb }
  EmitB($F3); EmitB($A6);
  { je → bytes equal }
  EmitB($0F); EmitB($84); okJmp := CodeLen; EmitI32(0);
  { Not equal }
  Patch32(skipJmp, CodeLen - (skipJmp + 4));
  if eq then MovRaxImm(0) else MovRaxImm(1);
  EmitB($E9); skipJmp := CodeLen; EmitI32(0);
  Patch32(okJmp, CodeLen - (okJmp + 4));
  if eq then MovRaxImm(1) else MovRaxImm(0);
  Patch32(skipJmp, CodeLen - (skipJmp + 4));
end;

procedure EmitStrCmpReg(eq: Boolean);
var skipJmp, okJmp: Integer;
begin
  { mov rsi, rcx }
  EmitB($48); EmitB($89); EmitB($CE);
  { add rsi, 8 }
  EmitB($48); EmitB($83); EmitB($C6); EmitB($08);
  { mov rdi, rax }
  EmitB($48); EmitB($89); EmitB($C7);
  { add rdi, 8 }
  EmitB($48); EmitB($83); EmitB($C7); EmitB($08);
  { mov rcx, [rcx] }
  EmitB($48); EmitB($8B); EmitB($09);
  { cmp rcx, [rax] }
  EmitB($48); EmitB($3B); EmitB($08);

  { jne not_equal }
  EmitB($0F); EmitB($85); skipJmp := CodeLen; EmitI32(0);

  { repe cmpsb }
  EmitB($F3); EmitB($A6);

  { je equal }
  EmitB($0F); EmitB($84); okJmp := CodeLen; EmitI32(0);

  { not_equal: }
  Patch32(skipJmp, CodeLen - (skipJmp + 4));
  if eq then MovRaxImm(0) else MovRaxImm(1);
  EmitB($E9); skipJmp := CodeLen; EmitI32(0);

  { equal: }
  Patch32(okJmp, CodeLen - (okJmp + 4));
  if eq then MovRaxImm(1) else MovRaxImm(0);

  { end: }
  Patch32(skipJmp, CodeLen - (skipJmp + 4));
end;

procedure EmitAnsiStrCmpReg(eq: Boolean; lhsTk, rhsTk: TTypeKind);
var pLhsNil, pLhsDone, pRhsNil, pRhsDone, skipJmp, okJmp, okJmp2: Integer;
begin
  { --- Load LHS (rax) -> rsi (chars), rdx (len) --- }
  if lhsTk = tyAnsiString then
  begin
    { test rax, rax }
    EmitB($48); EmitB($85); EmitB($C0);
    { jz lhs_nil }
    EmitB($74); pLhsNil := CodeLen; EmitB(0);
    
    EmitB($48); EmitB($89); EmitB($C6);             { mov rsi, rax }
    EmitB($48); EmitB($8B); EmitB($50); EmitB($F8); { mov rdx, [rax-8] }
    { jmp lhs_done }
    EmitB($EB); pLhsDone := CodeLen; EmitB(0);
    
    { lhs_nil: }
    Code[pLhsNil] := Byte(CodeLen - (pLhsNil + 1));
    EmitB($31); EmitB($F6);                         { xor esi, esi }
    EmitB($31); EmitB($D2);                         { xor edx, edx }
    
    { lhs_done: }
    Code[pLhsDone] := Byte(CodeLen - (pLhsDone + 1));
  end
  else
  begin
    EmitB($48); EmitB($8D); EmitB($70); EmitB($08); { lea rsi, [rax+8] }
    EmitB($48); EmitB($8B); EmitB($10);             { mov rdx, [rax] }
  end;

  { --- Load RHS (rcx) -> rdi (chars), r8 (len) --- }
  if rhsTk = tyAnsiString then
  begin
    { test rcx, rcx }
    EmitB($48); EmitB($85); EmitB($C9);
    { jz rhs_nil }
    EmitB($74); pRhsNil := CodeLen; EmitB(0);
    
    EmitB($48); EmitB($89); EmitB($CF);             { mov rdi, rcx }
    EmitB($4C); EmitB($8B); EmitB($41); EmitB($F8); { mov r8, [rcx-8] }
    { jmp rhs_done }
    EmitB($EB); pRhsDone := CodeLen; EmitB(0);
    
    { rhs_nil: }
    Code[pRhsNil] := Byte(CodeLen - (pRhsNil + 1));
    EmitB($31); EmitB($FF);                         { xor edi, edi }
    EmitB($45); EmitB($31); EmitB($C0);             { xor r8d, r8d }
    
    { rhs_done: }
    Code[pRhsDone] := Byte(CodeLen - (pRhsDone + 1));
  end
  else
  begin
    EmitB($48); EmitB($8D); EmitB($79); EmitB($08); { lea rdi, [rcx+8] }
    EmitB($4C); EmitB($8B); EmitB($01);             { mov r8, [rcx] }
  end;

  { --- Comparison --- }
  { cmp rdx, r8 }
  EmitB($4C); EmitB($39); EmitB($C2);
  { jne not_equal }
  EmitB($0F); EmitB($85); skipJmp := CodeLen; EmitI32(0);

  { Lengths are equal. If length is 0, they are equal! }
  { test rdx, rdx }
  EmitB($48); EmitB($85); EmitB($D2);
  { jz equal }
  EmitB($0F); EmitB($84); okJmp := CodeLen; EmitI32(0);

  { Compare contents:
    rcx = rdx (length for repe) }
  EmitB($48); EmitB($89); EmitB($D1);             { mov rcx, rdx }
  EmitB($F3); EmitB($A6);                          { repe cmpsb }
  { je equal }
  EmitB($0F); EmitB($84); okJmp2 := CodeLen; EmitI32(0);

  { not_equal: }
  Patch32(skipJmp, CodeLen - (skipJmp + 4));
  if eq then MovRaxImm(0) else MovRaxImm(1);
  { jmp end }
  EmitB($E9); skipJmp := CodeLen; EmitI32(0);

  { equal: }
  Patch32(okJmp, CodeLen - (okJmp + 4));
  Patch32(okJmp2, CodeLen - (okJmp2 + 4));
  if eq then MovRaxImm(1) else MovRaxImm(0);

  { end: }
  Patch32(skipJmp, CodeLen - (skipJmp + 4));
end;

procedure EmitAnsiStrCmp3Reg(op: TTokenKind; lhsTk, rhsTk: TTypeKind);
{ Lexicographic ordering for managed strings (tyAnsiString / tyString).
  rax = LHS handle, rcx = RHS handle.  Sets rax := 0/1 per op (< <= > >=).
  Mirrors EmitAnsiStrCmpReg's loading prologue, then a min-length repe cmpsb
  with a length tie-break, then an unsigned setcc. }
var pLhsNil, pLhsDone, pRhsNil, pRhsDone, pMinOk, pLenCmp, pSetcc: Integer;
begin
  { --- Load LHS (rax) -> rsi (chars), rdx (len) --- }
  if lhsTk = tyAnsiString then
  begin
    EmitB($48); EmitB($85); EmitB($C0);             { test rax, rax }
    EmitB($74); pLhsNil := CodeLen; EmitB(0);       { jz lhs_nil }
    EmitB($48); EmitB($89); EmitB($C6);             { mov rsi, rax }
    EmitB($48); EmitB($8B); EmitB($50); EmitB($F8); { mov rdx, [rax-8] }
    EmitB($EB); pLhsDone := CodeLen; EmitB(0);      { jmp lhs_done }
    Code[pLhsNil] := Byte(CodeLen - (pLhsNil + 1));
    EmitB($31); EmitB($F6);                         { xor esi, esi }
    EmitB($31); EmitB($D2);                         { xor edx, edx }
    Code[pLhsDone] := Byte(CodeLen - (pLhsDone + 1));
  end
  else
  begin
    EmitB($48); EmitB($8D); EmitB($70); EmitB($08); { lea rsi, [rax+8] }
    EmitB($48); EmitB($8B); EmitB($10);             { mov rdx, [rax] }
  end;

  { --- Load RHS (rcx) -> rdi (chars), r8 (len) --- }
  if rhsTk = tyAnsiString then
  begin
    EmitB($48); EmitB($85); EmitB($C9);             { test rcx, rcx }
    EmitB($74); pRhsNil := CodeLen; EmitB(0);       { jz rhs_nil }
    EmitB($48); EmitB($89); EmitB($CF);             { mov rdi, rcx }
    EmitB($4C); EmitB($8B); EmitB($41); EmitB($F8); { mov r8, [rcx-8] }
    EmitB($EB); pRhsDone := CodeLen; EmitB(0);      { jmp rhs_done }
    Code[pRhsNil] := Byte(CodeLen - (pRhsNil + 1));
    EmitB($31); EmitB($FF);                         { xor edi, edi }
    EmitB($45); EmitB($31); EmitB($C0);             { xor r8d, r8d }
    Code[pRhsDone] := Byte(CodeLen - (pRhsDone + 1));
  end
  else
  begin
    EmitB($48); EmitB($8D); EmitB($79); EmitB($08); { lea rdi, [rcx+8] }
    EmitB($4C); EmitB($8B); EmitB($01);             { mov r8, [rcx] }
  end;

  { --- minlen in rcx --- }
  EmitB($48); EmitB($89); EmitB($D1);               { mov rcx, rdx }
  EmitB($4C); EmitB($39); EmitB($C1);               { cmp rcx, r8 }
  EmitB($76); pMinOk := CodeLen; EmitB(0);          { jbe min_ok }
  EmitB($4C); EmitB($89); EmitB($C1);               { mov rcx, r8 }
  Code[pMinOk] := Byte(CodeLen - (pMinOk + 1));     { min_ok: }
  EmitB($48); EmitB($85); EmitB($C9);               { test rcx, rcx }
  EmitB($74); pLenCmp := CodeLen; EmitB(0);         { jz len_cmp }
  EmitB($F3); EmitB($A6);                           { repe cmpsb }
  EmitB($75); pSetcc := CodeLen; EmitB(0);          { jne set_cc (flags = lhs-rhs) }
  Code[pLenCmp] := Byte(CodeLen - (pLenCmp + 1));   { len_cmp: }
  EmitB($4C); EmitB($39); EmitB($C2);               { cmp rdx, r8 }
  Code[pSetcc] := Byte(CodeLen - (pSetcc + 1));     { set_cc: }
  case op of
    tkLt: begin EmitB($0F); EmitB($92); EmitB($C0); end;  { setb }
    tkLe: begin EmitB($0F); EmitB($96); EmitB($C0); end;  { setbe }
    tkGt: begin EmitB($0F); EmitB($97); EmitB($C0); end;  { seta }
    tkGe: begin EmitB($0F); EmitB($93); EmitB($C0); end;  { setae }
  end;
  EmitB($48); EmitB($0F); EmitB($B6); EmitB($C0);   { movzx rax, al }
end;

{ ===== Array element access ===== }

procedure EmitBumpAlloc;
{ On entry: rax = byte count requested. On exit: rax = allocated block base.
  Rounds size up to 8, bumps BSS_HEAP_PTR, grows the break via brk if needed.
  Shared by GetMem/class-new and dynamic-array SetLength (both
  backends), so it lives here in symtab.inc ahead of every caller. }
var jbePatch: Integer;
begin
  { Round size up to multiple of 8 for alignment }
  EmitB($48); EmitB($83); EmitB($C0); EmitB($07); { add rax, 7 }
  EmitB($48); EmitB($83); EmitB($E0); EmitB($F8); { and rax, -8 }
  { mov rbx, [BSS_HEAP_PTR] }
  EmitB($48); EmitB($8B); EmitB($1C); EmitB($25); EmitGlobRef(BSS_HEAP_PTR);
  { add rbx, rax }
  EmitB($48); EmitB($01); EmitB($C3);
  { cmp rbx, [BSS_HEAP_END] }
  EmitB($48); EmitB($3B); EmitB($1C); EmitB($25); EmitGlobRef(BSS_HEAP_END);
  { jbe skip_brk }
  EmitB($76); jbePatch := CodeLen; EmitB(0);
  { push rbx }
  EmitB($53);
  { mov rdi, rbx }
  EmitB($48); EmitB($89); EmitB($DF);
  { mov rax, SYS_BRK }
  MovRaxImm(SYS_BRK);
  { syscall }
  EmitSyscall;
  { pop rbx }
  EmitB($5B);
  { mov [BSS_HEAP_END], rax }
  EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_HEAP_END);
  { Patch short jump offset }
  Code[jbePatch] := Byte(CodeLen - (jbePatch + 1));
  { mov rax, [BSS_HEAP_PTR] }
  EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_HEAP_PTR);
  { mov [BSS_HEAP_PTR], rbx }
  EmitB($48); EmitB($89); EmitB($1C); EmitB($25); EmitGlobRef(BSS_HEAP_PTR);
end;

procedure EmitArrElemAddr(arrIdx: Integer);
{ On entry: rax = array index. On exit: rax = element address. }
var elemSize: Integer;
begin
  { feature-a-typeref-migrate-consumers lane 1: ElemType/ElemRecName read via
    SymTR[arrIdx].ElemTk/ElemRec (kept in sync by SymSyncTypeRef). }
  if SymTR[arrIdx].ElemTk = Ord(tyString) then
  begin
    if Syms[arrIdx].Kind = skGlobal then elemSize := STRING_CAP + 8
    else elemSize := LOCAL_STR_CAP + 8;
  end
  else if SymTR[arrIdx].ElemTk = Ord(tyRecord) then elemSize := RecSize(SymTR[arrIdx].ElemRec)
  else elemSize := TypeSize(IntToTypeKind(SymTR[arrIdx].ElemTk));

  if elemSize = 8 then
  begin
    { shl rax, 3  (multiply by 8) }
    EmitB($48); EmitB($C1); EmitB($E0); EmitB($03);
  end
  else if elemSize > 1 then
  begin
    { mov rcx, elemSize }
    EmitB($48); EmitB($C7); EmitB($C1); EmitI32(elemSize);
    { imul rax, rcx }
    EmitB($48); EmitB($0F); EmitB($AF); EmitB($C1);
  end;

  { Subtract lower bound * elemSize (if non-zero) }
  if Syms[arrIdx].ConstVal <> 0 then
  begin
    EmitB($48); EmitB($2D); EmitI32(Syms[arrIdx].ConstVal * elemSize);
  end;

  if Syms[arrIdx].Kind = skGlobal then
  begin
    { add eax, bss_arr_base  (32-bit add, zero-extends to rax) }
    EmitB($05); EmitGlobRef(Syms[arrIdx].Offset);
  end
  else
  begin
    EmitB($48); EmitB($01); EmitB($E8);       { add rax, rbp }
    EmitB($48); EmitB($05); EmitI32(Syms[arrIdx].Offset);
  end;
end;

procedure EmitArrLoad(arrIdx: Integer);
{ rax = index → rax = element value }
var sz: Integer; sgn: Boolean;
begin
  EmitArrElemAddr(arrIdx);
  sz := TypeSize(IntToTypeKind(SymTR[arrIdx].ElemTk));
  sgn := TypeSigned(IntToTypeKind(SymTR[arrIdx].ElemTk));
  if sz = 1 then
  begin
    if sgn then
      begin EmitB($48); EmitB($0F); EmitB($BE); EmitB($00); end { movsx rax, byte [rax] }
    else
      begin EmitB($48); EmitB($0F); EmitB($B6); EmitB($00); end;{ movzx rax, byte [rax] }
  end
  else if sz = 2 then
  begin
    if sgn then
      begin EmitB($48); EmitB($0F); EmitB($BF); EmitB($00); end { movsx rax, word [rax] }
    else
      begin EmitB($48); EmitB($0F); EmitB($B7); EmitB($00); end;{ movzx rax, word [rax] }
  end
  else if sz = 4 then
  begin
    if sgn then
      begin EmitB($48); EmitB($63); EmitB($00); end { movsxd rax, dword [rax] }
    else
      begin EmitB($8B); EmitB($00); end;{ mov eax, dword [rax] }
  end
  else
    begin EmitB($48); EmitB($8B); EmitB($00); end; { mov rax, [rax] }
end;

procedure EmitStringCharLoad(strIdx: Integer);
begin
  { On entry: rax = Pascal string index (1-based). On exit: rax = byte value. }
  EmitB($48); EmitB($FF); EmitB($C8);                 { dec rax }
  EmitB($48); EmitB($05); EmitGlobRef(Syms[strIdx].Offset + 8);
  EmitB($48); EmitB($0F); EmitB($B6); EmitB($00);     { movzx rax, byte [rax] }
end;

procedure EmitArrStore(arrIdx: Integer);
{ Stack: [..., addr]. rax = value. Store value at addr. }
var sz: Integer;
begin
  { addr was pushed before RHS eval }
  EmitB($59);                   { pop rcx -- element address }
  sz := TypeSize(IntToTypeKind(SymTR[arrIdx].ElemTk));
  if sz = 1 then
    begin EmitB($88); EmitB($01); end
  else if sz = 2 then
    begin EmitB($66); EmitB($89); EmitB($01); end
  else if sz = 4 then
    begin EmitB($89); EmitB($01); end
  else
    begin EmitB($48); EmitB($89); EmitB($01); end;
end;

{ ===== Operator overload table ===== }

procedure RegisterOpOverload(opKind, typeKind, recId, procIdx: Integer);
begin
  if OvrlCount >= MAX_OP_OVERLOADS then Error('too many operator overloads');
  OvrlOpKind[OvrlCount]   := opKind;
  OvrlTypeKind[OvrlCount] := typeKind;
  OvrlRecId[OvrlCount]    := recId;
  OvrlProcIdx[OvrlCount]  := procIdx;
  Inc(OvrlCount);
end;

function FindOpOverload(opKind, typeKind, recId: Integer): Integer;
var i: Integer;
begin
  Result := -1;
  i := 0;
  while i < OvrlCount do
  begin
    if (OvrlOpKind[i] = opKind) and (OvrlTypeKind[i] = typeKind) and (OvrlRecId[i] = recId) then
    begin
      Result := OvrlProcIdx[i];
      Exit;
    end;
    Inc(i);
  end;
end;

{ Binary-operator lookup that also considers the RIGHT operand.

  The table is keyed on the LEFT operand only, so two overloads of one operator
  sharing a left type collide and the first registered always wins: with both
  `TVec + TVec` and `TVec + Integer` declared, `a + 5` called the record/record
  one and silently produced its answer. Unreachable until the mixed-type
  SIGNATURE started parsing, which is why it had never been seen.

  Rather than widen the table, disambiguate here: the entry names a proc whose
  Params already carry the real operand types. Prefer an entry whose SECOND
  parameter matches the right operand exactly; fall back to the first entry with
  the right (opKind, leftKind, leftRec), which is exactly the old behaviour and
  keeps every single-overload program compiling as before.
  bug-a-a-mixed-type-record-operator-signature-fails-to-parse }
function FindOpOverload2(opKind, typeKind, recId, rightTk, rightRec: Integer): Integer;
var i, pi, firstHit: Integer;
begin
  Result := -1;
  firstHit := -1;
  i := 0;
  while i < OvrlCount do
  begin
    if (OvrlOpKind[i] = opKind) and (OvrlTypeKind[i] = typeKind) and (OvrlRecId[i] = recId) then
    begin
      pi := OvrlProcIdx[i];
      if firstHit < 0 then firstHit := pi;
      { TParam carries no RecName — the record id lives on the param's SYMBOL. }
      if (Procs[pi].ParamCount = 2) and
         (Ord(Procs[pi].Params[1].TypeKind) = rightTk) and
         (((rightTk <> Ord(tyRecord)) and (rightTk <> Ord(tyClass))) or
          ((Procs[pi].Params[1].SymIdx >= 0) and
           (Procs[pi].Params[1].SymIdx < SymCount) and
           (Syms[Procs[pi].Params[1].SymIdx].RecName = rightRec))) then
      begin
        Result := pi;
        Exit;
      end;
    end;
    Inc(i);
  end;
  Result := firstHit;
end;

{ ===== Procedure table ===== }

{ FNV-1a over the case-folded name. $811C9DC5 / $01000193 are the published
  32-bit FNV offset-basis and prime (avalanche constants, NOT integer limits);
  the LongWord multiply wraps mod 2^32 by design. Result masked to the
  power-of-two bucket count. }
function NameFoldHash(const s: AnsiString): Integer;
var i, b: Integer; h: LongWord;
begin
  h := LongWord($811C9DC5);
  for i := 1 to Length(s) do
  begin
    b := Ord(s[i]);
    if (b >= 65) and (b <= 90) then b := b + 32;   { fold A..Z }
    h := (h xor LongWord(b)) * LongWord($01000193);
  end;
  Result := Integer(h and LongWord(PROC_HASH_SIZE - 1));
end;

procedure ProcHashReset;
var i: Integer;
begin
  for i := 0 to PROC_HASH_SIZE - 1 do
  begin
    ProcHashHead[i] := -1;
    ProcHashTail[i] := -1;
  end;
end;

{ Append idx to its bucket's FIFO chain. Called once per RegisterProc; proc
  names are immutable after registration, so the index never goes stale. }
procedure ProcHashInsert(idx: Integer);
var b: Integer;
begin
  b := NameFoldHash(Procs[idx].Name);
  ProcHashNext[idx] := -1;
  if ProcHashHead[b] < 0 then
    ProcHashHead[b] := idx
  else
    ProcHashNext[ProcHashTail[b]] := idx;
  ProcHashTail[b] := idx;
end;

{ First candidate (registration order) for a name; walk via ProcHashNext.
  The chain holds every proc with the same FOLDED name (plus rare unrelated
  collisions) — callers still do their own exact/CaseEqual compare. }
function ProcChainHead(const name: AnsiString): Integer;
begin
  Result := ProcHashHead[NameFoldHash(name)];
end;

{ NAME ONLY — this returns ONE proc index and never consults overloads.

  That is not a gap to be fixed here, it is the contract: FindProc is what
  hand-built call sites use when they know exactly which routine they want.
  But it has a sharp edge worth stating at the declaration, because it cost
  three separate rediscoveries in one night
  (bug-nilpy-stdlib-shim-table-cannot-reach-an-overload): **adding a Pascal
  `overload` for a case a hand-built call gets wrong has NO EFFECT** — the new
  overload is never selected, the build is clean, the self-host is green, and
  nothing changes. The natural next conclusion is that the runtime is wrong
  rather than that the call was never routed there.

  When a hand-built call site needs to pick among arities, use FindProcArity
  below. When it needs to pick by TYPE, give the routine a unique name or
  convert at the call site — full overload resolution lives in MatchProcCall
  and is not reachable from a name lookup. }
{ Forwards: the FPC seed build compiles compiler.pas's includes in order and
  requires a declaration before use, unlike pxx itself. ProcScopeRank and
  MatchEligBase are both defined further down, beside MatchElig.
  See bug-a-fpc-seed-drift-emitasmx64-forward — the seed canary is what caught
  this, `make compiler/pascal26` was already converging. }
function ProcScopeRank(idx, bIdx: Integer): Integer; forward;
function MatchEligBase(idx: Integer; const name: AnsiString; demote: Boolean;
                  bIdx: Integer; userOnly, dropLateDef: Boolean): Boolean; forward;
function FindProcBound(const name: AnsiString): Integer; forward;

{ FindProc, but only an EXACT-CASE match counts. Pascal's lookup is
  case-INSENSITIVE and NilPy's names are not, so a Python name resolved against
  a builtin that differs only in case: `counter` found pylib's `Counter`, and
  every bare read of a module global by that name became a function VALUE
  (a code address printed as 4727019). The distinction it destroys is exactly
  the one Python programmers use most — `Counter` the type beside `counter` the
  tally.

  Written on top of FindProc rather than beside it: FindProc's EXACT pass runs
  first and its case-insensitive fallback only after, so a result whose stored
  name differs in case can only have come from the fallback. One line, and it
  cannot drift from the visibility/forward/unit rules the real lookup applies.
  bug-nilpy-a-global-collides-case-insensitively-with-a-builtin-proc }
function FindProcExactCase(const name: AnsiString): Integer; forward;
function FindProcNilPyBound(const name: AnsiString): Integer; forward;

function FindProc(const name: AnsiString): Integer;
var i, own, last: Integer; lo: AnsiString;
begin
  lo := name;
  own := -1; last := -1;
  { Exact-case match first — always, and the only path for case-sensitive
    symbols (C imports, or Pascal in case-sensitive mode). Hash-chain walk
    (FIFO = registration order) replaces the full linear scan; same result. }
  i := ProcChainHead(lo);
  while i >= 0 do
  begin
    { require-forward: a main-program routine whose header sits below the body
      being compiled is invisible, like the DeclOrderStrict global-var gate.
      ProcHdrTok = 0 (builtins/units/interface/methods/nested) always passes. }
    if (Procs[i].Name = lo) and
       not (RequireForward and (ProcHdrTok[i] > CurBodyHdrTok)) and
       DeclVisibleBareRoutine(ProcUnitIdx[i], name) then
      begin
        { LAST declaration wins, not first. The chain is FIFO = registration
          order, and used units are registered before the compiling scope's own
          routines — so first-wins made a unit's routine beat the program's own
          same-named one, silently
          (bug-p-program-function-does-not-shadow-used-unit). So a match in the
          CURRENT scope beats one from elsewhere; everything else is unchanged,
          first-in-chain.

          Only the current-scope preference — NOT "last declaring scope wins",
          which is FPC's `uses a, b` rule and which was measured to break the
          NilPy stdlib. FindProc returns the *representative* of a same-named
          set, and `pyparser.inc` reads `Procs[procIdx].RetType` off it to infer
          expression types; handing back a different scope's entry inferred the
          wrong type and segfaulted `sum(range(i))` at runtime. Same hazard bit
          the Pascal side differently — the parser reads the representative's
          signature to decide that `EmitAsmX64([...])` is an open-array
          constructor rather than a SET, so preferring the last entry made the
          compiler fail to compile itself. The unit-vs-unit half is filed
          separately (bug-p-uses-order-does-not-decide-which-unit-wins). }
        if (ProcUnitIdx[i] = CurrentUnitIdx) and (own < 0) then own := i;
        if last < 0 then last := i;
      end;
    i := ProcHashNext[i];
  end;
  if own >= 0 then last := own;
  if last >= 0 then
  begin
    if WarnUsesLeak and (ProcUnitIdx[last] >= 0) and (ProcUnitIdx[last] <> CurrentUnitIdx) and
       not VisibilityAllows(CurrentUnitIdx, ProcUnitIdx[last]) then
      WarnUsesLeakHit('routine', name, CurrentUnitIdx, ProcUnitIdx[last]);
    Result := last; Exit;
  end;
  { Case-insensitive fallback for case-insensitive symbols only (default Pascal).
    First match wins; ambiguity refinement (warn) is future work. External
    (C-import) symbols are excluded: a C linker symbol IS case-sensitive
    (`printf` <> `Printf`), so they match exact-only by default and relax only
    under {$LAZYCASING ON} below. Same chain: folded-name buckets hold every
    case variant. }
  i := ProcChainHead(lo);
  while i >= 0 do
  begin
    if (not ProcCaseSensitive[i]) and (not ProcExternal[i]) and
       CaseEqual(Procs[i].Name, lo) and
       not (RequireForward and (ProcHdrTok[i] > CurBodyHdrTok)) and
       DeclVisibleBareRoutine(ProcUnitIdx[i], name) then
    begin
      if (ProcUnitIdx[i] = CurrentUnitIdx) and (own < 0) then own := i;
      if last < 0 then last := i;
    end;
    i := ProcHashNext[i];
  end;
  if own >= 0 then last := own;
  if last >= 0 then
  begin
    if WarnUsesLeak and (ProcUnitIdx[last] >= 0) and (ProcUnitIdx[last] <> CurrentUnitIdx) and
       not VisibilityAllows(CurrentUnitIdx, ProcUnitIdx[last]) then
      WarnUsesLeakHit('routine', name, CurrentUnitIdx, ProcUnitIdx[last]);
    Result := last; Exit;
  end;
  { LAZYCASING fallback: only for C-import symbols (external), only when the
    switch is on, and only when EXACTLY ONE matches case-insensitively. Resolves
    to that proc's exact declared spelling (ELF linkage is unaffected) and warns
    so the case mismatch stays visible. Ambiguous -> error. Never reached by
    ordinary Pascal procs (they are not external). }
  if LazyCasing then
  begin
    Result := -1;
    for i := 0 to ProcCount-1 do
      if ProcExternal[i] and CaseEqual(Procs[i].Name, lo) then
      begin
        if Result >= 0 then
          Error('lazycasing: ambiguous case-insensitive match for ''' + name +
                ''' (''' + Procs[Result].Name + ''' vs ''' + Procs[i].Name + ''')');
        Result := i;
      end;
    if Result >= 0 then
    begin
      Warn('lazycasing: ''' + name + ''' resolved to C import ''' +
           Procs[Result].Name + ''' (case mismatch)');
      Exit;
    end;
  end;
  Result := -1;
end;

{ Canonicalize a C-import call name to the exact declared spelling under
  {$LAZYCASING ON}. Returns `name` unchanged when the switch is off, when a proc
  already matches exactly, or when no external symbol matches case-insensitively.
  Ambiguity (>1 external match) is an error. Silent — the user-facing warning is
  emitted once by FindProc during call classification; this only rebinds the
  name so MatchProcCall's exact-name phases find the proc. }
function LazyCanonName(const name: AnsiString): AnsiString;
var i, found: Integer;
begin
  Result := name;
  if not LazyCasing then Exit;
  for i := 0 to ProcCount-1 do
    if Procs[i].Name = name then Exit;            { exact match exists: no rebind }
  found := -1;
  for i := 0 to ProcCount-1 do
    if ProcExternal[i] and CaseEqual(Procs[i].Name, name) then
    begin
      if found >= 0 then
        Error('lazycasing: ambiguous case-insensitive match for ''' + name +
              ''' (''' + Procs[found].Name + ''' vs ''' + Procs[i].Name + ''')');
      found := i;
    end;
  if found >= 0 then Result := Procs[found].Name;
end;

{ The same-named proc that takes exactly `nArgs` parameters, or -1.

  The arity half of what FindProc cannot do. A hand-built call site knows its
  argument count, so this is enough to make an ordinary Pascal `overload` that
  differs only in arity actually reachable from one — which is the trap
  bug-nilpy-stdlib-shim-table-cannot-reach-an-overload is about. Type-based
  selection is still not available this way and still needs MatchProcCall.

  Scans rather than walking the hash chain in one pass because it must consider
  EVERY same-named entry, not stop at the first. }
{ FindProcArity, narrowed to the overload whose parameters are all DOUBLE.
  Arity alone cannot tell `Power(base, exponent: Integer): Integer` from
  `Power(base, exponent: Double): Double` — both take two — and the integer one
  is declared first, so a name lookup hands NilPy's `math.pow` an int-returning
  truncating power: `math.pow(2.0, 0.5)` answered 1 where CPython says
  1.4142135623730951. Python's math module is float-only, so "the all-Double
  arm" is exactly the right question for it to ask.
  bug-n-math-trunc-and-log-need-frontend-intercepts }
function FindProcArityDouble(const name: AnsiString; nArgs: Integer): Integer;
var i, k: Integer; allD: Boolean;
begin
  FindProcArityDouble := -1;
  for i := 0 to ProcCount - 1 do
    if CaseEqual(Procs[i].Name, name) and (Procs[i].ParamCount = nArgs) and
       (Procs[i].RetType = tyDouble) then
    begin
      allD := True;
      for k := 0 to nArgs - 1 do
        if Procs[i].Params[k].TypeKind <> tyDouble then allD := False;
      if allD then
      begin
        FindProcArityDouble := i;
        Exit;
      end;
    end;
end;

function FindProcArity(const name: AnsiString; nArgs: Integer): Integer;
var i: Integer;
begin
  FindProcArity := -1;
  for i := 0 to ProcCount - 1 do
    if (Procs[i].Name = name) and (Procs[i].ParamCount = nArgs) then
    begin
      FindProcArity := i;
      Exit;
    end;
  for i := 0 to ProcCount - 1 do
    if (not ProcCaseSensitive[i]) and CaseEqual(Procs[i].Name, name) and
       (Procs[i].ParamCount = nArgs) then
    begin
      FindProcArity := i;
      Exit;
    end;
end;

function FindProcInUnit(const name: AnsiString; unitIdx: Integer): Integer;
var i: Integer;
begin
  i := ProcChainHead(name);
  while i >= 0 do
  begin
    if (ProcUnitIdx[i] = unitIdx) and (Procs[i].Name = name) then
    begin
      Result := i;
      Exit;
    end;
    i := ProcHashNext[i];
  end;
  i := ProcChainHead(name);
  while i >= 0 do
  begin
    if (ProcUnitIdx[i] = unitIdx) and (not ProcCaseSensitive[i]) and
       CaseEqual(Procs[i].Name, name) then
    begin
      Result := i;
      Exit;
    end;
    i := ProcHashNext[i];
  end;
  Result := -1;
end;

function HasNonOverloadProc(const name: AnsiString): Boolean;
var i: Integer;
begin
  Result := False;
  i := ProcChainHead(name);
  while i >= 0 do
  begin
    if (ProcUnitIdx[i] = CurrentUnitIdx) and (Procs[i].Name = name) and
       not ProcOverloadDirective[i] then
    begin
      Result := True;
      Exit;
    end;
    i := ProcHashNext[i];
  end;
end;

{ The declaration a BARE-IDENTIFIER reference BINDS to, under Pascal's scope
  hiding rule — `uses a, b` binds b's parameterless `Who`, as FPC does.

  Separate from FindProc ON PURPOSE. FindProc returns the *representative* of a
  same-named set and callers read signatures and return types off it; ranking
  inside it broke the self-compile and the NilPy stdlib once already (see the
  note in FindProc). This is the other query — "which one does this reference
  bind to" — and it is only used where a binding is actually being made.

  Calls WITH arguments never come here; they go through MatchProcCall, whose
  MatchElig already removes hidden candidates. This covers the parameterless
  case, which binds off FindProc directly and so was untouched by that.

  `overload` anywhere in the set means JOIN rather than replace, so the
  representative is kept and ordinary overload resolution decides.
  bug-p-uses-order-does-not-decide-which-unit-wins }
function FindProcExactCase(const name: AnsiString): Integer;
begin
  Result := FindProc(name);
  if (Result >= 0) and (Procs[Result].Name <> name) then Result := -1;
end;

function FindProcBound(const name: AnsiString): Integer;
var i, best, bestR, r: Integer; lo: AnsiString; anyOverload: Boolean;
begin
  best := FindProc(name);
  FindProcBound := best;
  if best < 0 then Exit;
  lo := name;
  bestR := ProcScopeRank(best, -1);
  anyOverload := ProcOverloadDirective[best];
  i := ProcChainHead(lo);
  while i >= 0 do
  begin
    if (Procs[i].Name = lo) and
       not (RequireForward and (ProcHdrTok[i] > CurBodyHdrTok)) then
    begin
      r := ProcScopeRank(i, -1);
      if r > bestR then
      begin
        bestR := r; best := i; anyOverload := ProcOverloadDirective[i];
      end
      else if (r = bestR) and ProcOverloadDirective[i] then anyOverload := True;
    end;
    i := ProcHashNext[i];
  end;
  if not anyOverload then FindProcBound := best;
end;

{ Bare-name proc lookup for NilPy USER code — FindProcBound, minus the
  case-insensitive fallback WHERE IT REACHES PYTHON'S OWN NAMESPACE.

  Python is case-sensitive and its builtins live in pylib, so `print(Counter)`
  answered a code address and `print(cOUNTER)` CALLED Counter() where CPython
  raises NameError. Scoped to pylib/pyeval rather than applied to every row
  because the lax rule is what keeps a Pascal RTL routine reachable from NilPy
  under whatever case it is spelled with — the same split DeclCaseSensitive
  draws for symbols, said once here instead of at every lookup.
  bug-nilpy-a-global-collides-case-insensitively-with-a-builtin-proc }
function FindProcNilPyBound(const name: AnsiString): Integer;
var u: Integer;
begin
  Result := FindProcBound(name);
  if Result < 0 then Exit;
  if Procs[Result].Name = name then Exit;      { exact — nothing to decide }
  u := ProcUnitIdx[Result];
  if u < 0 then Exit;
  if (Strs[u].Text = 'pylib') or (Strs[u].Text = 'pyeval') then Result := -1;
end;

function FindProcOverload(const name: AnsiString; nParams: Integer; const ptypes: array of TTypeKind; const parr: array of Boolean; const pbyref: array of Boolean): Integer;
var i, j: Integer; match: Boolean;
begin
  for i := 0 to ProcCount-1 do
  begin
    if (ProcUnitIdx[i] = CurrentUnitIdx) and (Procs[i].Name = name) then
    begin
      if Procs[i].ParamCount = nParams then
      begin
        match := True;
        for j := 0 to nParams-1 do
        begin
          if (Procs[i].Params[j].TypeKind <> ptypes[j]) or
             (Procs[i].Params[j].IsArray <> parr[j]) or
             (Procs[i].Params[j].IsRef <> pbyref[j]) then
            match := False;
        end;
        if match then
        begin
          Result := i;
          Exit;
        end;
      end;
    end;
  end;
  Result := -1;
end;

{ True when a and b are two KNOWN, DISTINCT, NAMED record/class identities.
  Anonymous inline `record ... end` types match structurally (a pxx
  extension) — and each textual occurrence mints a fresh rec id (prescan vs
  body parse!), so identity must never discriminate them. }
function RecContainsRecIdDepth(ri, target, depth: Integer): Boolean;
var ci, fb, i: Integer;
begin
  Result := False;
  if (depth > 8) or (target = REC_NONE) then Exit;
  if ri = target then begin Result := True; Exit; end;
  if ri < REC_UCLASS_BASE then Exit;
  ci := ri - REC_UCLASS_BASE;
  fb := UClsFBase[ci];
  for i := 0 to UClsFCount[ci] - 1 do
    if (UFldRec_[fb + i] <> REC_NONE) and (UFldRec_[fb + i] <> ri) and
       (UFldDynDepth[fb + i] = 0) and
       (UFldTk[fb + i] = Ord(tyRecord)) and  { by-value only: class fields are pointers }
       RecContainsRecIdDepth(UFldRec_[fb + i], target, depth + 1) then
    begin
      Result := True;
      Exit;
    end;
end;

{ True when record ri (transitively, by value) contains record `target`. }
function RecContainsRecId(ri, target: Integer): Boolean;
begin
  Result := RecContainsRecIdDepth(ri, target, 0);
end;

{ True when record ri (transitively) contains a Text/TextFile field — the RTL
  `text` record — so Default() and similar can reject it (FPC forbids file
  types there). }
function RecContainsTextRec(ri: Integer): Boolean;
begin
  Result := RecContainsRecIdDepth(ri, IsRecordType('text'), 0);
end;

function RecIdsDistinctNamed(a, b: Integer): Boolean;
begin
  Result := False;
  if (a = REC_NONE) or (b = REC_NONE) or (a = b) then Exit;
  if (a >= REC_UCLASS_BASE) and (UClsNLen[a - REC_UCLASS_BASE] = 0) then Exit;
  if (b >= REC_UCLASS_BASE) and (UClsNLen[b - REC_UCLASS_BASE] = 0) then Exit;
  Result := True;
end;

{ Rec-aware variant of FindProcOverload for declaration-time matching: two
  routines whose params differ only in RECORD/CLASS identity are DIFFERENT
  overloads. Without this the second `Dot(const a, b: TVec3)` matched the
  registered `Dot(const a, b: TVec2)` slot (both params tyRecord) and its body
  overwrote the first's — every call then ran the last-declared body
  (bug-overload-resolution-record-identity). A rec id is only compared when
  both sides are known (<> REC_NONE), so registration paths that never stored
  ProcParamRecId keep matching as before. }
function FindProcOverloadRec(const name: AnsiString; nParams: Integer; const ptypes: array of TTypeKind; const precs: array of Integer; const parr: array of Boolean; const pbyref: array of Boolean): Integer;
var i, j: Integer; match: Boolean;
begin
  { Hash-chain walk (FIFO = registration order) instead of the full Procs scan
    — this runs once per RegisterProc, so the linear version made registering
    N procs O(N^2) string compares: the 12000-proc token-growth test spent
    ~50% of an 80s compile here (bug-a-token-growth-test-is-slow-and-times-out). }
  i := ProcChainHead(name);
  while i >= 0 do
  begin
    if (ProcUnitIdx[i] = CurrentUnitIdx) and (Procs[i].Name = name) then
    begin
      if Procs[i].ParamCount = nParams then
      begin
        match := True;
        for j := 0 to nParams-1 do
        begin
          if (Procs[i].Params[j].TypeKind <> ptypes[j]) or
             (Procs[i].Params[j].IsArray <> parr[j]) or
             (Procs[i].Params[j].IsRef <> pbyref[j]) then
            match := False;
          if ((ptypes[j] = tyRecord) or (ptypes[j] = tyClass)) and
             (j < MAX_PROC_PARAMS) and
             RecIdsDistinctNamed(precs[j], ProcParamRecId[i * MAX_PROC_PARAMS + j]) then
            match := False;
        end;
        if match then
        begin
          Result := i;
          Exit;
        end;
      end;
    end;
    i := ProcHashNext[i];
  end;
  Result := -1;
end;

function TypesCompatible(pType, aType: TTypeKind): Boolean;
begin
  if pType = aType then
  begin
    Result := True;
    Exit;
  end;
  if (pType = tyVariant) or (aType = tyVariant) then
  begin
    Result := True;
    Exit;
  end;
  if TypeIsOrdinal(pType) and TypeIsOrdinal(aType) then
  begin
    { A Boolean PARAMETER accepts only a Boolean argument (FPC: no implicit
      integer->Boolean). The blanket ordinal rule made overload resolution map
      a NativeInt argument onto `CreateJSON(Data: Boolean)` — declared before
      the Integer overload — so fpjson's TJSONArray.Create([1,2,3]) built
      [true, true, true]. Silent wrong VALUES, no diagnostic. The reverse
      (Boolean arg -> integer param) stays accepted for now. }
    Result := (pType <> tyBoolean) or (aType = tyBoolean);
    Exit;
  end;
  { An ARBITRARY-PRECISION int ARGUMENT matches an integer PARAMETER: it narrows
    through IRLowerCallArg's promo arm, exactly as a wide ordinal does. Promo is
    deliberately not reported by TypeIsOrdinal, so without this a routine could
    not accept its OWN result type — `def fib(n: int)` calling `fib(n - 1)`
    failed with "no overload of fib matches these arguments", because `n - 1` is
    arbitrary precision under the promotable-int default.

    tyPointer is included on purpose (it is an ordinal here): a Pointer formal
    receives the SLOT ADDRESS via IRPromoAddrOf, which is precisely promocore's
    calling convention (PXXPromoToStr and friends). Boolean is excluded for the
    same reason an integer argument does not match a Boolean formal. }
  if TypeIsOrdinal(pType) and TypeIsPromoInt(aType) then
  begin
    Result := pType <> tyBoolean;
    Exit;
  end;
  { ...and the REVERSE: an integer ARGUMENT matches a promo PARAMETER, boxed
    into a hidden promo temp by IRLowerCallArg exactly as the widening
    assignment `p := 12` boxes through PXXPromoFromInt. Without it `f(12)` on
    `function f(n: PromoInt)` failed with "no overload matches / argument types:
    (Integer)" while every other numeric parameter type accepts a literal —
    which made arbitrary precision awkward at exactly the boundary it is most
    useful, `Fact(20)` and friends.
    Boolean excluded on the same grounds as the rule above.
    bug-a-promoint-parameter-rejects-literals-and-call-results }
  if TypeIsPromoInt(pType) and TypeIsOrdinal(aType) then
  begin
    Result := aType <> tyBoolean;
    Exit;
  end;
  if (pType = tyString) and (aType = tyChar) then
  begin
    Result := True;
    Exit;
  end;
  if (pType = tyAnsiString) and (aType = tyChar) then
  begin
    Result := True;
    Exit;
  end;
  if (pType = tyAnsiString) and (aType = tyString) then
  begin
    Result := True;
    Exit;
  end;
  if (pType = tyString) and (aType = tyAnsiString) then
  begin
    Result := True;
    Exit;
  end;
  { A string argument marshals to a const char* (Pointer) parameter: IR lowering
    skips the inline length prefix (+8), so a C binding can pass a Pascal string
    without an explicit PChar() cast. Compatible-match only, after exact match. }
  if (pType = tyPointer) and (aType = tyString) then
  begin
    Result := True;
    Exit;
  end;
  { A managed string (tyAnsiString) likewise marshals to a const char* (Pointer)
    parameter. Its value is already a char pointer (no inline +8 prefix), so the
    IR side passes it as-is. Needed since scalar `string` resolves to tyAnsiString
    in managed mode (the default). }
  if (pType = tyPointer) and (aType = tyAnsiString) then
  begin
    Result := True;
    Exit;
  end;
  { A float formal accepts any float actual (widen/narrow at the ABI boundary,
    e.g. a Double or float-literal into a Single) or an ordinal actual (int ->
    float). Compatible-match only (after the exact-match phase), so a true
    same-width float arg still wins. Requires the internal-call Single ABI
    (feature-single-first-class) — without it a Single param would silently
    receive 0.0, which is why this clause depends on the ABI fix. }
  { ...and a promo actual likewise: `math.sqrt(n - 1)` narrows then converts,
    the same two steps an Int64 actual already takes. }
  if TypeIsFloat(pType) and
     (TypeIsFloat(aType) or TypeIsOrdinal(aType) or TypeIsPromoInt(aType)) then
  begin
    Result := True;
    Exit;
  end;
  { A FROZEN-string parameter (ShortString / string[N]) accepts a managed or
    frozen string (or char) argument — IRLowerCallArg converts through a
    hidden frozen temp (Pascal Script's Const S: ShortString). }
  if ((pType = tyFixedString) or (pType = tyShortString)) and
     ((aType = tyAnsiString) or (aType = tyString) or (aType = tyChar)) then
  begin
    Result := True;
    Exit;
  end;
  { A class instance converts implicitly to a rooted object reference — the
    builtin TObject / `object` param type is a tyPointer (elem tyClass), so a
    `P(o: TObject)` plain routine must accept any tyClass argument, matching
    the method path (bug-tobject-param-truncated-32bit, symptom 2). The
    reverse (class param <- pointer arg) stays rejected. }
  if (pType = tyPointer) and (aType = tyClass) then
  begin
    Result := True;
    Exit;
  end;
  Result := False;
end;

function ProcParamIsInterface(procIdx, j: Integer): Boolean;
{ True iff parameter j of proc procIdx is a CORBA interface type (a fat-pointer
  record), so overload matching can accept a class argument that implements it.
  The param's rec id comes from ProcParamRecId, not the param symbol: param sym
  slots are reused across procs, so Syms[SymIdx].RecName is unreliable here. }
var rec: Integer;
begin
  Result := False;
  if (j < 0) or (j >= Procs[procIdx].ParamCount) then Exit;
  if Procs[procIdx].Params[j].TypeKind <> tyRecord then Exit;
  rec := ProcParamRecId[procIdx * MAX_PROC_PARAMS + j];
  Result := (rec >= REC_UCLASS_BASE) and UClsIsInterface[rec - REC_UCLASS_BASE];
end;

function ByRefArgNeedsLvalue(procIdx, argNo: Integer): Boolean;
{ Does parameter `argNo` REQUIRE its argument to be a true lvalue?

  Only a genuine `var`/`out` does. That is the whole rule, and it replaces a
  five-armed disjunction that had been extended once per aggregate kind — a
  by-value/`const` record, a `const Variant`, a promotable int, a fixed-array
  call result, and (the one that opened this) an interface. Each arm was added
  after a user hit the refusal, each was written twice (the plain-call site and
  the overloaded-call site), and the two copies had already diverged: the
  overloaded one never learned the promo-int arm.
  devdocs/dev/root-cause-over-microfix.md calls two a smell and three a design
  flaw; this was five.

  The question the guard was really asking is "will IRLowerCallArg materialise a
  temp with an address for this argument?" — and the answer never depended on
  the argument's TYPE KIND at all. Everything else that reaches here is by-ref
  for the ABI only: a >8-byte record is copied by the callee, a `const Variant`
  is boxed into a hidden temp, a promo int is copied with PXXPromoCopy, a
  fixed-array result already lands in a caller-owned scratch. In every one of
  those the argument HAS an address and no write-back is expected, so a
  non-lvalue is sound. Only an explicit `var`/`out` needs to write back through
  the caller's storage, and FPC refuses a non-lvalue there too.

  Asking it this way is also what makes `TakeVal(TFoo.Create)` and
  `TakeVal(IFoo(o))` work: a constructor-call node carries the CLASS type kind
  and an explicit interface-cast node carries neither, so neither could ever
  have matched a type-kind list, however many arms it grew.
  bug-a-a-non-lvalue-is-refused-as-an-interface-argument }
begin
  Result := ProcParamExplicitByRef[procIdx * MAX_PROC_PARAMS + argNo] and
            not ProcParamIsConst[procIdx * MAX_PROC_PARAMS + argNo];
end;

function ProcParamIsNilable(procIdx, j: Integer): Boolean;
{ Is parameter j REFERENCE-shaped — one of the types `nil` is assignment-
  compatible with? Pointer, class, interface, method pointer. The last two are
  the reason this cannot be a kind test: both present as tyRecord, and a plain
  record is NOT nil-able, so the record identity has to be consulted.

  ONE predicate, asked from two directions that had answered it differently:
  overload matching (may `nil` bind this parameter?) and the trailing-default
  fill (what NODE does `e: TEv = nil` become?). The second was the segfault —
  it built the literal 0 tagged with the parameter's own kind, so lowering read
  an aggregate off address 0 — and it is precisely the shape of the tyVariant
  note already sitting in DefaultArgValueNode. Two is a smell; this is the
  place they meet instead.
  bug-a-nil-is-not-accepted-as-a-method-pointer-argument }
var pTk: TTypeKind; rec: Integer;
begin
  Result := False;
  if (procIdx < 0) or (j < 0) or (j >= MAX_PROC_PARAMS) then Exit;
  if j >= Procs[procIdx].ParamCount then Exit;
  pTk := Procs[procIdx].Params[j].TypeKind;
  if (pTk = tyPointer) or (pTk = tyClass) then begin Result := True; Exit; end;
  if pTk <> tyRecord then Exit;
  rec := ProcParamRecId[procIdx * MAX_PROC_PARAMS + j];
  if (rec = MethodPtrRecId) and (rec <> REC_NONE) then begin Result := True; Exit; end;
  Result := (rec >= REC_UCLASS_BASE) and UClsIsInterface[rec - REC_UCLASS_BASE];
end;

function MatchArgNilOk(i, j: Integer): Boolean;
{ May the literal `nil` at argument j bind parameter j of candidate i?

  FPC's rule, and it is about the DESTINATION, not the argument: nil is
  assignment-compatible with every reference-shaped type. pxx types nil as a
  tyPointer literal, so the kind channel let it through to a Pointer or a PChar
  parameter and stopped at the three that are not tyPointer -- a class, an
  interface (a record), and a method pointer (also a record). `P(o: TObject)`
  refusing `P(nil)` is the everyday half of that; the method-pointer half is
  what the ticket was filed about.

  Deliberately NOT extended to `var`/`out`: those need an lvalue, and nil is
  not one. That question is ByRefArgNeedsLvalue's, not Params[j].IsRef's --
  IsRef is TRUE for an ordinary by-VALUE record parameter (>8 bytes is passed
  by reference for the ABI), so asking it refused nil for exactly the two cases
  this ticket is about. Same trap, same answer as
  bug-a-a-non-lvalue-is-refused-as-an-interface-argument.
  bug-a-nil-is-not-accepted-as-a-method-pointer-argument }
begin
  Result := False;
  if not MatchArgNilValid then Exit;
  if (j < 0) or (j >= MAX_PROC_PARAMS) then Exit;
  if not MatchArgNil[j] then Exit;
  if PxxDbgEnabled('a.nilarg') then
    writeln('PXXDBG a.nilarg ', Procs[i].Name, ' param ', j, ' kind=', Ord(Procs[i].Params[j].TypeKind),
            ' rec=', ProcParamRecId[i * MAX_PROC_PARAMS + j], ' methodptrrec=', MethodPtrRecId,
            ' needslvalue=', ByRefArgNeedsLvalue(i, j), ' nilable=', ProcParamIsNilable(i, j));
  if ByRefArgNeedsLvalue(i, j) then Exit;
  if Procs[i].Params[j].IsArray then Exit;
  Result := ProcParamIsNilable(i, j);
end;

function MatchParamCompatible(i, j: Integer; aTk: TTypeKind): Boolean;
{ "Does argument j work for parameter j of candidate i?" — the ONE place the
  compatible phases of overload matching ask that. It exists because the answer
  is no longer a pure function of the two TYPE KINDS: the nil rule needs the
  argument's SHAPE and the parameter's record identity. Adding that at the seven
  `not (TypesCompatible(...) or ProcParamUntyped[...])` sites instead is how the
  previous additions went in, and two of them are already spelled slightly
  differently from the others. normalise-dont-special-case.md. }
begin
  Result := TypesCompatible(Procs[i].Params[j].TypeKind, aTk) or MatchArgNilOk(i, j);
end;

function HasExactCaseSensitiveProc(const name: AnsiString): Boolean;
var i: Integer;
begin
  Result := False;
  i := ProcChainHead(name);
  while i >= 0 do
  begin
    if ProcCaseSensitive[i] and (Procs[i].Name = name) then
    begin
      Result := True;
      Exit;
    end;
    i := ProcHashNext[i];
  end;
end;

{ Does proc `idx` answer to `name`? Exact always; case-insensitively too for a
  case-insensitive Pascal proc (default), but never for an external C import
  (printf <> Printf — those relax only under {$LAZYCASING ON}, handled in
  FindProc/LazyCanonName). Mirrors the FindProc fallback so unqualified calls
  resolve mixed-case spellings (inttostr -> IntToStr) like variable names do. }
function ProcNameMatches(idx: Integer; const name: AnsiString): Boolean;
begin
  { require-forward: a main-program routine whose header sits below the body
    being compiled is invisible at call resolution (the MatchProcCall walks
    come through here). ProcHdrTok = 0 (builtins/units/interface/methods/
    nested) always passes; outside a body CurBodyHdrTok is the see-all
    sentinel. }
  if RequireForward and (ProcHdrTok[idx] > CurBodyHdrTok) then
  begin
    Result := False;
    Exit;
  end;
  Result := (Procs[idx].Name = name) or
            ((not (CProgramMode and HasExactCaseSensitiveProc(name))) and
             (not ProcCaseSensitive[idx]) and (not ProcExternal[idx]) and
             CaseEqual(Procs[idx].Name, name));
end;

function PythonSideDeclaresRoutine(const name: AnsiString;
                                  exceptUnit: Integer): Boolean;
{ Is this name already a NilPy BUILTIN — a routine pylib/pyeval declares, or one
  the compiler minted (unit -1)? The question a qualified-only unit's row has to
  answer before it may be dropped: dropping it is only ever about not AMBUSHING
  the Python side, never about hiding a unit wholesale. }
var i, u: Integer;
begin
  PythonSideDeclaresRoutine := False;
  i := ProcChainHead(name);
  while i >= 0 do
  begin
    if ProcNameMatches(i, name) then
    begin
      u := ProcUnitIdx[i];
      if u <> exceptUnit then
      begin
        if u < 0 then begin PythonSideDeclaresRoutine := True; Exit; end;
        if (Strs[u].Text = 'pylib') or (Strs[u].Text = 'pyeval') then
        begin PythonSideDeclaresRoutine := True; Exit; end;
      end;
    end;
    i := ProcHashNext[i];
  end;
end;

function ProcArityMatches(i, nArgs: Integer): Boolean;
{ Exact arity, OR a call that omits trailing args whose params all carry a default
  value (`f(a; b: T = d)` callable as `f(x)`). The type-match phases only check
  the supplied args[0..nArgs-1]; the omitted ones are filled with their defaults
  at call lowering. }
var k: Integer;
begin
  if Procs[i].ParamCount = nArgs then begin Result := True; Exit; end;
  if (nArgs >= 0) and (nArgs < Procs[i].ParamCount) then
  begin
    Result := True;
    for k := nArgs to Procs[i].ParamCount - 1 do
      if (k >= MAX_PROC_PARAMS) or (not ProcParamHasDefault[i * MAX_PROC_PARAMS + k]) then
      begin Result := False; Exit; end;
    Exit;
  end;
  Result := False;
end;

function IntrinsicShadowedByMember(const nm: AnsiString): Boolean;
{ True when an unqualified call to `nm` inside a method body must bind to a
  MEMBER of the enclosing class (or an ancestor) rather than to the builtin of
  that name.

  The soft intrinsics -- Delete, Insert, SetLength, New, Dispose, ReallocMem,
  Str, SetSignalHandler -- each guard themselves with `FindProc(nm) < 0`, which
  lets a plain routine of the same name shadow them. A class METHOD is not
  registered under its bare name, so FindProc missed it and the builtin won:
  TFPObjectList.Remove's own `Delete(Result)` bound the builtin, whose argument
  check then rejected an Integer and produced a diagnostic about dynamic arrays
  -- true of the builtin, and nothing to do with the program. lib/rtl/contnrs.pas
  had not compiled since it landed because of it
  (bug-p-a-class-method-does-not-shadow-a-builtin-of-the-same-name).

  Together with the existing FindProc test this gives the resolution order
  FPC has: enclosing class (own methods, then ancestors) -> unit scope ->
  builtins. Methods only -- a FIELD or PROPERTY of the name is a different
  collision and is not what any of these intrinsics can be confused with. }
begin
  IntrinsicShadowedByMember :=
    (CurProc >= 0) and (CurMethClass >= REC_UCLASS_BASE) and
    (FindUMeth(CurMethClass - REC_UCLASS_BASE, nm) >= 0);
end;

{ The soft intrinsics' shadow test, in one place, plus the escape FPC gives.

  `System.X` is THE documented way to shadow an intrinsic deliberately and still
  reach the original, and FPC code uses it routinely. Every soft intrinsic wrote
  its own `FindProc(nm) < 0` guard and none of them consulted the qualifier, so
  the escape hatch did not escape: `System.Delete(s,2,3)` with a unit-level
  `Delete` in scope bound the user routine (error, or — for Inc/Dispose/Ord —
  SILENTLY called it and skipped the intrinsic's effect entirely).
  bug-p-a-system-qualified-call-binds-a-same-named-user-routine

  qUnit is ConsumeUnitQualifier's result: -2 = `System.`, -1 = unqualified,
  >= 0 = a named unit. Only the System marker opens a shadowed intrinsic — a
  unit-qualified call asks for THAT unit's routine by construction. }
function SoftIntrinsicOpen(const nm: AnsiString; qUnit: Integer): Boolean;
{ For the intrinsics that let a routine OR an enclosing class's method shadow
  them (Delete, Insert, SetLength, New, Dispose, ReallocMem, Str, ...). }
begin
  SoftIntrinsicOpen := (qUnit = -2) or
    ((FindProc(nm) < 0) and not IntrinsicShadowedByMember(nm));
end;

function SoftIntrinsicOpenSym(const nm: AnsiString; qUnit: Integer): Boolean;
{ For the older guards, which test an in-scope SYMBOL rather than a method
  (Inc, Dec, GetMem, FreeMem, Break, Continue, Move/FillChar, ...). }
begin
  SoftIntrinsicOpenSym := (qUnit = -2) or
    ((FindProc(nm) < 0) and (FindSym(nm) < 0));
end;

function FindUMethArity(ci: Integer; const name: AnsiString; nExplicitArgs: Integer): Integer;
{ Overload-aware method lookup: first name match (walking the parent chain)
  whose proc accepts the call's EXPLICIT arg count (self added per entry;
  exact arity or trailing defaults cover the rest). Falls back to the plain
  first-name-match so single-method behavior and error paths are unchanged. }
var i, base, cnt, curr, want: Integer; lo, name2: AnsiString;
begin
  name2 := name;
  lo := ULower(name2);
  curr := ci;
  while curr >= 0 do
  begin
    base := UClsMBase[curr];
    cnt  := UClsMCount[curr];
    i := 0;
    while i < cnt do
    begin
      if UMemberNameMatch(UMthNOff[base + i], UMthNLen[base + i], curr, name, lo) then
      begin
        want := nExplicitArgs;
        want := want + 1;   { every method has Self at 0, class methods included }
        if ProcArityMatches(UMthProc_[base + i], want) then
        begin Result := base + i; Exit; end;
      end;
      Inc(i);
    end;
    curr := UClsParent[curr];
  end;
  Result := FindUMeth(ci, name);
end;

function FindUMethForSig(ci: Integer; const name: AnsiString; sigProc: Integer): Integer;
{ The class method that implements ONE interface method SLOT.

  The IMT builder used to fill every slot with FindUMeth -- a NAME-only lookup --
  so an OVERLOADED interface method bound all of its slots to the class's FIRST
  method of that name: `IThing.Pick(x)` and `IThing.Pick(x, y)` both dispatched to
  TThing.Pick(x), and the second argument was read as garbage. Silent wrong
  values, and only THROUGH the interface -- the direct class call resolved
  correctly the whole time, which is why the defect survived
  (bug-p-interface-method-overload-picks-the-first-slot).

  Signature = arity, then each parameter's type kind, array-ness and class/record
  id. Param 0 is Self on both sides and is skipped. Falls back to the first name
  match when nothing matches exactly, so a class whose implementation differs only
  cosmetically binds exactly as it did before, and "does not implement" stays the
  IMT builder's diagnostic rather than this function's. }
var i, base, cnt, curr, k, cp, sRec, cRec: Integer; lo, name2: AnsiString; ok: Boolean;
begin
  Result := -1;
  name2 := name;
  lo := ULower(name2);
  curr := ci;
  while curr >= 0 do
  begin
    base := UClsMBase[curr];
    cnt  := UClsMCount[curr];
    i := 0;
    while i < cnt do
    begin
      if UMemberNameMatch(UMthNOff[base + i], UMthNLen[base + i], curr, name, lo) then
      begin
        cp := UMthProc_[base + i];
        if (cp >= 0) and (sigProc >= 0) and
           (Procs[cp].ParamCount = Procs[sigProc].ParamCount) then
        begin
          ok := True;
          k := 1;
          while k < Procs[cp].ParamCount do
          begin
            if (Procs[cp].Params[k].TypeKind <> Procs[sigProc].Params[k].TypeKind) or
               (Procs[cp].Params[k].IsArray <> Procs[sigProc].Params[k].IsArray) then
            begin ok := False; k := Procs[cp].ParamCount; end
            else
            begin
              if k < MAX_PROC_PARAMS then
              begin
                cRec := ProcParamRecId[cp * MAX_PROC_PARAMS + k];
                sRec := ProcParamRecId[sigProc * MAX_PROC_PARAMS + k];
                { only when BOTH sides know the id -- an unrecorded one must not
                  veto a match that the type kinds already agree on }
                if (cRec <> REC_NONE) and (sRec <> REC_NONE) and (cRec <> sRec) then
                begin ok := False; k := Procs[cp].ParamCount; end
                else
                  k := k + 1;
              end
              else
                k := k + 1;
            end;
          end;
          if ok then begin Result := base + i; Exit; end;
        end;
      end;
      Inc(i);
    end;
    curr := UClsParent[curr];
  end;
  Result := FindUMeth(ci, name);
end;

function FindUMethByProc(ci, procIdx: Integer): Integer;
{ The UMeth entry bound to a specific proc — an overloaded method's impl must
  update ITS OWN entry (slot/proc mapping), not the first name match. }
var i, base, cnt, curr: Integer;
begin
  Result := -1;
  curr := ci;
  while curr >= 0 do
  begin
    base := UClsMBase[curr];
    cnt  := UClsMCount[curr];
    for i := 0 to cnt - 1 do
      if UMthProc_[base + i] = procIdx then begin Result := base + i; Exit; end;
    curr := UClsParent[curr];
  end;
end;

{ True when call arg j's RECORD identity contradicts candidate i's param j.
  Only fires when both rec ids are known and the arg rec ids were filled for
  this call (MatchArgRecValid) — otherwise the matcher stays rec-blind, so
  callers that don't provide rec ids keep the legacy behavior. Records only:
  class params keep their inheritance-tolerant matching.
  (bug-overload-resolution-record-identity) }
function MatchArgRecMismatch(i, j: Integer; aTk: TTypeKind): Boolean;
var pr, ar, curr: Integer;
begin
  Result := False;
  { A definitely-scalar argument cannot bind an ARRAY parameter. Checked first,
    and independently of the record channel below, because the two facts come
    from different places: argTypes carries a fixed array's ELEMENT kind, so the
    array parameter is INDISTINGUISHABLE from a scalar one by type alone and won
    on declaration order. `array of const` (tyRecord / tyVariant element) is
    excluded — it legitimately takes anything.
    bug-a-an-integer-argument-binds-a-fixed-array-overload }
  if MatchArgScalarValid and (j < MAX_PROC_PARAMS) and MatchArgScalar[j] and
     Procs[i].Params[j].IsArray and
     (Procs[i].Params[j].TypeKind <> tyRecord) and
     (Procs[i].Params[j].TypeKind <> tyVariant) and
     not ProcParamUntyped[i * MAX_PROC_PARAMS + j] then
  begin
    Result := True;
    Exit;
  end;
  if not MatchArgRecValid then Exit;
  if j >= MAX_PROC_PARAMS then Exit;
  { Records AND classes. Classes were excluded here, so an UNRELATED class bound
    happily to any class-typed parameter — resolution took the first arity match
    and the callee then read one object's memory through another class's shape:
    silent wrong dispatch where the layouts happen to agree, a segfault where
    they do not (`dict([("a",1)])` binding its TPyList to `dict(d: TPyDict)`,
    `bool(obj)` binding to `bool(l: TPyList)`).
    (bug-a-overload-resolution-ignores-class-identity)
    The descendant tolerance below already did the right thing — it was simply
    never reached for classes. }
  if (aTk <> Procs[i].Params[j].TypeKind) then Exit;
  if (aTk <> tyRecord) and (aTk <> tyClass) then Exit;
  pr := ProcParamRecId[i * MAX_PROC_PARAMS + j];
  ar := MatchArgRec[j];
  if not RecIdsDistinctNamed(ar, pr) then Exit;
  { A TObject-typed parameter accepts anything — it is the root, and a user
    class with no explicit parent has UClsParent = -1, so the ancestor walk
    below would not reach it. }
  if (pr >= REC_UCLASS_BASE) and (FindUClass('TObject') >= 0) and
     (pr = REC_UCLASS_BASE + FindUClass('TObject')) then Exit;
  { Interface (and any future record) inheritance: an argument whose type
    DESCENDS from the param's type is a valid widening (IBar -> IFoo param),
    not a mismatch. Walk the arg's ancestor chain. }
  if (pr >= REC_UCLASS_BASE) and (ar >= REC_UCLASS_BASE) then
  begin
    curr := ar - REC_UCLASS_BASE;
    while curr >= 0 do
    begin
      if curr = pr - REC_UCLASS_BASE then Exit;   { descendant: compatible }
      curr := UClsParent[curr];
    end;
  end;
  Result := True;
end;

{ Strs[] index of the compiler's builtin intrinsic unit (`builtin`, home of
  Random and friends), cached: InternStr is an O(StrCount) scan and this is hit
  on every unqualified call. Interns the name if the unit was never loaded — the
  returned idx then matches no proc, so demotion simply never fires. }
function BuiltinUnitIdx: Integer;
begin
  if not BuiltinUnitIdxSet then
  begin
    BuiltinUnitIdxCache := InternStr('builtin');
    BuiltinUnitIdxSet := True;
  end;
  Result := BuiltinUnitIdxCache;
end;

{ Call-candidate eligibility gate. A proc answers to `name` as usual, EXCEPT a
  builtin-unit proc is demoted out of the set entirely when `demote` is set —
  i.e. some non-builtin routine of the same name is in scope. The builtin is a
  fallback only, reached when nothing else declares the name. This makes the
  winner name-level, not arg-width-level, so a used unit's routine can never be
  silently split with the intrinsic by argument width
  (bug-pascal-unqualified-call-binds-builtin-over-used-unit). }
{ Is NilPy proc `pi` BOUND at the cursor? A module-level `def` binds its name
  when the `def` STATEMENT runs, so a module-BODY call standing above it must not
  see it — that is the whole of Python's rule here. ProcPyDefTok is 0 for
  everything that is not a NilPy module-level def, so this answers True there at
  no cost, and inside a def body (CurProc >= 0) the code runs after the entire
  module has executed, which is what makes an ordinary forward reference between
  two defs legal.

  One place for the question, because it is asked from three: MatchElig (the
  candidate set), ParseFactorCore (the intrinsic guards' procIdx), and
  PyUserNameShadowsHere (`set(...)`'s own hook test).
  bug-nilpy-intrinsic-only-builtin-is-shadowed-from-the-top-of-the-module }
function PyDefBoundHere(pi: Integer): Boolean;
begin
  Result := (pi < 0) or (ProcPyDefTok[pi] = 0) or (CurProc >= 0) or
            (ProcPyDefTok[pi] <= TokPos);
end;

{ SCOPE RANK of a declaration, for Pascal's hiding rule: a declaration hides a
  same-named one from an EARLIER or OUTER scope. Higher wins.

    compiling scope (the program, or the unit being parsed)  -> HIDE_RANK_SELF
    a used unit                                              -> its position in
                                                                CompiledUnits,
                                                                which for a
                                                                `uses a, b`
                                                                clause IS the
                                                                uses order
    the builtin unit                                         -> 0, lowest

  CompiledUnits already records compile order, so the rank this needed did not
  have to be invented. }
function ProcScopeRank(idx, bIdx: Integer): Integer;
var u, k: Integer;
begin
  u := ProcUnitIdx[idx];
  if u = CurrentUnitIdx then begin ProcScopeRank := HIDE_RANK_SELF; Exit; end;
  if (bIdx >= 0) and (u = bIdx) then begin ProcScopeRank := 0; Exit; end;
  ProcScopeRank := 1;
  for k := 0 to CompiledUnitCount - 1 do
    if CompiledUnits[k] = u then begin ProcScopeRank := k + 2; Exit; end;
end;

{ The winning scope rank for `name` — every candidate below it is HIDDEN.
  Returns -1 for "nothing hides anything here", which is also what an
  `overload`-marked winner yields: `overload` means JOIN the set rather than
  replace it, and that is what keeps EmitAsmX64's `array of const` / AnsiString
  pair alive across scopes.

  Computed once per (name, flags) and memoised, because MatchElig is called in a
  tight loop over the whole proc table for ONE name — recomputing per candidate
  would make matching quadratic. The proc table grows during parsing, so
  ProcCount is part of the key. }
function ProcHideRank(const name: AnsiString; demote: Boolean;
                      bIdx: Integer; userOnly, dropLateDef: Boolean): Integer;
var i, r, best, flags: Integer; anyOverload: Boolean;
begin
  flags := Ord(demote) + 2 * Ord(userOnly) + 4 * Ord(dropLateDef) + 8 * (bIdx + 2);
  if HideRankValid and (HideRankProcCount = ProcCount) and
     (HideRankFlags = flags) and (HideRankUnit = CurrentUnitIdx) and
     (HideRankName = name) then
  begin ProcHideRank := HideRankVal; Exit; end;
  best := -1; anyOverload := False;
  for i := 0 to ProcCount - 1 do
  begin
    if not MatchEligBase(i, name, demote, bIdx, userOnly, dropLateDef) then Continue;
    r := ProcScopeRank(i, bIdx);
    if r > best then begin best := r; anyOverload := ProcOverloadDirective[i]; end
    else if (r = best) and ProcOverloadDirective[i] then anyOverload := True;
  end;
  if anyOverload then best := -1;
  HideRankName := name; HideRankFlags := flags; HideRankProcCount := ProcCount;
  HideRankUnit := CurrentUnitIdx; HideRankVal := best; HideRankValid := True;
  ProcHideRank := best;
end;

{ The eligibility tests that do NOT depend on scope hiding — the set
  ProcHideRank ranks over. Split out so the rank pass and the final predicate
  cannot drift apart. }
function MatchEligBase(idx: Integer; const name: AnsiString; demote: Boolean;
                  bIdx: Integer; userOnly, dropLateDef: Boolean): Boolean;
begin
  Result := ProcNameMatches(idx, name) and not (demote and (ProcUnitIdx[idx] = bIdx));
  { ...and, under --strict-uses, a routine declared in a unit this scope cannot
    legitimately see is not a candidate at all — the non-transitive `uses` rule
    applied where CALLS actually resolve. bug-pascal-uses-is-transitive. }
  { DeclVisibleBareRoutine and not DeclVisible: THIS is the lookup a direct call
    site resolves through, so it is where a Pascal unit pulled in by a NilPy
    `import` has to stop being a candidate. FindProc alone was not enough —
    `max(1.5, 2)` never goes through it, which is why the first cut of the fix
    hid a bare `Power` and still answered 2.0.
    bug-nilpy-import-leaks-the-units-names-into-the-python-namespace }
  if Result and not DeclVisibleBareRoutine(ProcUnitIdx[idx], name) then
  begin
    { The warn instrument's blind spot, closed: FindProc is NOT the lookup a
      direct call site resolves through, so --warn-uses-leak never saw the
      ticket's own headline repro. Reported as `cand` because this fires per
      REJECTED CANDIDATE, not per resolved name — noisier than the FindProc
      hits and a different unit of count. }
    if WarnUsesLeak then WarnUsesLeakHit('cand', name, CurrentUnitIdx, ProcUnitIdx[idx]);
    Result := False;
  end;
  { ...and, in a NilPy program that declares this name itself, ONLY that
    declaration is a candidate — see PyUserShadowsProc. }
  if Result and userOnly and (ProcUnitIdx[idx] <> -1) then Result := False;
  { ...and the mirror image: a module-level `def` is not bound ABOVE its own
    `def` statement, so at a module-body call site that precedes it the def is
    not a candidate at all and the builtin it shadows must win. userOnly is
    False here by construction (PyUserShadowsProc said the def is not bound
    yet), which left the def in the set to win on ARGUMENT FIT — `set([1,1])`
    above a `def set(x)` reached the user's, silently.

    Only when dropLateDef says another candidate exists: with no alternative the
    call would become a compile error, and CPython accepts a module-body forward
    call that never executes.
    bug-nilpy-intrinsic-only-builtin-is-shadowed-from-the-top-of-the-module }
  if Result and dropLateDef and (ProcUnitIdx[idx] = -1) and
     (not PyDefBoundHere(idx)) then Result := False;
end;

{ ...plus Pascal's SCOPE HIDING: a declaration in a later/inner scope hides a
  same-named one from an earlier/outer scope unless marked `overload`.

  This is candidate REMOVAL, deliberately, and it lives here rather than in
  FindProc. Ranking inside FindProc's chain was tried and broke two things that
  `gate.sh quick` did not catch — the compiler's own self-compile (the parser
  reads the returned proc's SIGNATURE to decide whether `[...]` is an
  open-array constructor or a set) and the NilPy stdlib (`pyparser.inc` infers
  expression types from the returned proc's RetType, and `sum(range(i))`
  segfaulted far from the cause). FindProc returns an overload-set
  REPRESENTATIVE that callers read types off; it is not a "which one does this
  call bind to" query. MatchElig is, and its 9 call sites are exactly the
  matching phases, so one test here removes hidden declarations from every
  phase at once.
  bug-p-uses-order-does-not-decide-which-unit-wins }
function MatchElig(idx: Integer; const name: AnsiString; demote: Boolean;
                  bIdx: Integer; userOnly, dropLateDef: Boolean): Boolean;
var hr: Integer;
begin
  Result := MatchEligBase(idx, name, demote, bIdx, userOnly, dropLateDef);
  if not Result then Exit;
  { Only for a PLAIN UNQUALIFIED call. `demote` is passed as `qUnit = -1`, so it
    is False exactly when the call named its scope — `System.Random(i + 1)`,
    which must reach the builtin even though a used unit declares Random and
    outranks it. Hiding answers "which declaration does a bare name see"; a
    qualified call has already answered that itself (test_builtin_name_demote). }
  if not demote then Exit;
  hr := ProcHideRank(name, demote, bIdx, userOnly, dropLateDef);
  if (hr >= 0) and (ProcScopeRank(idx, bIdx) < hr) then Result := False;
end;

{ Does the NilPy program itself declare a routine called `name`?

  Python has no overloading: a module-level `def sorted(x)` REPLACES the
  builtin, and every call in that module goes to it. pxx registers pylib's and
  pyeval's routines as ordinary overloaded procs, so a user def merely JOINED
  the candidate set and then lost on argument fit — `def sorted(x)` called with
  a list lost to `sorted(TPyList)` and the program silently printed the
  builtin's answer, while the same def called with an int appeared to work
  because no pylib overload matched (bug-nilpy-user-def-does-not-shadow-a-
  pylib-builtin; that accident is why the ticket's first diagnosis, registration
  order, measured as false).

  So the winner has to be decided at NAME level, not argument-width level —
  exactly the rule MatchElig's `demote` already implements for Pascal's
  builtin-vs-used-unit case (bug-pascal-unqualified-call-binds-builtin-over-
  used-unit). This is the same rule with "declared by the main program"
  (ProcUnitIdx = -1) in place of "not the builtin unit", and it demotes ALL of
  the unit's overloads together, which is the trap
  project_findproc_by_name_ignores_overloads warns about.

  NilPyUserCode-gated: a Pascal unit compiled into the same binary keeps FPC's
  rules, where a program routine and a unit routine of the same name do not
  work this way. }
function PyUserShadowsProc(const name: AnsiString): Boolean;
var i: Integer;
begin
  PyUserShadowsProc := False;
  if NilPyUserCode then
  begin
    i := ProcChainHead(name);
    while i >= 0 do
    begin
        { ...and, for a def that shadows a BUILTIN, only from its own `def`
        statement onward — Python rebinds the name when that statement RUNS.
        ProcPyDefTok is 0 for everything else, so this costs nothing there. }
      if ProcNameMatches(i, name) and (ProcUnitIdx[i] = -1) and
         ((ProcPyDefTok[i] = 0) or (ProcPyDefTok[i] <= TokPos)) then
      begin
        PyUserShadowsProc := True;
        Break;
      end;
      i := ProcHashNext[i];
    end;
  end;
  { PXXDBG=n.shadow — every shadow question and its answer. Worth having
    permanently: this predicate gates BOTH the overload demote and each
    name-keyed intrinsic's guard, so when a builtin is not being shadowed the
    first thing to establish is whether the predicate even said so, and
    reasoning about it from the call sites is what burned an hour. }
  if PxxDbgEnabled('n.shadow') then
    WriteLn('PXXDBG n.shadow ', name, ' user=', PyUserShadowsProc,
            ' nilpyuser=', NilPyUserCode, ' curunit=', CurrentUnitIdx);
end;

{ Human-readable spelling of a type kind, for diagnostics. A raw TTypeKind
  ORDINAL in an error message is unactionable — nobody can read "param[0] = 23"
  (bug-overload-mismatch-dumps-internals-to-stdout). }
function TypeKindSpelling(tk: TTypeKind): AnsiString;
begin
  case tk of
    tyUnknown:     Result := 'unknown';
    tyInteger:     Result := 'Integer';
    tyBoolean:     Result := 'Boolean';
    tyChar:        Result := 'Char';
    tyString:      Result := 'ShortString';
    tyRecord:      Result := 'record';
    tyClass:       Result := 'class';
    tyInt8:        Result := 'ShortInt';
    tyUInt8:       Result := 'Byte';
    tyBool8:       Result := '_Bool';
    tyInt16:       Result := 'SmallInt';
    tyUInt16:      Result := 'Word';
    tyInt32:       Result := 'LongInt';
    tyUInt32:      Result := 'Cardinal';
    tyInt64:       Result := 'Int64';
    tyUInt64:      Result := 'QWord';
    tyNativeInt:   Result := 'NativeInt';
    tyNativeUInt:  Result := 'NativeUInt';
    tyPointer:     Result := 'Pointer';
    tySingle:      Result := 'Single';
    tyDouble:      Result := 'Double';
    tyExtended:    Result := 'Extended';
    tySet:         Result := 'set';
    tyVariant:     Result := 'Variant';
    tyAnsiString:  Result := 'AnsiString';
    tyAuto:        Result := 'auto';
    tyShortString: Result := 'ShortString';
    tyFixedString: Result := 'string[N]';
    else           Result := 'type';
  end;
end;

function BinopOperandIsMachineWord(tk: TTypeKind): Boolean;
{ May this operand take part in plain integer arithmetic in a register? Ordinals
  and pointers obviously — and tyString / tySet too, because a frozen string or a
  set VALUE *is* its address (ir.inc, AN_DEREF: "a frozen-string / set value IS
  its address (no load)"), so the node holds a machine word however it is tagged. }
begin
  Result := TypeIsOrdinal(tk) or (tk = tyBoolean) or (tk = tyUnknown) or
            (tk = tyString) or (tk = tySet) or (tk = tyPointer);
end;

function CurProcNoteForError: AnsiString;
{ ' in <proc>' when a body is being emitted, '' at top level. Backend refusals
  ("not yet supported on target X") name a construct but not WHERE it is, and
  the `near:` context on a codegen-time Error is the LEXER's stale position —
  it points at whatever was tokenised last, which is routinely a different unit
  entirely. Without the proc name a cross-target wall in a builtin unit costs a
  bisect to locate. }
begin
  if (CurProc >= 0) and (CurProc < ProcCount) then
    Result := ' in ' + Procs[CurProc].Name
  else
    Result := '';
end;

function TypeIsMachineInt(tk: TTypeKind): Boolean;
{ The fixed-width integer kinds — deliberately NOT the whole of TypeIsOrdinal:
  Boolean, Char, Pointer, Bool8 and UCS4Char are ordinals that do not take part
  in integer-vs-float overload ranking, and the arbitrary-precision promo kinds
  have their own lossless rules in ArgNarrowsInt. }
begin
  Result := tk in [tyInteger, tyInt8, tyUInt8, tyInt16, tyUInt16, tyInt32,
                   tyUInt32, tyInt64, tyUInt64, tyNativeInt, tyNativeUInt];
end;

function ArgNarrowsInt(pType, aType: TTypeKind): Boolean;
{ True when binding an integer argument to this parameter would silently DROP
  high bits — a 16-bit argument onto a Byte parameter, an Int64 onto a LongInt.
  Overload resolution otherwise takes the first COMPATIBLE candidate in chain
  order, so with `p(v: Byte)` declared before `p(v: Word)`, `p(40000)` printed
  64: the argument was truncated, silently, in ordinary user code. Same shape as
  the fpjson `CreateJSON(Data: Boolean)` incident TypesCompatible already guards
  against — wrong VALUES, no diagnostic. Used to rank candidates, not to reject
  them: a narrowing candidate still wins when it is the only one that matches. }
begin
  { An ARBITRARY-PRECISION argument narrows into EVERY machine-int parameter —
    there is no width that holds it — so a lossless candidate must be preferred
    whatever the declaration order. `f"{n}"` lexes to `pystr_of(n)`, whose
    Int64 overload was picked over the Variant one and wrapped mod 2^64: for
    2**70 that is exactly 0, so a 22-digit number printed as "0". The Variant
    overload is lossless (PXXPromoToVariant carries the exact decimal as tag
    VT_PROMO_INT64), and Phase 1d now picks it.

    This RANKS, it does not reject — Phase 2 still binds a promo to an Int64
    parameter when that is the only candidate, which is what makes
    `def fib(n: int)` accept `fib(n - 1)` under NilPy's documented 64-bit
    narrowing of an int-annotated binding. }
  if TypeIsPromoInt(aType) then
  begin
    { EVERY ordinal parameter narrows arbitrary precision, not just the ones
      smaller than 64 bits — Char and Boolean included, or `f"{n}"` binds
      pystr_of(Char) and prints a NUL byte. A FLOAT parameter narrows too: a
      double carries 53 bits of mantissa, so a bignum loses digits (that bound
      pystr_of(Double) and printed 1.1805916207174113e+21 where Python prints
      all 22 digits).

      tyPointer is the ONE lossless ordinal: it receives the slot ADDRESS via
      IRPromoAddrOf, which is promocore's own calling convention. Ranking the
      rest as narrowing is what leaves the VARIANT overload — lossless, since
      PXXPromoToVariant carries the exact decimal — as the Phase 1d winner. }
    Result := (TypeIsOrdinal(pType) and (pType <> tyPointer)) or TypeIsFloat(pType);
    Exit;
  end;
  Result := (pType in [tyInteger, tyInt8, tyUInt8, tyInt16, tyUInt16, tyInt32,
                       tyUInt32, tyInt64, tyUInt64, tyNativeInt, tyNativeUInt]) and
            (aType in [tyInteger, tyInt8, tyUInt8, tyInt16, tyUInt16, tyInt32,
                       tyUInt32, tyInt64, tyUInt64, tyNativeInt, tyNativeUInt]) and
            (TypeSize(pType) < TypeSize(aType));
end;

function IntParamHoldsEveryValue(pType, aType: TTypeKind): Boolean;
{ Can EVERY value of integer type aType be represented in pType? The "fits"
  half of FPC's narrowest-that-fits overload rule, and deliberately NOT
  ArgNarrowsInt: that one compares `TypeSize(pType) < TypeSize(aType)` and is
  signedness-blind, so it says a LongInt parameter does not narrow a Cardinal
  argument. It does — same width, but half the range is unreachable — and
  Cardinal is exactly the row that shows FPC ranks by RANGE and not by declared
  width (measured: FPC binds Int64 there and LongInt everywhere else).

  ArgNarrowsInt is left alone on purpose: it ranks candidates on the DEFAULT
  path too, and the default dialect's widening is intended behaviour, not a bug
  to fix here. Used only under StrictOverloadWidth.
  compat-pascal-strict-fpc-should-pick-the-narrowest-integer-overload }
begin
  if TypeSigned(pType) = TypeSigned(aType) then
    Result := TypeSize(pType) >= TypeSize(aType)
  else if TypeSigned(pType) then
    { signed parameter, unsigned argument: it needs a spare bit for the sign }
    Result := TypeSize(pType) > TypeSize(aType)
  else
    { unsigned parameter, signed argument: a negative value has nowhere to go }
    Result := False;
end;

function LiteralIntKind(v: Int64): TTypeKind;
{ FPC's type for an untyped integer CONSTANT: the smallest type that holds it,
  signed candidate before unsigned at each width. pxx types every literal as
  LongInt (Int64 when it does not fit), which is a fine type for the VALUE but
  the wrong input to overload ranking — `hi($1234)` bound Hi(LongInt) and
  answered 0 where FPC binds Hi(SmallInt) and answers 18.

  Used ONLY to rank overload candidates (see MatchCallDelphiProcAddr). The
  literal's own expression type is untouched, so arithmetic promotion is
  unaffected — `b + 0` stays LongInt, as it is in FPC. }
begin
  if (v >= -128) and (v <= 127) then Result := tyInt8
  else if (v >= 0) and (v <= 255) then Result := tyUInt8
  else if (v >= -32768) and (v <= 32767) then Result := tyInt16
  else if (v >= 0) and (v <= 65535) then Result := tyUInt16
  else if (v >= -2147483648) and (v <= 2147483647) then Result := tyInt32
  else if (v >= 0) and (v <= 4294967295) then Result := tyUInt32
  else Result := tyInt64;
end;

function IsIntTypeKind(t: TTypeKind): Boolean;
begin
  Result := t in [tyInteger, tyInt8, tyUInt8, tyInt16, tyUInt16, tyInt32,
                  tyUInt32, tyInt64, tyUInt64, tyNativeInt, tyNativeUInt];
end;

function MatchParamExact(paramTk, argTk: TTypeKind): Boolean;
{ Exact-match test for one argument. `Integer` and `LongInt` are the SAME type
  -- both 4-byte signed, and FPC declares one as the other's alias -- but they
  carry distinct kinds here (tyInteger / tyInt32), so a bare kind comparison
  discriminated on the SPELLING and no exact match was found.

  What that cost: sysutils declares IntToHex for Int64, LongInt and LongWord,
  precisely so a 32-bit value renders 8 digits and not 16. `li: longint` hit
  the LongInt overload and printed FFFFFFFF; `i: integer` fell past the exact
  phase into the compatible ones, bound Int64, and printed FFFFFFFFFFFFFFFF --
  for the far more common spelling of the same type
  (bug-p-integer-and-longint-are-not-the-same-type-in-overload-matching).

  A unit cannot legitimately declare both overloads (FPC rejects the pair as
  duplicate), so treating them as one cannot make a previously-unambiguous call
  ambiguous. }
begin
  MatchParamExact := (paramTk = argTk) or
                     ((paramTk = tyInteger) and (argTk = tyInt32)) or
                     ((paramTk = tyInt32) and (argTk = tyInteger));
end;

function MatchProcCall(const name: AnsiString; nArgs: Integer; const argTypes: array of TTypeKind; suppressBuiltin: Boolean): Integer;
var i, j: Integer; match: Boolean; cn, nl: AnsiString; demote: Boolean; bIdx: Integer;
    userOnly: Boolean; ownM, anyM: Integer; pass: Integer;
    bestW, bestI, w: Integer;   { --strict-overload-width ranking }
    fits: Boolean;
    variantArg: Boolean;    { some argument is a Variant -- see Phase 1c1 }
    dropLateDef: Boolean;   { NilPy: a def below this call site is not bound yet }
begin
  { LAZYCASING: rebind a wrong-case C-import call to its exact declared spelling
    once, then match normally (the exact-name phases below then find it). }
  cn := LazyCanonName(name);
  if cn <> name then
  begin
    Result := MatchProcCall(cn, nArgs, argTypes, suppressBuiltin);
    Exit;
  end;

  { builtin-is-fallback: only for a plain unqualified call (suppressBuiltin).
    A `System.X` call (qUnit = -2) passes suppressBuiltin=False so the intrinsic
    still wins, matching the explicit-System semantics. Demote fires only when a
    real (non-builtin) same-name routine is actually in scope. }
  { A NilPy `def` REPLACES a builtin of the same name, at name level rather
    than by argument fit — see PyUserShadowsProc. Independent of the builtin
    demote below: pylib and pyeval are ordinary units, not the builtin unit. }
  userOnly := PyUserShadowsProc(name);
  { ...and, when it says the def is NOT bound here, the def has to be taken out
    of the candidate set rather than merely un-privileged — otherwise it wins on
    argument fit and the builtin it shadows is never reached. Only in the module
    BODY (inside a def body the code runs after the whole module has executed,
    so a forward reference between two defs is legal Python), and only when some
    OTHER routine of this name exists to fall back to: with no alternative this
    would turn a never-executed module-body forward call into a compile error,
    which CPython accepts.
    bug-nilpy-intrinsic-only-builtin-is-shadowed-from-the-top-of-the-module }
  dropLateDef := False;
  if NilPyUserCode and (not userOnly) and (CurProc < 0) then
  begin
    i := ProcChainHead(name);
    while i >= 0 do
    begin
      if ProcNameMatches(i, name) and (ProcUnitIdx[i] <> -1) then
      begin dropLateDef := True; Break; end;
      i := ProcHashNext[i];
    end;
  end;
  demote := False;
  bIdx := -1;
  if suppressBuiltin then
  begin
    bIdx := BuiltinUnitIdx;
    i := ProcChainHead(name);
    while i >= 0 do
    begin
      { ...and only a VISIBLE one demotes. Under --strict-uses the two filters
        have to compose: an out-of-scope candidate is not an alternative, so
        counting it here demoted the builtin and then dropped the out-of-scope
        one too, leaving NO candidate at all. Measured: pylib's `{x:g}` spec
        calls FloatToStr, builtin declares it, and sysutils' copy — which pylib
        cannot see — was silently doing the demoting. }
      if ProcNameMatches(i, name) and (ProcUnitIdx[i] <> bIdx) and
         DeclVisibleBareRoutine(ProcUnitIdx[i], name) then
      begin demote := True; Break; end;
      i := ProcHashNext[i];
    end;
  end;
  { Phase 1: Try exact match.

    Two exact matches are INDISTINGUISHABLE by signature, so the only thing
    left to rank them by is scope — and first-in-the-chain is registration
    order, which puts used units ahead of the compiling scope's own routines.
    That silently made `program s; uses sysutils; function IntToStr(...)` call
    sysutils' version (bug-p-program-function-does-not-shadow-used-unit): the
    user's own function was compiled, called by nothing, and ignored.

    So among EXACT matches prefer one from the current scope. This is
    deliberately narrow — only this phase, where the candidates tie on
    everything else. The later compatible/lifting phases rank by argument fit,
    and a better-fitting routine should still win regardless of where it lives. }
  i := ProcChainHead(name);
  ownM := -1; anyM := -1;
  while i >= 0 do
  begin
    if MatchElig(i, name, demote, bIdx, userOnly, dropLateDef) then
    begin
      if ProcArityMatches(i, nArgs) then
      begin
        match := True;
        for j := 0 to nArgs-1 do
        begin
          if ((not MatchParamExact(Procs[i].Params[j].TypeKind, argTypes[j])) and
             not ProcParamUntyped[i * MAX_PROC_PARAMS + j]) or
             MatchArgRecMismatch(i, j, argTypes[j]) then
            match := False;
        end;
        if match then
        begin
          if anyM < 0 then anyM := i;
          if (ProcUnitIdx[i] = CurrentUnitIdx) and (ownM < 0) then ownM := i;
        end;
      end;
    end;
    i := ProcHashNext[i];
  end;
  if ownM >= 0 then begin Result := ownM; Exit; end;
  if anyM >= 0 then begin Result := anyM; Exit; end;

  { The literal-typed probe wants Phase 1 and nothing else: its argTypes carry a
    RE-TYPED integer literal (LiteralIntKind), which is a legitimate input to an
    exact match and a misleading one to every compatible phase below. Bail out
    with no match and no diagnostic; the caller then matches again on the real
    argument types. }
  if MatchExactOnly then begin Result := -1; Exit; end;

  { Phase 1b: Try exact match with return-lifting }
  i := ProcChainHead(name);
  while i >= 0 do
  begin
    if MatchElig(i, name, demote, bIdx, userOnly, dropLateDef) then
    begin
      if (Procs[i].ParamCount > nArgs) and (ProcParamPtrDepth[i * MAX_PROC_PARAMS + nArgs] = 2) then
      begin
        match := True;
        for j := 0 to nArgs-1 do
        begin
          if ((not MatchParamExact(Procs[i].Params[j].TypeKind, argTypes[j])) and
             not ProcParamUntyped[i * MAX_PROC_PARAMS + j]) or
             MatchArgRecMismatch(i, j, argTypes[j]) then
            match := False;
        end;
        if match then
        begin
          Result := i;
          Exit;
        end;
      end;
    end;
    i := ProcHashNext[i];
  end;

  { Phase 1c: a Char argument prefers a string-typed parameter over the ordinal
    (char -> integer) compatible match. A single-char literal types as tyChar,
    so without this an earlier f(integer) overload silently won f('x') even when
    an f(string) overload exists (FPC ranks a char literal as a string). Runs
    before the general compatible phase so the string overload wins regardless of
    declaration order; every other arg must still be an exact type match. }
  i := ProcChainHead(name);
  while i >= 0 do
  begin
    if MatchElig(i, name, demote, bIdx, userOnly, dropLateDef) and ProcArityMatches(i, nArgs) then
    begin
      match := True;
      for j := 0 to nArgs-1 do
      begin
        if (not ((Procs[i].Params[j].TypeKind = argTypes[j]) or
                ProcParamUntyped[i * MAX_PROC_PARAMS + j] or
                ((argTypes[j] = tyChar) and
                 ((Procs[i].Params[j].TypeKind = tyString) or
                  (Procs[i].Params[j].TypeKind = tyAnsiString))))) or
           MatchArgRecMismatch(i, j, argTypes[j]) then
          match := False;
      end;
      if match then
      begin
        Result := i;
        Exit;
      end;
    end;
    i := ProcHashNext[i];
  end;

  { Phase 1c1: a VARIANT argument prefers a VARIANT parameter. FPC's rule, and
    the one phase the ladder was missing: a Variant is TypesCompatible with
    every scalar parameter, so without this the compatible phases below bind
    whichever overload happens to be DECLARED FIRST and the exact Variant
    candidate is never reached.

    Measured against fpc 3.2.2 with overloads (Int64 | AnsiString | Double |
    Variant) and a Variant argument: FPC binds Variant, pxx bound Int64 — and
    then coerced, so a Variant holding 7.5 printed as 7 and one holding a
    string raised. It only stayed hidden because an all-exact call (a Variant
    argument AND an AnsiString spec) already won in Phase 1; the moment a
    second argument was merely compatible — a ShortString literal against an
    AnsiString parameter, which is what NilPy's f-string rewrite emits — the
    whole call fell through to Phase 1d and the first candidate took it.
    bug-a-a-variant-argument-binds-the-first-compatible-overload

    Every other argument must still be compatible, so this only REORDERS
    candidates that would all have matched below; it never makes a call match
    that did not. A Variant argument against an untyped parameter is neutral,
    as it is in every other phase. }
  variantArg := False;
  for j := 0 to nArgs-1 do
    if argTypes[j] = tyVariant then variantArg := True;
  if variantArg then
  begin
    i := ProcChainHead(name);
    while i >= 0 do
    begin
      if MatchElig(i, name, demote, bIdx, userOnly, dropLateDef) and
         ProcArityMatches(i, nArgs) then
      begin
        match := True;
        for j := 0 to nArgs-1 do
        begin
          if ProcParamUntyped[i * MAX_PROC_PARAMS + j] then
            { untyped: neutral }
          else if (argTypes[j] = tyVariant) and
                  (Procs[i].Params[j].TypeKind <> tyVariant) then
            match := False
          else if not MatchParamCompatible(i, j, argTypes[j]) then
            match := False;
          if MatchArgRecMismatch(i, j, argTypes[j]) then match := False;
        end;
        if match then
        begin
          Result := i;
          Exit;
        end;
      end;
      i := ProcHashNext[i];
    end;
  end;

  { Phase 1c2: an INTEGER-valued argument prefers an INTEGER parameter over a
    FLOAT one — FPC's rule, and a strong one: it holds even when the integer
    parameter NARROWS. Measured against fpc 3.2.2, `f(Integer)` vs `f(Double)`
    binds the Integer overload for an Int64 argument, and `f(Byte)` vs
    `f(Double)` binds Byte for an Integer argument. pxx had no such preference,
    so Phase 1d below — which ranks purely by losslessness — handed `f(n + 1)`
    to the Double overload and computed something entirely different, silently.

    Two passes, because losslessness still ranks WITHIN the integer candidates:
    a lossless integer parameter must beat a narrowing one (`f(Integer)` vs
    `f(Int64)` with an Int64 argument stays Int64), and only then does a
    narrowing integer parameter beat a float. Both run before Phase 1d, so an
    integer candidate outranks a float one either way.
    bug-a-an-integer-binop-argument-binds-a-double-overload }
  for pass := 0 to 1 do
  begin
    { --strict-overload-width: FPC picks the NARROWEST parameter that FITS,
      where pxx's default takes the first qualifying candidate in chain order
      and so lands on the widest. Both are "correct" — the widening is the
      dialect (user, 2026-08-14) — so the ranking is only collected under the
      flag and the unflagged walk below is byte-for-byte the old one.

      "Fits" is already decided by ArgNarrowsInt, which this phase's pass 0
      excludes: that is what makes `Cardinal` keep binding Int64 (LongInt
      cannot hold every Cardinal, so it narrows and is not a candidate at all),
      which is the row that proves FPC's rule is narrowest-that-FITS rather
      than narrowest-declared.
      compat-pascal-strict-fpc-should-pick-the-narrowest-integer-overload }
    bestW := -1;
    bestI := -1;
    i := ProcChainHead(name);
    while i >= 0 do
    begin
      if MatchElig(i, name, demote, bIdx, userOnly, dropLateDef) and
         ProcArityMatches(i, nArgs) then
      begin
        match := False;   { at least one argument must be the int->int case }
        for j := 0 to nArgs-1 do
        begin
          if ProcParamUntyped[i * MAX_PROC_PARAMS + j] then
            { untyped: neutral }
          else if TypeIsMachineInt(argTypes[j]) and
                  TypeIsMachineInt(Procs[i].Params[j].TypeKind) and
                  MatchParamCompatible(i, j, argTypes[j]) and
                  ((pass = 1) or
                   not ArgNarrowsInt(Procs[i].Params[j].TypeKind, argTypes[j])) then
            match := True
          else if (Procs[i].Params[j].TypeKind = argTypes[j]) and
                  not MatchArgRecMismatch(i, j, argTypes[j]) then
            { some other argument matching exactly is fine }
          else
          begin
            match := False;
            Break;
          end;
          if MatchArgRecMismatch(i, j, argTypes[j]) then
          begin
            match := False;
            Break;
          end;
        end;
        if match then
        begin
          if not StrictOverloadWidth then
          begin
            Result := i;
            Exit;
          end;
          { rank by total declared width of the INTEGER parameters, narrowest
            first; chain order breaks a tie, so a single candidate and an
            all-equal set both behave exactly as before. A candidate that
            cannot hold every value of its argument is not ranked at all — it
            is still reachable through the ordinary phases below, which is what
            keeps a narrowing candidate winning when it is the only one. }
          w := 0;
          fits := True;
          for j := 0 to nArgs-1 do
            if (not ProcParamUntyped[i * MAX_PROC_PARAMS + j]) and
               TypeIsMachineInt(Procs[i].Params[j].TypeKind) then
            begin
              if TypeIsMachineInt(argTypes[j]) and
                 not IntParamHoldsEveryValue(Procs[i].Params[j].TypeKind, argTypes[j]) then
                fits := False;
              Inc(w, TypeSize(Procs[i].Params[j].TypeKind));
            end;
          if fits and ((bestI < 0) or (w < bestW)) then
          begin
            bestW := w;
            bestI := i;
          end;
        end;
      end;
      i := ProcHashNext[i];
    end;
    if bestI >= 0 then
    begin
      Result := bestI;
      Exit;
    end;
  end;

  { Phase 1d: compatible match that does NOT narrow an integer argument. Runs
    before the general compatible phase so a lossless candidate beats a
    truncating one whatever the declaration order — see ArgNarrowsInt. }
  i := ProcChainHead(name);
  while i >= 0 do
  begin
    if MatchElig(i, name, demote, bIdx, userOnly, dropLateDef) then
    begin
      if ProcArityMatches(i, nArgs) then
      begin
        match := True;
        for j := 0 to nArgs-1 do
        begin
          if (not (MatchParamCompatible(i, j, argTypes[j]) or
                  ProcParamUntyped[i * MAX_PROC_PARAMS + j])) or
             MatchArgRecMismatch(i, j, argTypes[j]) or
             (ArgNarrowsInt(Procs[i].Params[j].TypeKind, argTypes[j]) and
              not ProcParamUntyped[i * MAX_PROC_PARAMS + j]) then
            match := False;
        end;
        if match then
        begin
          Result := i;
          Exit;
        end;
      end;
    end;
    i := ProcHashNext[i];
  end;

  { Phase 2: Try compatible match }
  i := ProcChainHead(name);
  while i >= 0 do
  begin
    if MatchElig(i, name, demote, bIdx, userOnly, dropLateDef) then
    begin
      if ProcArityMatches(i, nArgs) then
      begin
        match := True;
        for j := 0 to nArgs-1 do
        begin
          if (not (MatchParamCompatible(i, j, argTypes[j]) or
                  ProcParamUntyped[i * MAX_PROC_PARAMS + j])) or
             MatchArgRecMismatch(i, j, argTypes[j]) then
            match := False;
        end;
        if match then
        begin
          Result := i;
          Exit;
        end;
      end;
    end;
    i := ProcHashNext[i];
  end;

  { Phase 2b: Try compatible match with return-lifting }
  i := ProcChainHead(name);
  while i >= 0 do
  begin
    if MatchElig(i, name, demote, bIdx, userOnly, dropLateDef) then
    begin
      if (Procs[i].ParamCount > nArgs) and (ProcParamPtrDepth[i * MAX_PROC_PARAMS + nArgs] = 2) then
      begin
        match := True;
        for j := 0 to nArgs-1 do
        begin
          if (not (MatchParamCompatible(i, j, argTypes[j]) or
                  ProcParamUntyped[i * MAX_PROC_PARAMS + j])) or
             MatchArgRecMismatch(i, j, argTypes[j]) then
            match := False;
        end;
        if match then
        begin
          Result := i;
          Exit;
        end;
      end;
    end;
    i := ProcHashNext[i];
  end;

  { Phase 2c: a class argument given to an interface parameter (the implicit
    class->interface coercion). Only fires when the param is a CORBA interface,
    so existing record/class overloads are unaffected. }
  i := ProcChainHead(name);
  while i >= 0 do
  begin
    if MatchElig(i, name, demote, bIdx, userOnly, dropLateDef) and ProcArityMatches(i, nArgs) then
    begin
      match := True;
      for j := 0 to nArgs-1 do
      begin
        if (not (MatchParamCompatible(i, j, argTypes[j]) or
                (ProcParamIsInterface(i, j) and (argTypes[j] = tyClass)) or
                ProcParamUntyped[i * MAX_PROC_PARAMS + j])) or
           MatchArgRecMismatch(i, j, argTypes[j]) then
          match := False;
      end;
      if match then
      begin
        Result := i;
        Exit;
      end;
    end;
    i := ProcHashNext[i];
  end;

  { Record the candidate set for the caller's diagnostic rather than writing it
    to stdout here: this used to print symbol indices and raw TTypeKind ORDINALS
    ahead of the actual error line, which read as leaked debug output and told a
    user nothing actionable (bug-overload-mismatch-dumps-internals-to-stdout).
    Type names, and the caller appends it after its own message. }
  OverloadReport := '';
  if not MatchQuiet then
  begin
    nl := '';
    AppendChar(nl, Chr(10));
    OverloadReport := nl + '  argument types: (';
    for j := 0 to nArgs-1 do
    begin
      if j > 0 then OverloadReport := OverloadReport + ', ';
      OverloadReport := OverloadReport + TypeKindSpelling(argTypes[j]);
    end;
    OverloadReport := OverloadReport + ')' + nl + '  candidates:';
    i := ProcChainHead(name);
    while i >= 0 do
    begin
      if MatchElig(i, name, demote, bIdx, userOnly, dropLateDef) then
      begin
        OverloadReport := OverloadReport + nl + '    ' + name + '(';
        for j := 0 to Procs[i].ParamCount-1 do
        begin
          if j > 0 then OverloadReport := OverloadReport + ', ';
          OverloadReport := OverloadReport + TypeKindSpelling(Procs[i].Params[j].TypeKind);
        end;
        OverloadReport := OverloadReport + ')';
      end;
      i := ProcHashNext[i];
    end;
  end;

  Result := -1;
end;

function MatchProcCallInUnit(const name: AnsiString; unitIdx, nArgs: Integer;
  const argTypes: array of TTypeKind): Integer;
var i, j: Integer; match: Boolean;
begin
  for i := 0 to ProcCount - 1 do
    if (ProcUnitIdx[i] = unitIdx) and
       ((Procs[i].Name = name) or
        ((not ProcCaseSensitive[i]) and CaseEqual(Procs[i].Name, name))) and
       (Procs[i].ParamCount = nArgs) then
    begin
      match := True;
      for j := 0 to nArgs - 1 do
        if ((Procs[i].Params[j].TypeKind <> argTypes[j]) and not ProcParamUntyped[i * MAX_PROC_PARAMS + j]) or MatchArgRecMismatch(i, j, argTypes[j]) then match := False;
      if match then
      begin
        Result := i;
        Exit;
      end;
    end;

  if MatchExactOnly then begin Result := -1; Exit; end;   { see MatchProcCall }

  { Phase 1b: Try exact match with return-lifting }
  for i := 0 to ProcCount - 1 do
    if (ProcUnitIdx[i] = unitIdx) and
       ((Procs[i].Name = name) or
        ((not ProcCaseSensitive[i]) and CaseEqual(Procs[i].Name, name))) and
       (Procs[i].ParamCount > nArgs) and
       (ProcParamPtrDepth[i * MAX_PROC_PARAMS + nArgs] = 2) then
    begin
      match := True;
      for j := 0 to nArgs - 1 do
        if ((Procs[i].Params[j].TypeKind <> argTypes[j]) and not ProcParamUntyped[i * MAX_PROC_PARAMS + j]) or MatchArgRecMismatch(i, j, argTypes[j]) then match := False;
      if match then
      begin
        Result := i;
        Exit;
      end;
    end;

  for i := 0 to ProcCount - 1 do
    if (ProcUnitIdx[i] = unitIdx) and
       ((Procs[i].Name = name) or
        ((not ProcCaseSensitive[i]) and CaseEqual(Procs[i].Name, name))) and
       (Procs[i].ParamCount = nArgs) then
    begin
      match := True;
      for j := 0 to nArgs - 1 do
        if (not (MatchParamCompatible(i, j, argTypes[j]) or ProcParamUntyped[i * MAX_PROC_PARAMS + j])) or MatchArgRecMismatch(i, j, argTypes[j]) then match := False;
      if match then
      begin
        Result := i;
        Exit;
      end;
    end;

  { Phase 2b: Try compatible match with return-lifting }
  for i := 0 to ProcCount - 1 do
    if (ProcUnitIdx[i] = unitIdx) and
       ((Procs[i].Name = name) or
        ((not ProcCaseSensitive[i]) and CaseEqual(Procs[i].Name, name))) and
       (Procs[i].ParamCount > nArgs) and
       (ProcParamPtrDepth[i * MAX_PROC_PARAMS + nArgs] = 2) then
    begin
      match := True;
      for j := 0 to nArgs - 1 do
        if (not (MatchParamCompatible(i, j, argTypes[j]) or ProcParamUntyped[i * MAX_PROC_PARAMS + j])) or MatchArgRecMismatch(i, j, argTypes[j]) then match := False;
      if match then
      begin
        Result := i;
        Exit;
      end;
    end;

  Result := -1;
end;


{ Grow the 90 parallel per-ROUTINE tables so index `need-1` is in bounds.

  One chokepoint (RegisterProc) because there is one: every Proc*/ProcParam*
  array is written there for the routine being registered, and nothing else
  appends. The families grow in LOCKSTEP -- the per-proc ones to n, the
  per-parameter ones to n*MAX_PROC_PARAMS, the capture/inline-local ones to
  their own stride -- because a missed one is a silent out-of-bounds, not an
  error. The list is generated from the declarations in defs.inc rather than
  typed out, for the same reason.

  `Procs` itself stays a fixed array[0..MAX_PROCS-1]: it is an array of RECORDS
  holding managed strings, which is a different (and much less proven) SetLength
  path than these scalar tables, and keeping it fixed keeps MAX_PROCS a real
  bound on everything here. That conversion is its own step.

  Costs measured: 38 MB of BSS reservation, the largest remaining family in the
  compiler after the token/sym/AST/IR conversions. feature-dynamic-compiler-tables }
procedure EnsureProcCapacity(need: Integer);
var n: Integer;
begin
  if need <= ProcCapacity then Exit;
  if ProcCapacity = 0 then n := 128 else n := ProcCapacity;
  while n < need do n := n * 2;
  if n > MAX_PROCS then n := MAX_PROCS;
  SetLength(ProcBodyIRNodes, n);  SetLength(ProcBodyMakesCall, n);  SetLength(ProcBodyEarlyExit, n);
  SetLength(ProcBodyAddrTakenParam, n);  SetLength(ProcBodyCompiled, n);  SetLength(InlineCallSites, n);
  SetLength(ProcInline, n);  SetLength(InlineBodyRoot, n);  SetLength(InlineParamCnt, n);
  SetLength(InlineBodyIsStmt, n);  SetLength(InlineLocalCnt, n);  SetLength(InlineBodyHasCall, n);
  SetLength(ProcFrameSensitive, n);  SetLength(DceLive, n);  SetLength(DceWork, n);
  SetLength(DceOrder, n);  SetLength(DceLimit, n);  SetLength(DceRemStart, n);
  SetLength(DceRemEnd, n);  SetLength(ProcHashNext, n);  SetLength(ProcOverloadDirective, n);
  SetLength(ProcFlexColumn, n);  SetLength(ProcExternal, n);  SetLength(ProcCModule, n);
  SetLength(ProcCaseSensitive, n);  SetLength(ProcLibrary, n);  SetLength(ProcExtName, n);
  SetLength(ProcCdecl, n);  SetLength(ProcVariadic, n);  SetLength(ProcNamedGP, n);
  SetLength(ProcNamedFP, n);  SetLength(ProcUnitIdx, n);  SetLength(ProcPyDefTok, n);
  SetLength(ProcHdrTok, n);  SetLength(ProcRetRecId, n);  SetLength(ProcAggregateDestSym, n);
  SetLength(ProcRetIsDynArray, n);  SetLength(ProcRetFixedArrBytes, n);  SetLength(ProcRetArrAi, n);
  SetLength(ProcIsAsync, n);  SetLength(ProcIsGenerator, n);  SetLength(ProcIsStackless, n);
  SetLength(ProcIram, n);  SetLength(ProcIsInterrupt, n);  SetLength(ProcBodyEnd, n);
  SetLength(ProcDbgMain, n);  SetLength(ProcGenElemTk, n);  SetLength(ProcGenElemRec, n);
  SetLength(ProcGenParamCnt, n);  SetLength(ProcGenInstSize, n);  SetLength(ProcRetElemTk, n);
  SetLength(ProcRetElemRec, n);  SetLength(ProcRetPtrElemTk, n);  SetLength(ProcRetProcSig, n);
  SetLength(CProcHasLocalDef, n);  SetLength(ProcRetPtrElemRec, n);  SetLength(PyCapCount, n);
  SetLength(PyDefTokOf, n);  SetLength(ProcPyStarIdx, n);  SetLength(ProcPyKwIdx, n);
  SetLength(ProcSigOff, n);  SetLength(ProcSigDfltOff, n);  SetLength(ObjProcStrOff, n);
  SetLength(ObjProcSymIdx, n);  SetLength(ObjProcIramOff, n);
  SetLength(InlineLocalTk, n*MAX_INLINE_LOCALS);
  SetLength(DceEdgeHead, n+1);
  SetLength(ProcParamPtrDepth, n*MAX_PROC_PARAMS);  SetLength(ProcParamRecId, n*MAX_PROC_PARAMS);  SetLength(ProcParamSetEnumId, n*MAX_PROC_PARAMS);
  SetLength(ProcParamDynDepth, n*MAX_PROC_PARAMS);  SetLength(ProcParamIsConst, n*MAX_PROC_PARAMS);  SetLength(ProcParamExplicitByRef, n*MAX_PROC_PARAMS);
  SetLength(ProcParamCapRef, n*MAX_PROC_PARAMS);  SetLength(ProcParamProcSig, n*MAX_PROC_PARAMS);  SetLength(ProcParamUntyped, n*MAX_PROC_PARAMS);
  SetLength(ProcParamHasDefault, n*MAX_PROC_PARAMS);  SetLength(ProcParamElemRowLen, n*MAX_PROC_PARAMS);  SetLength(ProcParamElemRowLo, n*MAX_PROC_PARAMS);
  SetLength(ProcParamDefaultVal, n*MAX_PROC_PARAMS);  SetLength(ProcParamDefaultIsStr, n*MAX_PROC_PARAMS);  SetLength(ProcParamDefaultIsNone, n*MAX_PROC_PARAMS);
  SetLength(ProcParamDefaultIsFloat, n*MAX_PROC_PARAMS);  SetLength(ProcParamDefaultIsBool, n*MAX_PROC_PARAMS);  SetLength(ProcParamDefaultSym, n*MAX_PROC_PARAMS);
  SetLength(ProcParamDefaultGName, n*MAX_PROC_PARAMS);  SetLength(ProcParamDefaultIsSet, n*MAX_PROC_PARAMS);  SetLength(ProcParamDefaultSOff, n*MAX_PROC_PARAMS);
  SetLength(ProcParamDefaultSLen, n*MAX_PROC_PARAMS);
  SetLength(PyCapName, n*PY_MAX_CAPS);
  ProcCapacity := n;
end;

function RegisterProc(const name: AnsiString; isFunc: Boolean;
  retType: TTypeKind; nParams: Integer;
  const pnames: array of AnsiString; const ptypes: array of TTypeKind): Integer;
var i: Integer;
begin
  if ProcCount >= MAX_PROCS then Error('too many procedures');
  if nParams > MAX_PROC_PARAMS then Error('too many procedure parameters');
  EnsureProcCapacity(ProcCount + 1);
  Procs[ProcCount].Name       := name;
  ProcHashInsert(ProcCount);
  Procs[ProcCount].IsFunc     := isFunc;
  Procs[ProcCount].RetType    := retType;
  Procs[ProcCount].ParamCount := nParams;
  Procs[ProcCount].BodyAddr   := -1;
  Procs[ProcCount].FramePatch := -1;
  Procs[ProcCount].RetSymIdx  := -1;
  Procs[ProcCount].ScopeBase  := 0;
  ProcExternal[ProcCount]     := False;
  ProcCaseSensitive[ProcCount] := DeclCaseSensitive;
  ProcOverloadDirective[ProcCount] := False;
  ProcFlexColumn[ProcCount]   := False;
  ProcLibrary[ProcCount]      := -1;
  ProcExtName[ProcCount]      := -1;
  ProcCdecl[ProcCount]        := False;
  ProcUnitIdx[ProcCount]      := CurrentUnitIdx;
  ProcPyDefTok[ProcCount]     := 0;   { 0 = visible everywhere; see defs.inc }
  ProcHdrTok[ProcCount]       := 0;   { 0 = always visible; ParseSubroutine stamps main-program headers }
  ProcRetRecId[ProcCount]     := REC_NONE;
  ProcAggregateDestSym[ProcCount] := -1;
  ProcRetIsDynArray[ProcCount] := False;
  { -1, not 0: zero is a VALID ArrType index, so a proc that never sets this
    would claim to return the FIRST array type declared in the program. }
  ProcRetArrAi[ProcCount] := -1;
  ProcRetElemTk[ProcCount]     := tyUnknown;
  ProcRetElemRec[ProcCount]    := REC_NONE;
  ProcRetPtrElemTk[ProcCount]  := Ord(tyUnknown);
  ProcRetPtrElemRec[ProcCount] := REC_NONE;
  ProcRetProcSig[ProcCount]    := -1;
  CProcHasLocalDef[ProcCount]  := False;
  ProcInline[ProcCount]        := False;
  InlineBodyRoot[ProcCount]    := -1;
  InlineParamCnt[ProcCount]    := 0;
  InlineBodyIsStmt[ProcCount]  := False;
  InlineBodyHasCall[ProcCount] := False;
  ProcFrameSensitive[ProcCount] := False;
  InlineLocalCnt[ProcCount]    := 0;
  ProcPyStarIdx[ProcCount]     := -1;
  ProcPyKwIdx[ProcCount]       := -1;
  for i := 0 to MAX_PROC_PARAMS - 1 do
  begin
    ProcParamPtrDepth[ProcCount * MAX_PROC_PARAMS + i] := 0;
    ProcParamIsConst[ProcCount * MAX_PROC_PARAMS + i] := False;
    ProcParamCapRef[ProcCount * MAX_PROC_PARAMS + i] := False;
    ProcParamExplicitByRef[ProcCount * MAX_PROC_PARAMS + i] := False;
    ProcParamUntyped[ProcCount * MAX_PROC_PARAMS + i] := False;
    ProcParamHasDefault[ProcCount * MAX_PROC_PARAMS + i] := False;
    ProcParamDefaultVal[ProcCount * MAX_PROC_PARAMS + i] := 0;
    ProcParamDefaultIsStr[ProcCount * MAX_PROC_PARAMS + i] := False;
    ProcParamDefaultIsNone[ProcCount * MAX_PROC_PARAMS + i] := False;
    ProcParamDefaultIsFloat[ProcCount * MAX_PROC_PARAMS + i] := False;
    ProcParamDefaultSOff[ProcCount * MAX_PROC_PARAMS + i] := 0;
    ProcParamDefaultSLen[ProcCount * MAX_PROC_PARAMS + i] := 0;
    ProcParamDefaultSym[ProcCount * MAX_PROC_PARAMS + i] := -1;
    ProcParamDefaultIsBool[ProcCount * MAX_PROC_PARAMS + i] := False;
    ProcParamRecId[ProcCount * MAX_PROC_PARAMS + i] := REC_NONE;
    ProcParamSetEnumId[ProcCount * MAX_PROC_PARAMS + i] := -1;
    ProcParamDynDepth[ProcCount * MAX_PROC_PARAMS + i] := 0;
    ProcParamElemRowLen[ProcCount * MAX_PROC_PARAMS + i] := 0;
    ProcParamElemRowLo[ProcCount * MAX_PROC_PARAMS + i] := 0;
  end;
  for i := 0 to nParams-1 do
  begin
    Procs[ProcCount].Params[i].Name     := pnames[i];
    Procs[ProcCount].Params[i].TypeKind := ptypes[i];
    Procs[ProcCount].Params[i].SymIdx   := -1;
    ProcParamProcSig[ProcCount * MAX_PROC_PARAMS + i] := -1;   { not proc-typed unless the frontend says so }
    Procs[ProcCount].Params[i].IsArray  := False;
    { C struct-by-value params use the by-ref ABI (an 8-byte pointer slot the
      callee derefs; the caller copies to a temp and passes &temp — see cparser
      AllocParam and ir.inc IRLowerCallArg). The proc's Params[].IsRef must agree
      so the CALLER marshals it as one pointer word, not a 2-word by-value record
      (which pushed a stale second word -> a NULL 2nd struct arg on arm32/riscv32).
      C-mode-gated so Pascal proc registration stays byte-identical. }
    Procs[ProcCount].Params[i].IsRef    := CProgramMode and (ptypes[i] = tyRecord);
  end;
  Result := ProcCount; Inc(ProcCount);
end;

{ The __pxx_run_finalizers shell every exit path calls (main-body fall-off and
  every Halt site). Registered lazily — a Halt can lower before all units are
  parsed, so the shell is a forward call resolved by ApplyCallFixups; the body
  (unit finalizers in reverse init order, behind a run-once BSS guard) is
  emitted by EmitFinalizerRunnerBody in pasparser_proc.inc
  (bug-unit-finalization-not-executed). }
function GetFiniRunnerProc: Integer;
var dummyNames: array[0..0] of AnsiString;
    dummyTypes: array[0..0] of TTypeKind;
begin
  if FiniRunnerProc < 0 then
    FiniRunnerProc := RegisterProc('__pxx_run_finalizers', False, tyInteger, 0,
                                   dummyNames, dummyTypes);
  Result := FiniRunnerProc;
end;

{ ===== int-to-string write ===== }

procedure EmitwriteInt;
var jnsOff, loopStart: Integer;
begin
  EmitB($48); EmitB($85); EmitB($C0);
  EmitB($79); jnsOff := CodeLen; EmitB(0);
  EmitB($48); EmitB($F7); EmitB($D8);
  EmitB($50);
  EmitwriteSyscall(MINUS_OFFSET, 1);
  EmitB($58);
  Code[jnsOff] := Byte(CodeLen - (jnsOff + 1));
  EmitB($48); EmitB($31); EmitB($C9);
  MovRbxImm(10);
  EmitB($48); EmitB($BF); EmitDataRef(INTBUF_OFFSET + INTBUF_SIZE);
  loopStart := CodeLen;
  EmitB($48); EmitB($31); EmitB($D2);
  EmitB($48); EmitB($F7); EmitB($F3);
  EmitB($80); EmitB($C2); EmitB($30);
  EmitB($48); EmitB($FF); EmitB($CF);
  EmitB($88); EmitB($17);
  EmitB($48); EmitB($FF); EmitB($C1);
  EmitB($48); EmitB($85); EmitB($C0);
  EmitB($75); EmitB(Byte(loopStart - (CodeLen + 1)));
  EmitB($48); EmitB($89); EmitB($FE);
  EmitB($48); EmitB($89); EmitB($CA);
  MovRaxImm(SYS_WRITE); MovRdiImm(CurWriteFd); EmitSyscall;
end;

procedure EmitwriteUInt;
var loopStart: Integer;
begin
  EmitB($48); EmitB($31); EmitB($C9);
  MovRbxImm(10);
  EmitB($48); EmitB($BF); EmitDataRef(INTBUF_OFFSET + INTBUF_SIZE);
  loopStart := CodeLen;
  EmitB($48); EmitB($31); EmitB($D2);
  EmitB($48); EmitB($F7); EmitB($F3);
  EmitB($80); EmitB($C2); EmitB($30);
  EmitB($48); EmitB($FF); EmitB($CF);
  EmitB($88); EmitB($17);
  EmitB($48); EmitB($FF); EmitB($C1);
  EmitB($48); EmitB($85); EmitB($C0);
  EmitB($75); EmitB(Byte(loopStart - (CodeLen + 1)));
  EmitB($48); EmitB($89); EmitB($FE);
  EmitB($48); EmitB($89); EmitB($CA);
  MovRaxImm(SYS_WRITE); MovRdiImm(CurWriteFd); EmitSyscall;
end;

procedure EmitwriteChar;
{ rax = char byte value → write 1 byte to stdout }
begin
  EmitB($48); EmitB($BE); EmitDataRef(INTBUF_OFFSET);
  EmitB($88); EmitB($06);
  MovRaxImm(SYS_WRITE); MovRdiImm(CurWriteFd); MovRdxImm(1); EmitSyscall;
end;

procedure EnsureSpaces;
var j: Integer;
begin
  if SpacesOffset >= 0 then Exit;
  SpacesOffset := DataLen;
  for j := 0 to SPACES_SIZE - 1 do Data[DataLen + j] := $20;
  Inc(DataLen, SPACES_SIZE);
end;

procedure EmitwriteIntW(width: Integer);
{ rax = signed int → right-aligned in field of min width chars }
var jnsOff, jleOff, jzOff, loopStart: Integer;
begin
  { r8 = sign flag (0=positive, 1=negative) }
  EmitB($4D); EmitB($31); EmitB($C0);                    { xor r8, r8 }
  EmitB($48); EmitB($85); EmitB($C0);                    { test rax, rax }
  EmitB($79); jnsOff := CodeLen; EmitB(0);               { jns .positive }
  EmitB($48); EmitB($F7); EmitB($D8);                    { neg rax }
  EmitB($49); EmitB($FF); EmitB($C0);                    { inc r8 }
  Code[jnsOff] := Byte(CodeLen - (jnsOff + 1));
  { Digit conversion into INTBUF from end }
  EmitB($48); EmitB($31); EmitB($C9);                    { xor rcx, rcx }
  MovRbxImm(10);
  EmitB($48); EmitB($BF); EmitDataRef(INTBUF_OFFSET + INTBUF_SIZE);
  loopStart := CodeLen;
  EmitB($48); EmitB($31); EmitB($D2);                    { xor rdx, rdx }
  EmitB($48); EmitB($F7); EmitB($F3);                    { div rbx }
  EmitB($80); EmitB($C2); EmitB($30);                    { add dl, '0' }
  EmitB($48); EmitB($FF); EmitB($CF);                    { dec rdi }
  EmitB($88); EmitB($17);                                { mov [rdi], dl }
  EmitB($48); EmitB($FF); EmitB($C1);                    { inc rcx }
  EmitB($48); EmitB($85); EmitB($C0);                    { test rax, rax }
  EmitB($75); EmitB(Byte(loopStart - (CodeLen + 1)));    { jnz loop }
  { Save digit start/count; compute padding = width - digits - sign }
  EmitB($57);                                            { push rdi }
  EmitB($51);                                            { push rcx }
  MovRaxImm(width);
  EmitB($48); EmitB($29); EmitB($C8);                    { sub rax, rcx }
  EmitB($4C); EmitB($29); EmitB($C0);                    { sub rax, r8 }
  EmitB($7E); jleOff := CodeLen; EmitB(0);               { jle .no_pad }
  EnsureSpaces;
  EmitB($48); EmitB($BE); EmitDataRef(SpacesOffset);    { mov rsi, spaces }
  EmitB($48); EmitB($89); EmitB($C2);                    { mov rdx, rax }
  MovRaxImm(SYS_WRITE); MovRdiImm(CurWriteFd); EmitSyscall;
  Code[jleOff] := Byte(CodeLen - (jleOff + 1));
  { Write sign if negative }
  EmitB($4D); EmitB($85); EmitB($C0);                    { test r8, r8 }
  EmitB($74); jzOff := CodeLen; EmitB(0);                { jz .no_sign }
  EmitwriteSyscall(MINUS_OFFSET, 1);
  Code[jzOff] := Byte(CodeLen - (jzOff + 1));
  { Write digits }
  EmitB($5A);                                            { pop rdx }
  EmitB($5E);                                            { pop rsi }
  MovRaxImm(SYS_WRITE); MovRdiImm(CurWriteFd); EmitSyscall;
end;

procedure EmitwriteUIntW(width: Integer);
{ rax = unsigned int → right-aligned in field of min width chars }
var jleOff, loopStart: Integer;
begin
  EmitB($48); EmitB($31); EmitB($C9);                    { xor rcx, rcx }
  MovRbxImm(10);
  EmitB($48); EmitB($BF); EmitDataRef(INTBUF_OFFSET + INTBUF_SIZE);
  loopStart := CodeLen;
  EmitB($48); EmitB($31); EmitB($D2);                    { xor rdx, rdx }
  EmitB($48); EmitB($F7); EmitB($F3);                    { div rbx }
  EmitB($80); EmitB($C2); EmitB($30);                    { add dl, '0' }
  EmitB($48); EmitB($FF); EmitB($CF);                    { dec rdi }
  EmitB($88); EmitB($17);                                { mov [rdi], dl }
  EmitB($48); EmitB($FF); EmitB($C1);                    { inc rcx }
  EmitB($48); EmitB($85); EmitB($C0);                    { test rax, rax }
  EmitB($75); EmitB(Byte(loopStart - (CodeLen + 1)));    { jnz loop }
  EmitB($57);                                            { push rdi }
  EmitB($51);                                            { push rcx }
  MovRaxImm(width);
  EmitB($48); EmitB($29); EmitB($C8);                    { sub rax, rcx }
  EmitB($7E); jleOff := CodeLen; EmitB(0);               { jle .no_pad }
  EnsureSpaces;
  EmitB($48); EmitB($BE); EmitDataRef(SpacesOffset);
  EmitB($48); EmitB($89); EmitB($C2);                    { mov rdx, rax }
  MovRaxImm(SYS_WRITE); MovRdiImm(CurWriteFd); EmitSyscall;
  Code[jleOff] := Byte(CodeLen - (jleOff + 1));
  EmitB($5A);                                            { pop rdx }
  EmitB($5E);                                            { pop rsi }
  MovRaxImm(SYS_WRITE); MovRdiImm(CurWriteFd); EmitSyscall;
end;

procedure EmitWriteFloatNat;
{ Double in xmm0. Python-style natural decimal: [-]int.frac with trailing zeros
  trimmed but at least one fractional digit (so 5.0 prints "5.0"). Integer part
  is printed via the integer writer (no scaling overflow); the fractional part is
  (value - trunc)*1e15 rounded to an Int64, emitted most-significant-first and
  stopped once the remainder reaches zero. frac kept in r13 across the syscalls. }
const FRAC = 15;
var jncOff, jbCarry, i, k, nJz: Integer;
    endJz: array[0..FRAC-1] of Integer;
    divisor, scale: Int64;
begin
  scale := 1;
  for k := 1 to FRAC do scale := scale * 10;                   { 10^15 }

  EmitB($41); EmitB($55);                                       { push r13 }

  { sign: strip and print '-' }
  EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0);   { movq rax, xmm0 }
  EmitB($48); EmitB($0F); EmitB($BA); EmitB($E0); EmitB($3F);   { bt rax, 63 }
  EmitB($73); jncOff := CodeLen; EmitB(0);                      { jnc .pos }
  EmitB($48); EmitB($0F); EmitB($BA); EmitB($F0); EmitB($3F);   { btr rax, 63 }
  EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C0);   { movq xmm0, rax }
  MovRaxImm(Ord('-')); EmitwriteChar;
  Code[jncOff] := Byte(CodeLen - (jncOff + 1));                 { .pos: }

  { intpart = trunc(value) -> rax ; frac double = value - intpart }
  EmitB($F2); EmitB($48); EmitB($0F); EmitB($2C); EmitB($C0);   { cvttsd2si rax, xmm0 }
  EmitB($F2); EmitB($48); EmitB($0F); EmitB($2A); EmitB($D8);   { cvtsi2sd xmm3, rax }
  EmitB($F2); EmitB($0F); EmitB($5C); EmitB($C3);               { subsd xmm0, xmm3 }
  { frac *= scale ; round -> rbx }
  EmitB($48); EmitB($B9); EmitI64(scale);                       { mov rcx, scale }
  EmitB($F2); EmitB($48); EmitB($0F); EmitB($2A); EmitB($C9);   { cvtsi2sd xmm1, rcx }
  EmitB($F2); EmitB($0F); EmitB($59); EmitB($C1);               { mulsd xmm0, xmm1 }
  EmitB($F2); EmitB($48); EmitB($0F); EmitB($2D); EmitB($D8);   { cvtsd2si rbx, xmm0 }
  { carry: if rbx >= scale (frac rounded up to 1.0): rbx -= scale; intpart++ }
  EmitB($49); EmitB($B8); EmitI64(scale);                       { mov r8, scale }
  EmitB($4C); EmitB($39); EmitB($C3);                           { cmp rbx, r8 }
  EmitB($72); jbCarry := CodeLen; EmitB(0);                     { jb .nocarry }
  EmitB($4C); EmitB($29); EmitB($C3);                           { sub rbx, r8 }
  EmitB($48); EmitB($FF); EmitB($C0);                           { inc rax }
  Code[jbCarry] := Byte(CodeLen - (jbCarry + 1));               { .nocarry: }
  EmitB($49); EmitB($89); EmitB($DD);                           { mov r13, rbx (frac) }

  { print intpart (non-negative) then '.' }
  EmitwriteUInt;
  MovRaxImm(Ord('.')); EmitwriteChar;

  { frac digits MSD-first, stop after the remainder hits 0 (>=1 digit always) }
  nJz := 0;
  for i := 0 to FRAC - 1 do
  begin
    divisor := 1;
    for k := 1 to (FRAC - 1 - i) do divisor := divisor * 10;     { 10^(FRAC-1-i) }
    EmitB($4C); EmitB($89); EmitB($E8);                          { mov rax, r13 }
    EmitB($48); EmitB($31); EmitB($D2);                          { xor rdx, rdx }
    EmitB($48); EmitB($B9); EmitI64(divisor);                    { mov rcx, divisor }
    EmitB($48); EmitB($F7); EmitB($F1);                          { div rcx -> rax=digit, rdx=rem }
    EmitB($49); EmitB($89); EmitB($D5);                          { mov r13, rdx (remainder) }
    EmitB($48); EmitB($83); EmitB($C0); EmitB($30);             { add rax, '0' }
    EmitwriteChar;
    if i < FRAC - 1 then
    begin
      EmitB($4D); EmitB($85); EmitB($ED);                        { test r13, r13 }
      EmitB($0F); EmitB($84); endJz[nJz] := CodeLen; EmitI32(0); { jz .end }
      Inc(nJz);
    end;
  end;

  { .end: }
  for k := 0 to nJz - 1 do
    Patch32(endJz[k], CodeLen - (endJz[k] + 4));
  EmitB($41); EmitB($5D);                                        { pop r13 }
end;

procedure EmitWriteFloatFixedNative(width, decimals: Integer); forward;

procedure EmitWriteFloatFixed(width, decimals: Integer);
{ Double value in xmm0 -> [-]intpart.frac with `decimals` fractional digits,
  right-justified in `width` columns. A shim onto the runtime PXXWriteFloatFixed.

  The hand-written native emitter this replaces scaled the integer part through
  Int64 — exact only for |v| < 2^63, as its own header said — so
  writeln(1e20:0:2) printed 9223372036854775809.00, the saturation value
  (bug-a-x86-64-writeln-fixed-saturates-at-int64). It survived one more round
  only because the runtime helper had no field-width parameter and shimming
  would have dropped padding; the helper now takes one
  (bug-a-aarch64-float-field-width-ignored), so the last hand-written float
  formatter on this target is gone. x86-64 now has none. }
var procIdx: Integer;
begin
  procIdx := FindProc('PXXWriteFloatFixed');
  if procIdx < 0 then
  begin
    EmitWriteFloatFixedNative(width, decimals);
    Exit;
  end;
  EmitAsmX64([
    'sub rsp, 16',
    'movsd [rsp], xmm0',
    'mov rdi, rsp',
    'mov rsi, %', decimals,
    'mov rdx, %', width
  ]);
  EmitCallProc(procIdx);
  EmitAsmX64(['add rsp, 16']);
end;

procedure EmitWriteFloatFixedNative(width, decimals: Integer);
{ Double value in xmm0. Prints [-]intpart.frac with exactly 'decimals'
  fractional digits (decimals=0 -> rounded integer, no point), right-justified in
  a field of `width` columns (width<=0 = no padding). Reuses the integer
  printers, so all digits come from integer division.

  The INTEGER AND FRACTIONAL parts are scaled SEPARATELY. Scaling the whole
  value by 10^decimals in one multiply overflows Int64 the moment
  |v| * 10^decimals reaches 2^63 — `WriteLn(1e16:0:5)` and `WriteLn(267.5:0:17)`
  both did, and printed 2^63's own digits with a point pushed in
  (92233720368547.75808), with nothing to suggest the number was debris
  (bug-b-writeln-float-with-17-decimals-prints-garbage).

  trunc(|v|) is exact in Int64 for |v| < 2^63, and |v| - trunc(|v|) is exact
  too, both operands being representable. The fraction is below 1, so scaling
  IT by up to 10^18 cannot overflow — one multiply and one rounding, the same
  quality as before for every value that already printed correctly.

  Digits past the 18th are printed as zeros rather than guessed: a double
  carries no information there, and FPC pads the same way (measured — both
  print `0.1:0:20` as 0.10000000000000000000).

  |v| >= 2^63 has no fixed form to build and is still wrong; FPC prints those
  in full, so the residual is
  compat-pascal-write-fixed-huge-magnitude-differs-from-fpc. }
var pow10, divisor: Int64; i, k, fdigits, jncOff: Integer;
    pNotNeg, pCntTop, pCntDone, pNoPad: Integer;
    nfJne, nfJnz, nfJnc, nfJmpSign, nfEndInf, nfEndNan: Integer;
begin
  { ---- NON-FINITE first ----

    A fixed-decimals request cannot be honoured for a value that has no digits.
    Unguarded, this path did not hang the way the scientific one did — it scaled
    through Int64 and printed 9223372036854775809.000000 for +Inf, a plausible
    number that is entirely debris. Its portable twin (PXXWriteFloatFixed, used
    by every target without a native emitter) DID hang, so the pair produced two
    different wrong answers for the same program depending on the backend
    (bug-a-writeln-of-a-non-finite-double-hangs).

    The spelling wins over the field width: `Inf:12:3` prints ` Inf`, not a
    padded one. Field padding of a non-numeric spelling is a separate question
    and FPC is not a clean oracle for it either.

    rel32 branches, not rel8 — each EmitwriteChar expands to a write syscall
    sequence, so a byte displacement silently truncates. Before the padding
    pre-pass, so no register state is live yet. }
  EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0);   { movq rax, xmm0 }
  EmitB($48); EmitB($BA); EmitI64($7FF0000000000000);           { mov rdx, expmask }
  EmitB($48); EmitB($89); EmitB($C1);                           { mov rcx, rax }
  EmitB($48); EmitB($21); EmitB($D1);                           { and rcx, rdx }
  EmitB($48); EmitB($39); EmitB($D1);                           { cmp rcx, rdx }
  EmitB($0F); EmitB($85); nfJne := CodeLen; EmitI32(0);         { jne .finite }
  EmitB($48); EmitB($89); EmitB($C1);                           { mov rcx, rax (sign) }
  EmitB($48); EmitB($BA); EmitI64($000FFFFFFFFFFFFF);           { mov rdx, mantmask }
  EmitB($48); EmitB($21); EmitB($D0);                           { and rax, rdx }
  EmitB($48); EmitB($85); EmitB($C0);                           { test rax, rax }
  EmitB($0F); EmitB($85); nfJnz := CodeLen; EmitI32(0);         { jnz .nan }
  EmitB($48); EmitB($0F); EmitB($BA); EmitB($E1); EmitB($3F);   { bt rcx, 63 }
  EmitB($0F); EmitB($83); nfJnc := CodeLen; EmitI32(0);         { jnc .posinf }
  MovRaxImm(Ord('-')); EmitwriteChar;
  EmitB($E9); nfJmpSign := CodeLen; EmitI32(0);                 { jmp .infbody }
  Patch32(nfJnc, CodeLen - (nfJnc + 4));                        { .posinf: }
  MovRaxImm(Ord(' ')); EmitwriteChar;
  Patch32(nfJmpSign, CodeLen - (nfJmpSign + 4));                { .infbody: }
  MovRaxImm(Ord('I')); EmitwriteChar;
  MovRaxImm(Ord('n')); EmitwriteChar;
  MovRaxImm(Ord('f')); EmitwriteChar;
  EmitB($E9); nfEndInf := CodeLen; EmitI32(0);                  { jmp .fixdone }
  Patch32(nfJnz, CodeLen - (nfJnz + 4));                        { .nan: }
  MovRaxImm(Ord(' ')); EmitwriteChar;
  MovRaxImm(Ord('N')); EmitwriteChar;
  MovRaxImm(Ord('a')); EmitwriteChar;
  MovRaxImm(Ord('n')); EmitwriteChar;
  EmitB($E9); nfEndNan := CodeLen; EmitI32(0);                  { jmp .fixdone }
  Patch32(nfJne, CodeLen - (nfJne + 4));                        { .finite: }

  { the fractional scale, capped where Int64 stops carrying information }
  fdigits := decimals;
  if fdigits > 18 then fdigits := 18;
  pow10 := 1;
  for i := 1 to fdigits do pow10 := pow10 * 10;

  { Field-width padding: a pre-pass computes the formatted length and emits the
    leading spaces, right-justifying the value (FPC `:w:d`). It must not disturb
    xmm0 (the emission below re-reads it); it works in rax/rcx/rdx/rsi + xmm1/xmm2
    only. Skipped for width<=0 (the common writeln(x:0:d) form). }
  if width > 0 then
  begin
    EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0);   { movq rax, xmm0 }
    EmitB($48); EmitB($31); EmitB($F6);                           { xor rsi, rsi }
    EmitB($48); EmitB($0F); EmitB($BA); EmitB($E0); EmitB($3F);   { bt rax, 63 }
    EmitB($73); pNotNeg := CodeLen; EmitB(0);                     { jnc .notneg }
    EmitB($48); EmitB($FF); EmitB($C6);                           { inc rsi (sign char) }
    Code[pNotNeg] := Byte(CodeLen - (pNotNeg + 1));
    EmitB($48); EmitB($0F); EmitB($BA); EmitB($F0); EmitB($3F);   { btr rax, 63 (abs bits) }
    EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C8);   { movq xmm1, rax }
    { The intpart AS PRINTED, which means AFTER the fraction's rounding: `9.999:7:2`
      prints `10.00`, two integer digits from a value whose trunc is 9, and
      counting the untruncated one padded the field one column too wide. Same
      split as the emission below, in the scratch registers this pre-pass is
      allowed to touch (rax/rcx/rdx/rsi + xmm1/xmm2; xmm0 must survive). }
    EmitAsmX64([
      'cvttsd2si rax, xmm1',
      'cvtsi2sd xmm2, rax',
      'subsd xmm1, xmm2'
    ]);
    EmitB($48); EmitB($B9); EmitI64(pow10);                        { mov rcx, pow10 }
    EmitAsmX64([
      'cvtsi2sd xmm2, rcx',
      'mulsd xmm1, xmm2'
    ]);
    EmitB($48); EmitB($BA); EmitI64($3FE0000000000000);            { mov rdx, 0.5 }
    EmitAsmX64([
      'movq xmm2, rdx',
      'addsd xmm1, xmm2',
      'cvttsd2si rdx, xmm1',
      'cmp rdx, rcx',
      'jb .nocarrywidth',
      'inc rax',
    '.nocarrywidth:'
    ]);
    EmitB($48); EmitB($FF); EmitB($C6);                           { inc rsi (first int digit) }
    EmitB($48); EmitB($B9); EmitI64(10);                          { mov rcx, 10 }
    pCntTop := CodeLen;                                           { .cnt: }
    EmitB($48); EmitB($83); EmitB($F8); EmitB($0A);               { cmp rax, 10 }
    EmitB($72); pCntDone := CodeLen; EmitB(0);                    { jb .cntdone }
    EmitB($48); EmitB($31); EmitB($D2);                           { xor rdx, rdx }
    EmitB($48); EmitB($F7); EmitB($F1);                           { div rcx }
    EmitB($48); EmitB($FF); EmitB($C6);                           { inc rsi }
    EmitB($EB); EmitB(Byte(pCntTop - (CodeLen + 1)));             { jmp .cnt }
    Code[pCntDone] := Byte(CodeLen - (pCntDone + 1));            { .cntdone: }
    if decimals > 0 then
    begin
      EmitB($48); EmitB($81); EmitB($C6); EmitI32(decimals + 1); { add rsi, decimals+1 }
    end;
    MovRaxImm(width);
    EmitB($48); EmitB($29); EmitB($F0);                           { sub rax, rsi (padcount) }
    EmitB($7E); pNoPad := CodeLen; EmitB(0);                      { jle .nopad }
    EnsureSpaces;
    EmitB($48); EmitB($BE); EmitDataRef(SpacesOffset);           { mov rsi, spaces }
    EmitB($48); EmitB($89); EmitB($C2);                           { mov rdx, rax }
    MovRaxImm(SYS_WRITE); MovRdiImm(CurWriteFd); EmitSyscall;
    Code[pNoPad] := Byte(CodeLen - (pNoPad + 1));                { .nopad: }
  end;

  { sign: if the sign bit is set, print '-' and clear it (abs) }
  EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0);   { movq rax, xmm0 }
  EmitB($48); EmitB($0F); EmitB($BA); EmitB($E0); EmitB($3F);   { bt rax, 63 }
  EmitB($73); jncOff := CodeLen; EmitB(0);                      { jnc .pos }
  EmitB($48); EmitB($0F); EmitB($BA); EmitB($F0); EmitB($3F);   { btr rax, 63 }
  EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C0);   { movq xmm0, rax }
  MovRaxImm(Ord('-')); EmitwriteChar;
  Code[jncOff] := Byte(CodeLen - (jncOff + 1));

  { rax = trunc(|v|) exactly; rbx = round((|v| - rax) * 10^fdigits), which
    cannot overflow because the fraction is below 1. A fraction that rounds up
    to 1.0 carries into the integer part — with fdigits = 0 that IS the
    round-to-nearest the `decimals <= 0` form needs. }
  EmitAsmX64([
    'cvttsd2si rax, xmm0',
    'cvtsi2sd xmm1, rax',
    'subsd xmm0, xmm1'
  ]);
  { 10^fdigits reaches 10^18, so it must be the full imm64 form — an imm32
    silently truncated it and every value with 15+ decimals rounded up }
  EmitB($48); EmitB($BB); EmitI64(pow10);                       { mov rbx, pow10 }
  EmitAsmX64([
    'cvtsi2sd xmm1, rbx',
    'mulsd xmm0, xmm1',
    'push rax'
  ]);
  { round HALF AWAY FROM ZERO, by adding a half and truncating — FPC's rule for
    write(v:w:d), measured: 0.5/1.5/2.5 at :0:0 print 1/2/3, where round-to-even
    would give 0/2/2. The value is already non-negative here (the sign was
    printed and cleared above), so "away from zero" is "up". }
  EmitB($48); EmitB($B8); EmitI64($3FE0000000000000);           { mov rax, 0.5 }
  EmitAsmX64([
    'movq xmm1, rax',
    'addsd xmm0, xmm1',
    'cvttsd2si rax, xmm0',
    'cmp rax, rbx',
    'jb .nocarry',
    'xor rax, rax',
    'pop rbx',
    'inc rbx',
    'push rbx',
  '.nocarry:',
    'mov rbx, rax',
    'pop rax'
  ]);

  if decimals <= 0 then begin EmitwriteUInt; Exit; end;

  EmitB($53);                                                   { push rbx (frac) }
  EmitwriteUInt;                                                { print intpart }
  MovRaxImm(Ord('.')); EmitwriteChar;
  EmitB($5B);                                                   { pop rbx (frac) }

  { print frac as 'fdigits' zero-padded digits, most significant first, then
    literal zeros out to `decimals`. frac stays in rbx (preserved across the
    write syscall). }
  for i := fdigits - 1 downto 0 do
  begin
    divisor := 1;
    for k := 1 to i do divisor := divisor * 10;
    EmitB($48); EmitB($89); EmitB($D8);                         { mov rax, rbx }
    EmitB($48); EmitB($31); EmitB($D2);                         { xor rdx, rdx }
    EmitB($48); EmitB($B9); EmitI64(divisor);                   { mov rcx, divisor }
    EmitB($48); EmitB($F7); EmitB($F1);                         { div rcx }
    EmitB($48); EmitB($89); EmitB($D3);                         { mov rbx, rdx }
    EmitB($48); EmitB($83); EmitB($C0); EmitB($30);             { add rax, '0' }
    EmitwriteChar;
  end;
  for i := fdigits + 1 to decimals do
  begin
    MovRaxImm(Ord('0')); EmitwriteChar;
  end;
  Patch32(nfEndInf, CodeLen - (nfEndInf + 4));                  { .fixdone: }
  Patch32(nfEndNan, CodeLen - (nfEndNan + 4));
end;

procedure EmitWriteFloatSciSelfContained;
{ The ORIGINAL hand-written x86-64 formatter, kept ONLY as a fallback for
  frontends that link no RTL (the esoteric skeleton probes: Algol, Fortran,
  LOLCODE, Whitespace, Erlang — all x86-64-only). Those emit code immediately
  with no entry jump, so they cannot pull builtinheap, and the shim below would
  fail with "compiler error: PXXWriteFloatSci not found".

  It is NOT correctly rounded — it normalises by repeated divide and drifts from
  the 16th digit, and gets the EXPONENT wrong for 1e200
  (bug-a-writeln-float-exponent-form-not-correctly-rounded). Every program that
  links the RTL — i.e. every real one — takes the exact path instead. Do not
  extend this; if a probe frontend ever needs correct digits, give it an entry
  jump so it can pull builtinheap, and delete this. }
{ Double value in xmm0. Prints Pascal-style scientific notation:
  <' '|'-'>d.<16 digits>E<'+'|'-'>ddd  (17 significant digits, 3-digit exponent),
  matching FPC's default Str(Double) field width. Digit extraction uses double
  arithmetic, so the last 1-2 digits may differ from a correctly-rounded bignum
  formatter; adequate for general output. e10 kept in r12. }
const FRAC = 16;
var jncPos, jmpSignDone, jnzNz, jmpDone: Integer;
    laTop, laJb, lbTop, lbJae, jnsPos2, jmpEd: Integer;
    clampJle, bdLoop, roundJl, ovJb: Integer;
    nfJne, nfJnz, nfJnc, nfJmpSign, nfDoneInf, nfDoneNan: Integer;
    k, j: Integer; divisor: Int64;
begin
  EmitB($41); EmitB($54);                                       { push r12 }

  { ---- NON-FINITE first: Inf and NaN have no decimal normalisation ----

    The two loops below normalise into [1,10) by repeated divide/multiply. For
    +Inf, `Inf/10` is still Inf, so `.la` NEVER EXITS; a NaN compares UNORDERED,
    which leaves `.lb`'s `jae` untaken and loops there instead. So `writeln` of a
    non-finite Double emitted its sign and then SPUN FOREVER — a hang, the one
    failure shape worse than a crash, and reachable from ordinary code because a
    float divide by zero yields Inf BY DESIGN here rather than erroring
    (bug-a-writeln-of-a-non-finite-double-hangs).

    Checked BEFORE the sign block on purpose: everything here runs with no
    syscall in between, so rax/rcx/rdx are free (EmitwriteChar issues a syscall,
    which clobbers rcx and r11 — that is why the existing code parks live values
    in r12/r13). It also lets NaN print WITHOUT a sign, which is what FPC does;
    detecting after the sign block would have emitted the '-' that 0.0/0.0's
    negative NaN carries.

    Spelling matches sysutils' FloatToStr — `Inf` / `-Inf` — plus `Nan`. }
  EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0);   { movq rax, xmm0 }
  EmitB($48); EmitB($BA); EmitI64($7FF0000000000000);           { mov rdx, expmask }
  EmitB($48); EmitB($89); EmitB($C1);                           { mov rcx, rax }
  EmitB($48); EmitB($21); EmitB($D1);                           { and rcx, rdx }
  EmitB($48); EmitB($39); EmitB($D1);                           { cmp rcx, rdx }
  { rel32 throughout this block, NOT rel8: each EmitwriteChar expands to a full
    write syscall sequence, so these branches span far more than 127 bytes and a
    byte displacement silently TRUNCATES — which is what made NaN still hang
    after the Inf case was already right. }
  EmitB($0F); EmitB($85); nfJne := CodeLen; EmitI32(0);         { jne .finite }
  EmitB($48); EmitB($89); EmitB($C1);                           { mov rcx, rax (keep sign) }
  EmitB($48); EmitB($BA); EmitI64($000FFFFFFFFFFFFF);           { mov rdx, mantmask }
  EmitB($48); EmitB($21); EmitB($D0);                           { and rax, rdx }
  EmitB($48); EmitB($85); EmitB($C0);                           { test rax, rax }
  EmitB($0F); EmitB($85); nfJnz := CodeLen; EmitI32(0);          { jnz .nan }
  { Inf: sign from the saved bits, then the magnitude spelling }
  EmitB($48); EmitB($0F); EmitB($BA); EmitB($E1); EmitB($3F);   { bt rcx, 63 }
  EmitB($0F); EmitB($83); nfJnc := CodeLen; EmitI32(0);          { jnc .posinf }
  MovRaxImm(Ord('-')); EmitwriteChar;
  EmitB($E9); nfJmpSign := CodeLen; EmitI32(0);                  { jmp .infbody }
  Patch32(nfJnc, CodeLen - (nfJnc + 4));                        { .posinf: }
  MovRaxImm(Ord(' ')); EmitwriteChar;
  Patch32(nfJmpSign, CodeLen - (nfJmpSign + 4));                { .infbody: }
  MovRaxImm(Ord('I')); EmitwriteChar;
  MovRaxImm(Ord('n')); EmitwriteChar;
  MovRaxImm(Ord('f')); EmitwriteChar;
  EmitB($E9); nfDoneInf := CodeLen; EmitI32(0);                 { jmp .done }
  Patch32(nfJnz, CodeLen - (nfJnz + 4));                        { .nan: }
  MovRaxImm(Ord(' ')); EmitwriteChar;
  MovRaxImm(Ord('N')); EmitwriteChar;
  MovRaxImm(Ord('a')); EmitwriteChar;
  MovRaxImm(Ord('n')); EmitwriteChar;
  EmitB($E9); nfDoneNan := CodeLen; EmitI32(0);                 { jmp .done }
  Patch32(nfJne, CodeLen - (nfJne + 4));                        { .finite: }

  { ---- sign ---- }
  EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0);   { movq rax, xmm0 }
  EmitB($48); EmitB($0F); EmitB($BA); EmitB($E0); EmitB($3F);   { bt rax, 63 }
  EmitB($73); jncPos := CodeLen; EmitB(0);                      { jnc .pos }
  EmitB($48); EmitB($0F); EmitB($BA); EmitB($F0); EmitB($3F);   { btr rax, 63 }
  EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C0);   { movq xmm0, rax }
  MovRaxImm(Ord('-')); EmitwriteChar;
  EmitB($EB); jmpSignDone := CodeLen; EmitB(0);                 { jmp .signdone }
  Code[jncPos] := Byte(CodeLen - (jncPos + 1));                 { .pos: }
  MovRaxImm(Ord(' ')); EmitwriteChar;
  Code[jmpSignDone] := Byte(CodeLen - (jmpSignDone + 1));       { .signdone: }

  { 10.0 -> xmm1, 1.0 -> xmm2 (preserved across syscalls) }
  MovRaxImm(10); EmitB($F2); EmitB($48); EmitB($0F); EmitB($2A); EmitB($C8); { cvtsi2sd xmm1, rax }
  MovRaxImm(1);  EmitB($F2); EmitB($48); EmitB($0F); EmitB($2A); EmitB($D0); { cvtsi2sd xmm2, rax }

  { ---- zero special case ---- }
  EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0);   { movq rax, xmm0 }
  EmitB($48); EmitB($85); EmitB($C0);                          { test rax, rax }
  EmitB($0F); EmitB($85); jnzNz := CodeLen; EmitI32(0);        { jnz .nz }
  MovRaxImm(Ord('0')); EmitwriteChar;
  MovRaxImm(Ord('.')); EmitwriteChar;
  for j := 1 to FRAC do begin MovRaxImm(Ord('0')); EmitwriteChar; end;
  MovRaxImm(Ord('E')); EmitwriteChar;
  MovRaxImm(Ord('+')); EmitwriteChar;
  for j := 1 to 3 do begin MovRaxImm(Ord('0')); EmitwriteChar; end;
  EmitB($E9); jmpDone := CodeLen; EmitI32(0);                  { jmp .done }
  Patch32(jnzNz, CodeLen - (jnzNz + 4));                       { .nz: }

  { ---- normalize value into [1,10), tracking decimal exponent in r12 ---- }
  EmitB($4D); EmitB($31); EmitB($E4);                          { xor r12, r12 }
  laTop := CodeLen;                                            { .la: while value>=10 }
  EmitB($66); EmitB($0F); EmitB($2E); EmitB($C1);              { ucomisd xmm0, xmm1 }
  EmitB($72); laJb := CodeLen; EmitB(0);                       { jb .ea }
  EmitB($F2); EmitB($0F); EmitB($5E); EmitB($C1);              { divsd xmm0, xmm1 }
  EmitB($49); EmitB($FF); EmitB($C4);                          { inc r12 }
  EmitB($EB); EmitB(Byte(laTop - (CodeLen + 1)));              { jmp .la }
  Code[laJb] := Byte(CodeLen - (laJb + 1));                    { .ea: }
  lbTop := CodeLen;                                            { .lb: while value<1 }
  EmitB($66); EmitB($0F); EmitB($2E); EmitB($C2);              { ucomisd xmm0, xmm2 }
  EmitB($73); lbJae := CodeLen; EmitB(0);                      { jae .eb }
  EmitB($F2); EmitB($0F); EmitB($59); EmitB($C1);              { mulsd xmm0, xmm1 }
  EmitB($49); EmitB($FF); EmitB($CC);                          { dec r12 }
  EmitB($EB); EmitB(Byte(lbTop - (CodeLen + 1)));              { jmp .lb }
  Code[lbJae] := Byte(CodeLen - (lbJae + 1));                  { .eb: }

  { m = round-to-nearest(value * 10^FRAC) built as a (FRAC+1)-digit integer in
    rbx, extracted MSD-first by iteration so each step only truncates a value in
    [0,10). This keeps ~17 accurate digits, unlike one (value*10^16) double
    multiply which overflows the 53-bit mantissa and zeroes the low digits. rcx
    counts the FRAC+1 leading digits; one extra guard digit then rounds half-up.
    No syscalls here, so rax/rcx/rdx are free scratch; xmm1 still holds 10.0. }
  EmitB($48); EmitB($31); EmitB($DB);                          { xor rbx, rbx }
  EmitB($B9); EmitI32(FRAC + 1);                               { mov ecx, 17 }
  bdLoop := CodeLen;                                           { .bd: }
  EmitB($F2); EmitB($48); EmitB($0F); EmitB($2C); EmitB($C0);  { cvttsd2si rax, xmm0 }
  EmitB($48); EmitB($83); EmitB($F8); EmitB($09);              { cmp rax, 9 }
  EmitB($7E); clampJle := CodeLen; EmitB(0);                   { jle .ok }
  EmitB($B8); EmitI32(9);                                      { mov eax, 9 }
  Code[clampJle] := Byte(CodeLen - (clampJle + 1));            { .ok: }
  EmitB($48); EmitB($6B); EmitB($DB); EmitB($0A);              { imul rbx, rbx, 10 }
  EmitB($48); EmitB($01); EmitB($C3);                          { add rbx, rax }
  EmitB($F2); EmitB($48); EmitB($0F); EmitB($2A); EmitB($D8);  { cvtsi2sd xmm3, rax }
  EmitB($F2); EmitB($0F); EmitB($5C); EmitB($C3);              { subsd xmm0, xmm3 }
  EmitB($F2); EmitB($0F); EmitB($59); EmitB($C1);              { mulsd xmm0, xmm1 }
  EmitB($48); EmitB($FF); EmitB($C9);                          { dec rcx }
  EmitB($75); EmitB(Byte(bdLoop - (CodeLen + 1)));             { jnz .bd }
  { guard digit: round half-up }
  EmitB($F2); EmitB($48); EmitB($0F); EmitB($2C); EmitB($C0);  { cvttsd2si rax, xmm0 }
  EmitB($48); EmitB($83); EmitB($F8); EmitB($05);              { cmp rax, 5 }
  EmitB($7C); roundJl := CodeLen; EmitB(0);                    { jl .noround }
  EmitB($48); EmitB($FF); EmitB($C3);                          { inc rbx }
  Code[roundJl] := Byte(CodeLen - (roundJl + 1));              { .noround: }
  { carry past the leading digit (9.99..->10.0): drop a digit, bump exponent }
  divisor := 1; for k := 0 to FRAC do divisor := divisor * 10;  { 10^(FRAC+1) }
  EmitB($48); EmitB($B8); EmitI64(divisor);                    { mov rax, 10^17 }
  EmitB($48); EmitB($39); EmitB($C3);                          { cmp rbx, rax }
  EmitB($72); ovJb := CodeLen; EmitB(0);                       { jb .nov }
  EmitB($48); EmitB($89); EmitB($D8);                          { mov rax, rbx }
  EmitB($48); EmitB($31); EmitB($D2);                          { xor rdx, rdx }
  EmitB($B9); EmitI32(10);                                     { mov ecx, 10 }
  EmitB($48); EmitB($F7); EmitB($F1);                          { div rcx }
  EmitB($48); EmitB($89); EmitB($C3);                          { mov rbx, rax }
  EmitB($49); EmitB($FF); EmitB($C4);                          { inc r12 }
  Code[ovJb] := Byte(CodeLen - (ovJb + 1));                    { .nov: }

  { print m as d.<FRAC digits>, most significant first }
  for k := FRAC downto 0 do
  begin
    divisor := 1; for j := 1 to k do divisor := divisor * 10;
    EmitB($48); EmitB($89); EmitB($D8);                        { mov rax, rbx }
    EmitB($48); EmitB($31); EmitB($D2);                        { xor rdx, rdx }
    EmitB($48); EmitB($B9); EmitI64(divisor);                  { mov rcx, divisor }
    EmitB($48); EmitB($F7); EmitB($F1);                        { div rcx }
    EmitB($48); EmitB($89); EmitB($D3);                        { mov rbx, rdx }
    EmitB($48); EmitB($83); EmitB($C0); EmitB($30);            { add rax, '0' }
    EmitwriteChar;
    if k = FRAC then begin MovRaxImm(Ord('.')); EmitwriteChar; end;
  end;

  { 'E', exponent sign, 3-digit exponent }
  MovRaxImm(Ord('E')); EmitwriteChar;
  EmitB($4C); EmitB($89); EmitB($E0);                          { mov rax, r12 }
  EmitB($48); EmitB($85); EmitB($C0);                          { test rax, rax }
  EmitB($79); jnsPos2 := CodeLen; EmitB(0);                    { jns .pos2 }
  EmitB($48); EmitB($F7); EmitB($D8);                          { neg rax }
  EmitB($48); EmitB($89); EmitB($C3);                          { mov rbx, rax }
  MovRaxImm(Ord('-')); EmitwriteChar;
  EmitB($EB); jmpEd := CodeLen; EmitB(0);                      { jmp .ed }
  Code[jnsPos2] := Byte(CodeLen - (jnsPos2 + 1));              { .pos2: }
  EmitB($48); EmitB($89); EmitB($C3);                          { mov rbx, rax }
  MovRaxImm(Ord('+')); EmitwriteChar;
  Code[jmpEd] := Byte(CodeLen - (jmpEd + 1));                  { .ed: }
  for k := 2 downto 0 do
  begin
    divisor := 1; for j := 1 to k do divisor := divisor * 10;
    EmitB($48); EmitB($89); EmitB($D8);                        { mov rax, rbx }
    EmitB($48); EmitB($31); EmitB($D2);                        { xor rdx, rdx }
    EmitB($48); EmitB($B9); EmitI64(divisor);                  { mov rcx, divisor }
    EmitB($48); EmitB($F7); EmitB($F1);                        { div rcx }
    EmitB($48); EmitB($89); EmitB($D3);                        { mov rbx, rdx }
    EmitB($48); EmitB($83); EmitB($C0); EmitB($30);            { add rax, '0' }
    EmitwriteChar;
  end;

  Patch32(jmpDone, CodeLen - (jmpDone + 4));                   { .done: }
  Patch32(nfDoneInf, CodeLen - (nfDoneInf + 4));               { ...Inf joins here }
  Patch32(nfDoneNan, CodeLen - (nfDoneNan + 4));               { ...and NaN }
  EmitB($41); EmitB($5C);                                       { pop r12 }
end;

procedure SciFormatFor(wid: Integer; tk: Integer; var fracdigits, expdigits: Integer);
{ The (fracdigits, expdigits) a scientific write should use, from the field
  width and the value's STATIC type. One function because five backends ask the
  same question, and five copies of a clamp is where an off-by-one hides.

  Measured against FPC 3.2.2 (2026-08-19), not derived from its docs:

    d           ->  3.3333333333333331E-001    16 frac, 3 exp   (Double default)
    d:12        ->  3.3333E-001                 4 frac
    d:20        ->  3.333333333333E-001        12 frac
    d:8         ->  3.3E-001                    1 frac  (clamped; 9 chars > 8)
    s           ->  3.333333433E-01             9 frac, 2 exp   (Single default)
    s:14        ->  3.3333334E-01               7 frac

  So: total width = sign(1) + lead(1) + point(1) + frac + 'E'(1) + expsign(1) +
  expdigits, giving frac = wid - 5 - expdigits. FPC's floor is ONE fractional
  digit and it overflows the field rather than going below it, which is why the
  clamp widens the output instead of truncating the number. }
begin
  if tk = Ord(tySingle) then expdigits := 2 else expdigits := 3;
  if wid > 0 then
  begin
    fracdigits := wid - 5 - expdigits;
    if fracdigits < 1 then fracdigits := 1;
    if fracdigits > 16 then fracdigits := 16;
  end
  else if tk = Ord(tySingle) then
    fracdigits := 9
  else
    fracdigits := 16;
end;

procedure EmitWriteFloatSci(fracdigits, expdigits: Integer);
{ Double value in xmm0 -> Pascal scientific notation with `fracdigits` digits
  after the point and an `expdigits`-digit exponent.

  Took NO parameters until 2026-08-19, which is why write(d:W) could not narrow
  the mantissa to the field and a Single could not ask for its 10-digit,
  2-digit-exponent form. It now takes the same shape as its sibling
  EmitWriteFloatFixed(width, decimals) — one calling convention for both float
  writers rather than one that formats and one that cannot.

  Shims onto PXXWriteFloatSci (exact decimal expansion) when the RTL is linked,
  which is the case for every ordinary program; falls back to the old
  self-contained emitter for the RTL-less probe frontends. That fallback is
  fixed at 16/3 and cannot honour a request — acceptable because it serves only
  frontends with no RTL, where writeln formatting is not under test. }
var procIdx: Integer;
begin
  procIdx := FindProc('PXXWriteFloatSci');
  if procIdx < 0 then
  begin
    EmitWriteFloatSciSelfContained;
    Exit;
  end;
  EmitAsmX64([
    'sub rsp, 16',
    'movsd [rsp], xmm0',
    'mov rdi, rsp',
    'mov rsi, %', fracdigits,
    'mov rdx, %', expdigits
  ]);
  EmitCallProc(procIdx);
  EmitAsmX64(['add rsp, 16']);
end;

function WriteExprIsFloat(node: Integer): Boolean;
{ True when a writeln argument expression has a floating-point type. }
begin
  if ASTKind[node] = AN_IDENT then
    Result := (ASTIVal[node] >= 0) and TypeIsFloat(Syms[ASTIVal[node]].TypeKind)
  else
    Result := TypeIsFloat(IntToTypeKind(ASTTk[node]));
end;

{ ===== Prologue/Epilogue ===== }

function EmitProcPrologue: Integer;
{ Returns patch position for sub rsp/esp imm32 }
begin
  if TargetArch = TARGET_I386 then
  begin
    EmitB($55);                          { push ebp }
    EmitB($89); EmitB($E5);              { mov ebp, esp }
    EmitB($81); EmitB($EC);              { sub esp, imm32 }
    Result := CodeLen; EmitI32(0);
    Exit;
  end;
  if TargetArch = TARGET_ARM32 then
  begin
    EmitI32($E92D4800);  { push {fp, lr} }
    EmitI32($E1A0B00D);  { mov fp, sp }
    { Frame size can exceed an ARM rotated-imm8, so load it from a literal
      into r9 (scratch, free at proc entry) and subtract. Patch the literal. }
    EmitI32($E59F9000);  { ldr r9, [pc]  (the literal below) }
    EmitI32($EA000000);  { b .+8         (skip the literal) }
    Result := CodeLen;
    EmitI32(0);          { frame-size literal (patched) }
    EmitI32($E04DD009);  { sub sp, sp, r9 }
    Exit;
  end;
  if TargetArch = TARGET_AARCH64 then
  begin
    EmitI32($A9BF7BFD);  { stp x29, x30, [sp, #-16]! }
    EmitI32($910003FD);  { mov x29, sp }
    Result := CodeLen;
    EmitI32($D10003FF);  { sub sp, sp, #0 }
    Exit;
  end;
  if TargetArch = TARGET_XTENSA then
  begin
    if XtensaABI = XTENSA_ABI_WINDOWED then
    begin
      xtensa_entry(reg_xtensa_sp, 32);
      { a15 is only a bootstrap frame base until params are spilled; the body
        frame pointer moves to a7, outside call8's outgoing window. The
        patchable addi lowers sp once to reserve locals + the constant-sp
        expression-stack region; sp then stays fixed for the whole body so the
        window spill area at [sp-16] never desyncs. The reserved region starts
        with XT_OUTARG_REGION bytes of OUTGOING argument space at sp+0 (the
        ABI's home for argument words 6..), so the expression stack begins
        above it. }
      XtSpillDepth := XT_OUTARG_REGION;
      XtSpillMax := XtSpillDepth;
      xtensa_mov(reg_xtensa_a15, reg_xtensa_sp);
      Result := CodeLen;
      xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 0);
    end
    else
    begin
      { Raw `interrupt;` handler (Call0): a hardware exception can preempt arbitrary
        code, so the interrupted caller-saved a-regs the body clobbers (a2-a8,
        a10-a13) must be preserved. a0/a1(sp)/a15 are covered by the normal Call0
        frame below; a9/a14 are never touched by codegen. Saved in a 48-byte area
        (11 regs, 16-byte aligned) ABOVE the normal frame; the epilogue restores
        them and returns via `rfe` (general level-1 exception). Windowed ABI is
        gated off in the parser (mid-window spill is a follow-up). }
      if (CurProc >= 0) and ProcIsInterrupt[CurProc] then
      begin
        xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, -48);
        xtensa_s32i(reg_xtensa_a2, reg_xtensa_sp, 0);  xtensa_s32i(reg_xtensa_a3, reg_xtensa_sp, 4);
        xtensa_s32i(reg_xtensa_a4, reg_xtensa_sp, 8);  xtensa_s32i(reg_xtensa_a5, reg_xtensa_sp, 12);
        xtensa_s32i(reg_xtensa_a6, reg_xtensa_sp, 16); xtensa_s32i(reg_xtensa_a7, reg_xtensa_sp, 20);
        xtensa_s32i(reg_xtensa_a8, reg_xtensa_sp, 24); xtensa_s32i(reg_xtensa_a10, reg_xtensa_sp, 28);
        xtensa_s32i(reg_xtensa_a11, reg_xtensa_sp, 32); xtensa_s32i(reg_xtensa_a12, reg_xtensa_sp, 36);
        xtensa_s32i(reg_xtensa_a13, reg_xtensa_sp, 40);
      end;
      { Xtensa Call0 ABI prologue: push a0, a15 (save Return Address and Frame Pointer) }
      xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, -16);
      xtensa_s32i(reg_xtensa_a0, reg_xtensa_sp, 12);
      xtensa_s32i(reg_xtensa_a15, reg_xtensa_sp, 8);
      xtensa_mov(reg_xtensa_a15, reg_xtensa_sp);
      Result := CodeLen;
      xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 0);
    end;
    Exit;
  end;
  if TargetArch = TARGET_RISCV32 then
  begin
    { Raw `interrupt;` handler: a hardware trap can preempt arbitrary code, so the
      interrupted caller-saved context (t0-t6, a0-a7) must be preserved across the
      body — the normal prologue below only saves ra/s0. Saved in a 64-byte area
      ABOVE the normal frame; the epilogue restores them then `mret`s. ra/s0 are
      covered by the normal prologue. (Codegen never touches s1-s11.) }
    if (CurProc >= 0) and ProcIsInterrupt[CurProc] then
    begin
      rv32_addi(reg_sp, reg_sp, -64);
      rv32_sw(reg_t0, reg_sp, 0);  rv32_sw(reg_t1, reg_sp, 4);  rv32_sw(reg_t2, reg_sp, 8);
      rv32_sw(reg_t3, reg_sp, 12); rv32_sw(reg_t4, reg_sp, 16); rv32_sw(reg_t5, reg_sp, 20);
      rv32_sw(reg_t6, reg_sp, 24);
      rv32_sw(reg_a0, reg_sp, 28); rv32_sw(reg_a1, reg_sp, 32); rv32_sw(reg_a2, reg_sp, 36);
      rv32_sw(reg_a3, reg_sp, 40); rv32_sw(reg_a4, reg_sp, 44); rv32_sw(reg_a5, reg_sp, 48);
      rv32_sw(reg_a6, reg_sp, 52); rv32_sw(reg_a7, reg_sp, 56);
    end;
    { RISC-V prologue: push ra, s0 (save Return Address and Frame Pointer) }
    rv32_addi(reg_sp, reg_sp, -16);
    rv32_sw(reg_ra, reg_sp, 12);
    rv32_sw(reg_s0, reg_sp, 8);
    rv32_addi(reg_s0, reg_sp, 0);
    Result := CodeLen;
    { Reserve THREE words for the frame adjustment (patched in PatchProcPrologue):
      a single `addi sp,sp,-frame` only reaches +/-2048, so a larger frame needs
      `lui t0,hi; addi t0,t0,lo; sub sp,sp,t0`. Small frames patch addi + 2 nops.
      (t0 is scratch at entry — the interrupt path already saved it above.) }
    rv32_addi(reg_sp, reg_sp, 0);
    rv32_addi(reg_zero, reg_zero, 0);
    rv32_addi(reg_zero, reg_zero, 0);
    Exit;
  end;
  EmitB($55);
  EmitB($48); EmitB($89); EmitB($E5);
  EmitB($48); EmitB($81); EmitB($EC);
  Result := CodeLen; EmitI32(0);
end;

procedure PatchProcPrologue(patchPos, size: Integer);
var aligned, a64imm, rvLo, rvHi: Integer;
begin
  aligned := ((size + 15) div 16) * 16;
  { Windowed xtensa keeps sp constant and runs its expression/argument stack in
    a reserved region below the locals. Round the one-shot frame (locals +
    region) up to 256 and lower sp with a single ADDMI — ADDI's +-128 immediate
    cannot reach it, and a too-large ADDI silently truncates. }
  if (TargetArch = TARGET_XTENSA) and (XtensaABI = XTENSA_ABI_WINDOWED) then
  begin
    { Reserve the locals plus what this routine's expression/argument stack
      actually reached (XtSpillMax already includes XT_OUTARG_REGION, its
      starting value) — not the worst case. ESP-IDF hands tasks 3584-byte
      stacks, so a fixed 256-byte floor per frame cost ~11 levels of recursion:
      printing one Int64 digit by digit is 19 deep and died with LoadProhibited
      (bug-a-xtensa-windowed-frame-minimum-256-bytes).

      ADDI reaches -128 with byte granularity and is the same 3 bytes as ADDMI,
      whose immediate is a multiple of 256 — so small frames use ADDI and pay
      only what they need, and everything else rounds up to ADDMI's step. The
      stack stays 16-byte aligned either way. }
    aligned := size + XtSpillMax;
    if aligned <= 128 then
    begin
      aligned := ((aligned + 15) div 16) * 16;
      if aligned = 0 then aligned := 16;
      Patch24(patchPos, EncodeXtensaAddi(reg_xtensa_sp, reg_xtensa_sp, -aligned));
    end
    else
    begin
      aligned := ((aligned + 255) div 256) * 256;
      Patch24(patchPos, EncodeXtensaAddmi(reg_xtensa_sp, reg_xtensa_sp, -aligned));
    end;
    Exit;
  end;
  if TargetArch = TARGET_ARM32 then
    Patch32(patchPos, aligned)  { raw frame-size literal; loaded into r9, then sub sp,sp,r9 }
  else if TargetArch = TARGET_AARCH64 then
  begin
    { AArch64 `sub sp,sp,#imm` is a 12-bit immediate optionally shifted left 12.
      Frames <= 4095 use it directly; larger frames round up to a 4096 multiple
      and use the LSL #12 form (sh bit = bit 22). The epilog restores via
      `mov sp, x29`, so over-reserving the round-up slack is harmless. }
    if aligned <= 4095 then
      Patch32(patchPos, $D10003FF or (aligned shl 10))
    else
    begin
      a64imm := (aligned + 4095) div 4096;   { units of 4096, <= 4095 (frame < 16 MB) }
      Patch32(patchPos, $D14003FF or (a64imm shl 10));
    end;
  end
  else if TargetArch = TARGET_XTENSA then
  begin
    { Call0 ABI: the prologue saved a0/a15 and set a15 as a frame pointer; the
      epilog restores via `mov sp, a15`, so over-reserving the frame is harmless.
      ADDI's immediate is 8-bit signed (+-128); a larger frame silently wraps.
      Keep the exact ADDI encoding for small frames, and for anything beyond its
      reach round up to 256 and lower sp with a single ADDMI (imm8<<8, reaching
      -32768), mirroring the windowed path. }
    if aligned <= 128 then
      Patch24(patchPos, EncodeXtensaAddi(reg_xtensa_sp, reg_xtensa_sp, -aligned))
    else
    begin
      aligned := ((aligned + 255) div 256) * 256;
      if aligned > 32768 then
        Error('target xtensa (call0): stack frame too large (> 32 KB) for a single ADDMI');
      Patch24(patchPos, EncodeXtensaAddmi(reg_xtensa_sp, reg_xtensa_sp, -aligned));
    end;
  end
  else if TargetArch = TARGET_RISCV32 then
  begin
    { addi's immediate is 12-bit signed (+/-2048); a larger frame silently
      truncated to a positive value and allocated the frame UPWARD, so callees
      overwrote this function's locals (bug-riscv32-large-frame-addi-truncate).
      Small frames: `addi sp,sp,-aligned` + 2 nops. Large: build the size in t0
      (lui+addi) and `sub sp,sp,t0` — three words, matching the reservation. }
    if aligned <= 2047 then
    begin
      Patch32(patchPos, EncodeRISCVAddi(reg_sp, reg_sp, -aligned));
      Patch32(patchPos + 4, EncodeRISCVAddi(0, 0, 0));   { nop }
      Patch32(patchPos + 8, EncodeRISCVAddi(0, 0, 0));   { nop }
    end
    else
    begin
      rvLo := aligned and $FFF;
      if (rvLo and $800) <> 0 then rvLo := rvLo - $1000;  { addi's lo is sign-extended }
      rvHi := aligned - rvLo;                             { multiple of 4096 for lui }
      Patch32(patchPos,     EncodeRISCVLui(reg_t0, rvHi));
      Patch32(patchPos + 4, EncodeRISCVAddi(reg_t0, reg_t0, rvLo));
      Patch32(patchPos + 8, EncodeRISCVSub(reg_sp, reg_sp, reg_t0));
    end;
  end
  else
    Patch32(patchPos, aligned);
end;

function SymNeedsManagedCleanup(i: Integer): Boolean;
begin
  Result := False;
  if Syms[i].TypeKind = tyAnsiString then
    Result := True
  else if Syms[i].TypeKind = tyVariant then
    Result := True
  else if Syms[i].IsArray and (Syms[i].ArrLen = -1) then
    Result := True
  else if SymIsComInterface(i) then
    Result := True
  else if (Syms[i].TypeKind = tyRecord) and not Syms[i].IsArray and
          RecordHasManagedFields(SymTR[i].RecId) then
    Result := True
  { A STATIC array whose ELEMENTS are managed. The tyAnsiString arm at the top
    already (accidentally) catches an array of strings, because an array's
    TypeKind IS its element kind — but the record arm above excludes arrays, so
    a proc whose only managed local was an `array[0..N] of TRec` got no cleanup
    emitted at all and leaked every element.
    bug-a-local-static-array-of-string-never-released-at-scope-exit
    Asked through ManagedElemKind rather than re-derived here, which is what
    also brings in `array[0..N] of IFoo` (kind 4): SymIsComInterface answers
    False for an array on purpose, so nothing above claims it and the whole
    array leaked.
    bug-a-a-local-array-of-interfaces-is-never-released-at-scope-exit }
  else if Syms[i].IsArray and (Syms[i].ArrLen >= 0) and (SymElemDynDepth[i] = 0) and
          (ManagedElemKind(Ord(Syms[i].TypeKind), SymTR[i].ElemRec) <> 0) then
    Result := True;
end;

function ProcHasManagedLocalCleanup(procIdx, retSymIdx: Integer): Boolean;
var i: Integer;
begin
  Result := False;
  for i := Procs[procIdx].ScopeBase to SymCount - 1 do
    if (Syms[i].Kind = skLocal) and (i <> retSymIdx) and SymNeedsManagedCleanup(i) then
    begin
      Result := True;
      Exit;
    end;
end;

procedure EmitLeaveExceptionFrameX64;
begin
  x64_mov_reg_mem(8, rRAX, rRSP, 0, False); { mov rax, [rsp] }
  x64_mov_glob_reg(8, BSS_EXC_TOP, rRAX);   { mov [BSS_EXC_TOP], rax }
  x64_add_reg_imm(8, rRSP, EXC_FRAME_SIZE);  { add rsp, EXC_FRAME_SIZE }
end;

{ Class-binding ARC eligibility (feature-nilpy-object-reclamation slice 4):
  only NAMED user locals/globals participate in rebind-release + scope-exit
  release. Hidden desugar temps ('' or '__py_*') are created MID-body, after
  the proc-entry zero-init pass, so releasing them would read stale stack
  bytes; they keep raw pointer semantics (their construction refs leak as
  before this feature). Except-handler binders are named and get their slot
  nil'd by the AN_TRY_EXCEPT lowering. }
function PyClassSymArcEligible(symIdx: Integer): Boolean;
begin
  { hidden desugar temps included: every NilPy tyClass local — whenever it was
    minted — is nil'd by CompileAST's watermark pass before its first
    statement runs, so releases never read stale stack bytes }
  Result := (Syms[symIdx].TypeKind = tyClass) and
            ((Syms[symIdx].Kind = skLocal) or (Syms[symIdx].Kind = skGlobal)) and
            (not Syms[symIdx].IsArray) and (not Syms[symIdx].IsRef);
end;

procedure EmitManagedLocalCleanup(retSymIdx: Integer);
var i, procIdx, mek: Integer;
begin
  if CurProc < 0 then Exit;
  { A STACKLESS GENERATOR step function RETURNS at every yield and is re-entered
    at the next one, so its locals are not going out of scope on this path —
    they are the generator's live state, checkpointed into the heap instance and
    restored on resume. Releasing them here freed the very objects the instance
    still points at, and the failure was silent: a Nil Python generator walking
    `for t in xs` got a dangling list on its second step, so the loop simply
    ENDED, one element in, with no error anywhere. (Pascal never saw it — its
    class locals are not refcounted, so there was nothing to release.)

    What the references cost instead is that they are dropped only when the
    instance is freed, which today means they leak with it. That is a bounded
    per-generator leak traded for correctness, and it is recorded on
    feature-nilpy-yield-outside-a-for-loop rather than left to be rediscovered. }
  if CurProcIsStackless then Exit;
  { PXXDBG=a.arc:<proc> — every symbol this scope-exit pass CONSIDERS, with the
    three facts that decide whether it is released. A managed temp that leaks is
    invisible in `a.ir` (the epilogue releases are emitted as machine code, not
    IR), so without this the only way to tell a skipped temp from a released one
    was to disassemble. bug-a-an-interface-passed-by-value-leaks-a-reference-per-call. }
  if PxxDbgWants('a.arc', Procs[CurProc].Name) then
  begin
    WriteLn('PXXDBG a.arc ', Procs[CurProc].Name,
            ' scopeBase=', Procs[CurProc].ScopeBase, ' symCount=', SymCount,
            ' retSym=', retSymIdx);
    for i := Procs[CurProc].ScopeBase to SymCount - 1 do
      WriteLn('PXXDBG a.arc   sym=', i, ' name=[', Syms[i].Name,
              '] kind=', Ord(Syms[i].Kind), ' tk=', Ord(Syms[i].TypeKind),
              ' recId=', SymTR[i].RecId, ' comIntf=', Ord(SymIsComInterface(i)),
              ' hiddenArgTemp=', Ord(SymIsHiddenArgTemp[i]));
  end;
  for i := Procs[CurProc].ScopeBase to SymCount - 1 do
  begin
    if (Syms[i].Kind = skLocal) and (i <> retSymIdx) then
    begin
      if SymIsComInterface(i) then
      begin
        { COM/ARC interface local: _Release the held reference (nil-safe). }
        procIdx := FindProc('PXXIntfRelease');
        if procIdx < 0 then Error('compiler error: PXXIntfRelease not found');
        x64_lea_reg_mem(8, rRDI, rRBP, Syms[i].Offset, True);  { lea rdi, [rbp+off] }
        x64_mov_reg_imm(8, rRSI, SymTR[i].RecId - REC_UCLASS_BASE);  { rsi = interface id }
        EmitCallProc(procIdx);
      end
      else if Syms[i].IsArray and (Syms[i].ArrLen >= 0) and (SymElemDynDepth[i] = 0) and
              (ManagedElemKind(Ord(Syms[i].TypeKind), SymTR[i].ElemRec) <> 0) then
      begin
        { STATIC array with MANAGED ELEMENTS: release EVERY element.

          This arm did not exist. An array's TypeKind is its ELEMENT kind, so
          `array[0..N] of string` fell into the scalar tyAnsiString arm below
          and released element 0 ONLY — the other N leaked, silently and
          linearly. Measured: 1 element flat, 3 elements leak 2, 6 leak 5.
          An array of managed RECORDS leaked all of them (SymNeedsManagedCleanup
          did not even flag it, so no cleanup was emitted).

          PXXArrayReleaseImmediate is the header-free element walk already
          added for whole-array assignment — a static array has no
          [refcount][length] prefix, so the count is passed explicitly. N-D
          arrays are stored flat, so ArrLen is the right count.
          MUST precede the scalar arms below, which would otherwise claim it.
          bug-a-local-static-array-of-string-never-released-at-scope-exit }
        procIdx := FindProc('PXXArrayReleaseImmediate');
        if procIdx < 0 then Error('compiler error: PXXArrayReleaseImmediate not found');
        x64_lea_reg_mem(8, rRDI, rRBP, Syms[i].Offset, True);   { rdi = &arr }
        x64_mov_reg_imm(8, rRSI, Syms[i].ArrLen);               { rsi = count }
        mek := ManagedElemKind(Ord(Syms[i].TypeKind), SymTR[i].ElemRec);
        x64_mov_reg_imm(8, rRDX, mek);                          { baseKind }
        if mek = 3 then
          EmitAsmX64(['mov rcx, @data',
            -(RECORD_RTTI_DATAREF_BASE + (SymTR[i].ElemRec - REC_UCLASS_BASE))])
        else
          { kinds 1 and 4: the fourth argument is an immediate, not an address —
            0 for a string element, the interface id for kind 4. }
          x64_mov_reg_imm(8, rRCX, ManagedElemRef(Ord(Syms[i].TypeKind), SymTR[i].ElemRec));
        EmitCallProc(procIdx);
      end
      else if (Syms[i].TypeKind = tyAnsiString) and not Syms[i].IsArray then
      begin
        { A SCALAR AnsiString local. The `not IsArray` guard is load-bearing and
          was missing: an array's TypeKind IS its element kind, so a local
          `array of string` (TypeKind = tyAnsiString, ArrLen = -1) was claimed
          HERE — above the dynamic-array arm below — and the array's DATA
          POINTER was handed to the string releaser as if it were a string
          handle. Neither the elements nor the block were ever freed: measured
          at ~560 bytes leaked per call for an 8-element array, growing linearly
          (200k calls = 112 MB), on HEAD and on pinned alike. The other four
          backends' epilogues already carry this guard; x86-64 was the outlier.
          bug-a-local-dynamic-array-of-string-is-released-as-a-string-handle }
        x64_mov_reg_mem(8, rRAX, rRBP, Syms[i].Offset, True);   { mov rax, [rbp+off] }
        IREmitCodeCall(AnsiStrReleaseAddr);
      end
      else if Syms[i].TypeKind = tyVariant then
      begin
        { lea rax, [rbp + Offset] }
        x64_lea_reg_mem(8, rRAX, rRBP, Syms[i].Offset, True);
        EmitVariantClear;
      end
      else if (Syms[i].TypeKind = tyClass) and (not Syms[i].IsArray) and
              NilPyUserCode and
              PyClassSymArcEligible(i) then
      begin
        { NilPy-user class local: drop the binding's ref at scope exit — the
          trigger that actually reclaims (feature-nilpy-object-reclamation
          slice 4). The Pascal callee carries the nil check and population-tag
          guard, so a Pascal-created instance held here is left alone. }
        procIdx := FindProc('PXXObjRelease');
        if procIdx >= 0 then
        begin
          x64_mov_reg_mem(8, rRDI, rRBP, Syms[i].Offset, True);  { rdi = instance }
          EmitCallProc(procIdx);
        end;
      end
      else if TypeIsPromoInt(Syms[i].TypeKind) then
      begin
        { Promotable-int local/temp: release a heap-tier payload at scope exit.
          Without this every call that spilled a promo value to the bignum tier
          (e.g. the & 0xFFFFFFFFFFFFFFFF mask-constant temp) leaked its payload
          once per call (bug-a-runtime-variant-heap-grows-unbounded). }
        procIdx := FindProc('PXXPromoClear');
        if procIdx >= 0 then
        begin
          x64_lea_reg_mem(8, rRDI, rRBP, Syms[i].Offset, True);  { rdi = slot addr }
          EmitCallProc(procIdx);
        end;
      end
      else if Syms[i].IsArray and (Syms[i].ArrLen = -1) then
      begin
        { mov rax, [rbp + Offset] }
        x64_mov_reg_mem(8, rRAX, rRBP, Syms[i].Offset, True);
        EmitDynArrayReleaseForSym(i);
      end
      else if (Syms[i].TypeKind = tyRecord) and not Syms[i].IsArray and
              RecordHasManagedFields(SymTR[i].RecId) then
      begin
        { Record value local with managed fields (AnsiString, dynamic-array, or
          nested): release them under the heap lock. rbx = record address. }
        x64_push_reg(rRBX);                                      { push rbx }
        x64_lea_reg_mem(8, rRBX, rRBP, Syms[i].Offset, True);     { lea rbx, [rbp+off] }
        EmitAcquireHeapLock;
        EmitManagedRecordReleaseLocked(SymTR[i].RecId);
        EmitReleaseHeapLock;
        x64_pop_reg(rRBX);                                       { pop rbx }
      end;
    end;
  end;
end;

{ ---- Zero-init contract (feature-zero-init-contract) ---------------------
  The "a managed slot is nil before first use" guarantee has ONE owner in the
  compiler: EmitZeroFrameSlot. Callers state the frame offset and the extent in
  bytes; the machine sequence is this routine's business, nobody else's. The
  extent may be any size — the >pointer-sized case routes to the RTL primitive
  PXXMemZero, so there is no per-target "managed aggregates not supported" hole.
  x86-64 keeps `rep stosb` inline (the hardware memset), which is the same
  guarantee produced by the same owner, not a second implementation of it. }
procedure EmitZeroFrameSlot(frameOff, nBytes: Integer);
var helperPi: Integer;
begin
  if nBytes <= 0 then Exit;

  if nBytes <= TARGET_PTR_SIZE then
  begin
    { Single pointer-sized handle (AnsiString / dyn-array): one nil store. }
    if TargetArch = TARGET_I386 then
      begin EmitB($C7); EmitB($85); EmitI32(frameOff); EmitI32(0); end  { mov dword [ebp+off], 0 }
    else if TargetArch = TARGET_ARM32 then
    begin
      EmitLoadImmArm32(9, frameOff);
      EmitI32($E08B9009);                        { add r9, fp, r9 }
      EmitI32($E3A00000);                        { mov r0, #0 }
      EmitI32($E5890000);                        { str r0, [r9] }
    end
    else if TargetArch = TARGET_AARCH64 then
    begin
      EmitLoadImmA64(9, frameOff);
      EmitI32($8B0903A9);                        { add x9, x29, x9 }
      EmitI32($F900013F);                        { str xzr, [x9] }
    end
    else if TargetArch = TARGET_XTENSA then
    begin
      EmitFrameAddrXtensa(reg_xtensa_a8, frameOff);
      xtensa_movi(reg_xtensa_a9, 0);
      xtensa_s32i(reg_xtensa_a9, reg_xtensa_a8, 0);
    end
    else if TargetArch = TARGET_RISCV32 then
    begin
      EmitLoadImmRISCV32(reg_t0, frameOff);
      rv32_add(reg_t0, reg_s0, reg_t0);
      rv32_sw(reg_zero, reg_t0, 0);
    end
    else
      begin EmitB($48); EmitB($C7); EmitB($85); EmitI32(frameOff); EmitI32(0); end; { mov qword [rbp+off], 0 }
    Exit;
  end;

  { Managed aggregate (record with managed fields / variant / COM fat pointer /
    array of managed): zero the whole extent. }
  if TargetArch = TARGET_X86_64 then
  begin
    EmitB($48); EmitB($8D); EmitB($BD); EmitI32(frameOff);   { lea rdi, [rbp+off] }
    EmitB($48); EmitB($31); EmitB($C0);                      { xor rax, rax }
    EmitB($48); EmitB($C7); EmitB($C1); EmitI32(nBytes);     { mov rcx, nBytes }
    EmitB($F3); EmitB($AA);                                  { rep stosb }
    Exit;
  end;

  helperPi := FindProc('PXXMemZero');
  if helperPi < 0 then Error('compiler error: PXXMemZero not found');
  if TargetArch = TARGET_I386 then
  begin
    EmitB($8D); EmitB($85); EmitI32(frameOff);   { lea eax, [ebp+off] }
    EmitB($50);                                  { push dest (param 0, deepest) }
    EmitB($68); EmitI32(nBytes);                 { push count }
    EmitCallProc(helperPi);
    EmitB($81); EmitB($C4); EmitI32(8);          { add esp, 8 }
  end
  else if TargetArch = TARGET_ARM32 then
  begin
    EmitLoadImmArm32(0, frameOff);
    EmitI32($E08B0000);                          { add r0, fp, r0 (dest) }
    EmitLoadImmArm32(1, nBytes);                 { r1 = count }
    EmitCallProc(helperPi);
  end
  else if TargetArch = TARGET_AARCH64 then
  begin
    EmitLoadImmA64(9, frameOff);
    EmitI32($8B0903A0);                          { add x0, x29, x9 (dest) }
    EmitLoadImmA64(1, nBytes);                   { x1 = count }
    EmitCallProc(helperPi);
  end
  else if TargetArch = TARGET_RISCV32 then
  begin
    EmitLoadImmRISCV32(reg_t0, frameOff);
    rv32_add(reg_a0, reg_s0, reg_t0);            { a0 = dest }
    EmitLoadImmRISCV32(reg_a1, nBytes);          { a1 = count }
    EmitCallProc(helperPi);
  end
  else if TargetArch = TARGET_XTENSA then
  begin
    EmitFrameAddrXtensa(reg_xtensa_a8, frameOff);
    if XtensaABI = XTENSA_ABI_WINDOWED then
    begin
      xtensa_mov(reg_xtensa_a10, reg_xtensa_a8);       { arg0 = dest }
      EmitLoadConstXtensa(reg_xtensa_a11, nBytes);     { arg1 = count }
    end
    else
    begin
      xtensa_mov(reg_xtensa_a2, reg_xtensa_a8);        { arg0 = dest }
      EmitLoadConstXtensa(reg_xtensa_a3, nBytes);      { arg1 = count }
    end;
    EmitCallProc(helperPi);
  end
  else
    Error('compiler error: EmitZeroFrameSlot: unhandled target');
end;

{ Stash the caller's hidden aggregate-result destination pointer (passed in the
  per-target indirect-result register) into the proc's dest-sym frame slot, right
  after the prologue and before the param-copy loop can clobber that register.
  Shared by the Pascal (pasparser_*.inc) and C (cparser.inc) routine emitters so an
  aggregate-returning C function uses the same convention as a Pascal one. }
procedure EmitAggregateDestStash(procIdx: Integer);
var idx: Integer;
begin
  if (procIdx < 0) or (ProcAggregateDestSym[procIdx] < 0) then Exit;
  idx := ProcAggregateDestSym[procIdx];
  if TargetArch = TARGET_I386 then
    { i386 carries the hidden destination pointer in ecx; stash it before the
      param-copy loop clobbers ecx. }
    begin EmitB($89); EmitB($8D); EmitI32(Syms[idx].Offset); end { mov [ebp+off], ecx }
  else if TargetArch = TARGET_AARCH64 then
  begin
    { aarch64 carries the hidden destination in x8 (AAPCS XR). }
    EmitLoadImmA64(9, Syms[idx].Offset);
    EmitI32($8B0903A9);                                 { add x9, x29, x9 }
    EmitI32($F9000128);                                 { str x8, [x9] }
  end
  else if TargetArch = TARGET_ARM32 then
  begin
    { arm32 carries the hidden destination in r12 (ip, a scratch reg). }
    EmitLoadImmArm32(9, Syms[idx].Offset);
    EmitI32($E08B9009);                                 { add r9, fp, r9 }
    EmitI32($E589C000);                                 { str r12, [r9] }
  end
  else if TargetArch = TARGET_RISCV32 then
  begin
    { riscv32 carries the hidden destination in t1 (no dedicated indirect-result
      reg); stash it before the param-copy loop clobbers t1. }
    EmitLoadImmRISCV32(reg_t0, Syms[idx].Offset);
    rv32_add(reg_t0, reg_s0, reg_t0);
    rv32_sw(reg_t1, reg_t0, 0);
  end
  else if TargetArch = TARGET_XTENSA then
  begin
    { xtensa Call0 carries the hidden destination in a8 (a caller-saved temp
      outside the a2-a7 arg set); stash it before the param-copy clobbers a8. }
    if XtensaABI = XTENSA_ABI_CALL0 then
    begin
      EmitFrameAddrXtensa(reg_xtensa_a9, Syms[idx].Offset);
      xtensa_s32i(reg_xtensa_a8, reg_xtensa_a9, 0);
    end
    else
    begin
      { Windowed has no register that survives the call8 rotation, so the
        destination travels as the ABI's implicit FIRST argument word — callee
        a2 (the caller's a10), exactly where xtensa gcc puts the pointer for a
        >16-byte struct return; every declared parameter shifts up one word
        (the param-copy loop starts at pw=1). a15 is the frame base here: a7 is
        not the frame pointer yet (it still holds incoming argument word 5). }
      if (Syms[idx].Offset >= -128) and (Syms[idx].Offset <= 127) then
        xtensa_addi(reg_xtensa_a9, reg_xtensa_a15, Syms[idx].Offset)
      else
        Error('target xtensa windowed: aggregate-result frame offset out of range');
      xtensa_s32i(reg_xtensa_a2, reg_xtensa_a9, 0);
    end;
  end
  else
    begin EmitB($4C); EmitB($89); EmitB($95); EmitI32(Syms[idx].Offset); end; { mov [rbp+off], r10 }
end;

procedure EmitProcEpilog(retSymIdx: Integer);
var sz, i, procIdx, mek: Integer;
begin
  if TargetArch = TARGET_I386 then
  begin
    EmitProcScopeExitCleanupForTarget(retSymIdx);

    { Ordinal or pointer-sized (AnsiString/pointer/class handle) results.
      Legacy fixed string returns the address of its inline buffer. }
    if retSymIdx >= 0 then
    begin
      if ABIRetViaHiddenDestProc(CurProc) and
         (CurProc >= 0) and (ProcAggregateDestSym[CurProc] >= 0) then
      begin
        { Aggregate result: copy the Result local into the caller's hidden
          destination (pointer the prologue stashed in the dest-sym slot from
          ecx), return that pointer in eax. Mirrors the x86-64 rep-movsb path. }
        if (Syms[retSymIdx].TypeKind = tyRecord) and not Syms[retSymIdx].IsArray and
           RecordHasManagedFields(SymTR[retSymIdx].RecId) then
        begin
          { A reused destination still holds the previous value's managed
            handles; release them before the raw copy orphans them. }
          EmitB($8B); EmitB($85); EmitI32(Syms[ProcAggregateDestSym[CurProc]].Offset); { mov eax, [ebp+destOff] }
          EmitB($50);                                { push eax (arg0 recAddr) }
          EmitB($68); EmitDataRef(-(RECORD_RTTI_DATAREF_BASE + (SymTR[retSymIdx].RecId - REC_UCLASS_BASE))); { push desc }
          procIdx := FindProc('PXXRecordRelease');
          if procIdx < 0 then Error('compiler error: PXXRecordRelease not found');
          EmitCallProc(procIdx);
          EmitB($81); EmitB($C4); EmitI32(8);        { add esp, 8 }
        end;
        EmitB($8B); EmitB($BD); EmitI32(Syms[ProcAggregateDestSym[CurProc]].Offset); { mov edi, [ebp+destOff] }
        EmitB($89); EmitB($F8);                                  { mov eax, edi (return value) }
        EmitB($8D); EmitB($B5); EmitI32(Syms[retSymIdx].Offset); { lea esi, [ebp+resultOff] }
        sz := AggRetCopySize(retSymIdx);
        EmitB($B9); EmitI32(sz);                                 { mov ecx, sz }
        EmitB($F3); EmitB($A4);                                  { rep movsb }
      end
      else if Syms[retSymIdx].TypeKind = tyString then
      begin
        if Syms[retSymIdx].Kind = skGlobal then
          begin EmitB($B8); EmitGlobRef(Syms[retSymIdx].Offset); end          { mov eax, abs32 }
        else if (Syms[retSymIdx].Kind = skParam) and Syms[retSymIdx].IsRef then
          begin EmitB($8B); EmitB($85); EmitI32(Syms[retSymIdx].Offset); end  { mov eax, [ebp+off] }
        else if Syms[retSymIdx].Kind = skLocal then
          begin EmitB($8D); EmitB($85); EmitI32(Syms[retSymIdx].Offset); end  { lea eax, [ebp+off] }
        else
          Error('target i386: only local/global string function results supported yet');
      end
      else if Syms[retSymIdx].IsArray and (Syms[retSymIdx].ArrLen = -1) and
              (Syms[retSymIdx].Kind = skLocal) then
      begin
        { DYNAMIC-ARRAY result: the slot holds one pointer-sized heap
          handle, exactly like the tyAnsiString case below — not an aggregate.
          All four cross epilogues refused it outright on `IsArray`, so a
          function returning `array of T` did not BUILD for any non-x86-64
          target (three whole tests unbuildable). A STATIC array result IS the
          unsupported case and still errors below.

          Loaded at POINTER width by hand: EmitLoadVar* sizes by
          TypeSize(Syms[].TypeKind), and an array's TypeKind is its ELEMENT
          kind, so `array of Char` would come back through a byte load with the
          handle's top bytes gone — the truncation EmitLoadVarA64 carried until
          today. Ownership transfers to the caller, which is why every managed-
          local cleanup above already skips retSymIdx.
          bug-a-a-function-returning-a-dynamic-array-is-refused-on-every-cross-target }
        EmitB($8B); EmitB($85); EmitI32(Syms[retSymIdx].Offset);   { mov eax, [ebp+off] }
      end
      else
      begin
        if Syms[retSymIdx].IsArray or (Syms[retSymIdx].Kind <> skLocal) or
           not (TypeIsOrdinal(Syms[retSymIdx].TypeKind) or TypeIsFloat(Syms[retSymIdx].TypeKind) or
                (Syms[retSymIdx].TypeKind in [tyAnsiString, tyPointer, tyClass])) then
          Error('target i386: only ordinal/pointer/string function results supported yet');
        { Float result: the 8-byte Double slot loads into eax:edx (the sz=8 path
          below); a 4-byte Single loads into eax. The caller moves eax(:edx) ->
          xmm0 for the SSE value model. See feature-cross-float-returns. }
        { Load at the result's width and extend to a full eax. A 1-byte
          Boolean/Char slot loaded with a plain 4-byte mov drags in 3 garbage
          bytes, which then defeats callers that `not`/`xor` or test eax. }
        sz := TypeSize(Syms[retSymIdx].TypeKind);
        if sz = 1 then
        begin
          if TypeSigned(Syms[retSymIdx].TypeKind) then
            begin EmitB($0F); EmitB($BE); EmitB($85); EmitI32(Syms[retSymIdx].Offset); end  { movsx eax, byte [ebp+off] }
          else
            begin EmitB($0F); EmitB($B6); EmitB($85); EmitI32(Syms[retSymIdx].Offset); end; { movzx eax, byte [ebp+off] }
        end
        else if sz = 2 then
        begin
          if TypeSigned(Syms[retSymIdx].TypeKind) then
            begin EmitB($0F); EmitB($BF); EmitB($85); EmitI32(Syms[retSymIdx].Offset); end  { movsx eax, word [ebp+off] }
          else
            begin EmitB($0F); EmitB($B7); EmitB($85); EmitI32(Syms[retSymIdx].Offset); end; { movzx eax, word [ebp+off] }
        end
        else
        begin
          EmitB($8B); EmitB($85); EmitI32(Syms[retSymIdx].Offset);                          { mov eax, [ebp+off] }
          if sz = 8 then
            begin EmitB($8B); EmitB($95); EmitI32(Syms[retSymIdx].Offset + 4); end;          { mov edx, [ebp+off+4] (Int64 hi) }
        end;
      end;
    end;
    EmitB($C9); EmitB($C3);                                    { leave; ret }
    Exit;
  end;
{$ifndef PXX_NO_ARM32}
  if TargetArch = TARGET_ARM32 then
  begin
    EmitProcScopeExitCleanupForTarget(retSymIdx);

    if retSymIdx >= 0 then
    begin
      if ABIRetViaHiddenDestProc(CurProc) and
         (CurProc >= 0) and (ProcAggregateDestSym[CurProc] >= 0) then
      begin
        { Aggregate result: copy the Result local into the caller's hidden
          destination (pointer the prologue stashed from r12), return the
          pointer in r0. r5=src, r6=dst, r4=count for EmitArm32CopyBytes. }
        if (Syms[retSymIdx].TypeKind = tyRecord) and not Syms[retSymIdx].IsArray and
           RecordHasManagedFields(SymTR[retSymIdx].RecId) then
        begin
          { A reused destination still holds the previous value's managed
            handles; release them before the raw copy orphans them. }
          EmitLoadVarArm32(ProcAggregateDestSym[CurProc]);  { r0 = dest ptr }
          EmitLoadDataRefArm32(1,
            -(RECORD_RTTI_DATAREF_BASE + (SymTR[retSymIdx].RecId - REC_UCLASS_BASE)));
          procIdx := FindProc('PXXRecordRelease');
          if procIdx < 0 then Error('compiler error: PXXRecordRelease not found');
          EmitCallProc(procIdx);
        end;
        EmitLoadVarArm32(ProcAggregateDestSym[CurProc]);  { r0 = dest ptr }
        EmitI32($E1A06000);                               { mov r6, r0 (dst) }
        EmitLoadVarAddrArm32(retSymIdx);                  { r0 = &Result }
        EmitI32($E1A05000);                               { mov r5, r0 (src) }
        sz := AggRetCopySize(retSymIdx);
        EmitLoadImmArm32(4, sz);                          { r4 = byte count }
        EmitArm32CopyBytes(4, 5, 6);
        EmitLoadVarArm32(ProcAggregateDestSym[CurProc]);  { r0 = dest (return value) }
      end
      else if Syms[retSymIdx].TypeKind = tyString then
        { Legacy inline string struct ([len][data]): return its address — the
          global lives in BSS, a local on the frame (mirrors the x86-64 path).
          Managed tyAnsiString results stay pointer-sized handles below. }
        EmitLoadVarAddrArm32(retSymIdx)
      else if Syms[retSymIdx].IsArray and (Syms[retSymIdx].ArrLen = -1) and
              (Syms[retSymIdx].Kind = skLocal) then
      begin
        { DYNAMIC-ARRAY result: the slot holds one pointer-sized heap
          handle, exactly like the tyAnsiString case below — not an aggregate.
          All four cross epilogues refused it outright on `IsArray`, so a
          function returning `array of T` did not BUILD for any non-x86-64
          target (three whole tests unbuildable). A STATIC array result IS the
          unsupported case and still errors below.

          Loaded at POINTER width by hand: EmitLoadVar* sizes by
          TypeSize(Syms[].TypeKind), and an array's TypeKind is its ELEMENT
          kind, so `array of Char` would come back through a byte load with the
          handle's top bytes gone — the truncation EmitLoadVarA64 carried until
          today. Ownership transfers to the caller, which is why every managed-
          local cleanup above already skips retSymIdx.
          bug-a-a-function-returning-a-dynamic-array-is-refused-on-every-cross-target }
        EmitLoadImmArm32(9, Syms[retSymIdx].Offset);
        EmitI32($E08B9009);                          { add r9, fp, r9 }
        EmitI32($E5990000);                          { ldr r0, [r9] = handle }
      end
      else
      begin
        if Syms[retSymIdx].IsArray or (Syms[retSymIdx].Kind <> skLocal) or
           not (TypeIsOrdinal(Syms[retSymIdx].TypeKind) or TypeIsFloat(Syms[retSymIdx].TypeKind) or
                (Syms[retSymIdx].TypeKind in [tyAnsiString, tyPointer, tyClass])) then
          Error('target arm32: only ordinal/pointer/string function results supported yet');
        if (Syms[retSymIdx].TypeKind = tyInt64) or
           (Syms[retSymIdx].TypeKind = tyUInt64) or
           (Syms[retSymIdx].TypeKind = tyDouble) or (Syms[retSymIdx].TypeKind = tyExtended) then
          { Int64 / Double result: raw 8 bytes in r0:r1 (lo:hi). The caller moves
            r0:r1 -> d0 for the float value model. See feature-cross-float-returns. }
          EmitLoadVar64Arm32(retSymIdx)
        else
          { ordinal / pointer / Single (4-byte bits in r0). }
          EmitLoadVarArm32(retSymIdx);
      end;
    end;
    EmitI32($E1A0D00B);  { mov sp, fp }
    EmitI32($E8BD8800);  { pop {fp, pc} }
    Exit;
  end;
{$endif}
{$ifndef PXX_NO_AARCH64}
  if TargetArch = TARGET_AARCH64 then
  begin
    EmitProcScopeExitCleanupForTarget(retSymIdx);
    if retSymIdx >= 0 then
    begin
      if ABIRetViaHiddenDestProc(CurProc) and
         (CurProc >= 0) and (ProcAggregateDestSym[CurProc] >= 0) then
      begin
        { Aggregate result: copy the Result local into the caller's hidden
          destination (pointer the prologue stashed from x8), return the pointer
          in x0. EmitA64CopyBytes uses x4/x5/x6 + w8, leaving x0 intact. }
        if (Syms[retSymIdx].TypeKind = tyRecord) and not Syms[retSymIdx].IsArray and
           RecordHasManagedFields(SymTR[retSymIdx].RecId) then
        begin
          { A reused destination still holds the previous value's managed
            handles; release them before the raw copy orphans them. }
          EmitLoadVarA64(ProcAggregateDestSym[CurProc]);   { x0 = dest ptr }
          EmitLoadDataRefA64(1,
            -(RECORD_RTTI_DATAREF_BASE + (SymTR[retSymIdx].RecId - REC_UCLASS_BASE)));
          procIdx := FindProc('PXXRecordRelease');
          if procIdx < 0 then Error('compiler error: PXXRecordRelease not found');
          EmitCallProc(procIdx);
        end;
        EmitLoadVarA64(ProcAggregateDestSym[CurProc]);   { x0 = dest ptr }
        EmitI32($AA0003E6);                              { mov x6, x0 (dst) }
        EmitLoadImmA64(9, Syms[retSymIdx].Offset);
        EmitI32($8B0903A5);                              { add x5, x29, x9 (src = &Result) }
        sz := AggRetCopySize(retSymIdx);
        EmitLoadImmA64(4, sz);                           { x4 = byte count }
        EmitA64CopyBytes(4, 5, 6);
      end
      else if Syms[retSymIdx].TypeKind = tyString then
      begin
        if Syms[retSymIdx].Kind = skGlobal then
        begin
          EmitI32($18000040);  { ldr w0, [pc+8] }
          EmitI32($14000002);  { b [pc+8] }
          EmitGlobRef(Syms[retSymIdx].Offset);
        end
        else if Syms[retSymIdx].Kind = skLocal then
        begin
          EmitLoadImmA64(9, Syms[retSymIdx].Offset);
          EmitI32($8B0903A0);  { add x0, x29, x9 }
        end
        else
          Error('target aarch64: only local/global string function results supported yet');
      end
      else if Syms[retSymIdx].IsArray and (Syms[retSymIdx].ArrLen = -1) and
              (Syms[retSymIdx].Kind = skLocal) then
      begin
        { DYNAMIC-ARRAY result: the slot holds one pointer-sized heap
          handle, exactly like the tyAnsiString case below — not an aggregate.
          All four cross epilogues refused it outright on `IsArray`, so a
          function returning `array of T` did not BUILD for any non-x86-64
          target (three whole tests unbuildable). A STATIC array result IS the
          unsupported case and still errors below.

          Loaded at POINTER width by hand: EmitLoadVar* sizes by
          TypeSize(Syms[].TypeKind), and an array's TypeKind is its ELEMENT
          kind, so `array of Char` would come back through a byte load with the
          handle's top bytes gone — the truncation EmitLoadVarA64 carried until
          today. Ownership transfers to the caller, which is why every managed-
          local cleanup above already skips retSymIdx.
          bug-a-a-function-returning-a-dynamic-array-is-refused-on-every-cross-target }
        EmitLoadVarA64(retSymIdx);   { the ArrLen = -1 arm loads full ptr width }
      end
      else
      begin
        if Syms[retSymIdx].IsArray or (Syms[retSymIdx].Kind <> skLocal) or
           not (TypeIsOrdinal(Syms[retSymIdx].TypeKind) or TypeIsFloat(Syms[retSymIdx].TypeKind) or
                (Syms[retSymIdx].TypeKind in [tyAnsiString, tyPointer, tyClass])) then
          Error('target aarch64: only ordinal/pointer/string function results supported yet');
        { Float result: the value model carries it as double-bits in x0 (the
          return reg). EmitLoadVarA64 loads a Double's 8 bytes / widens a Single
          into x0 already. See feature-cross-float-returns. }
        EmitLoadVarA64(retSymIdx);
      end;
    end;
    { -O3 unified residency (aarch64 mirror): restore the caller's x19..x24 /
      d8..d13 from the save-iff-used slots before the frame teardown. Reached
      by every return path; x0 (the result) and x29 are still valid, x9 is
      scratch. Counts are 0 outside -O3 aarch64 bodies, so -O0/-O2 emission is
      untouched. }
    for i := 0 to RcResidentCount - 1 do
    begin
      EmitLoadImmA64(9, RcResidentSaveOff[i]);
      EmitI32($8B0903A9);                        { add x9, x29, x9 }
      EmitI32($F9400120 or RcResidentReg[i]);    { ldr x19..x24, [x9] }
    end;
    for i := 0 to FrResidentCount - 1 do
    begin
      EmitLoadImmA64(9, FrResidentSaveOff[i]);
      EmitI32($8B0903A9);                        { add x9, x29, x9 }
      EmitI32($FD400120 or (8 + i));             { ldr d(8+i), [x9] }
    end;
    EmitI32($910003BF);  { mov sp, x29 }
    EmitI32($A8C17BFD);  { ldp x29, x30, [sp], #16 }
    EmitI32($D65F03C0);  { ret }
    Exit;
  end;
{$endif}
  if TargetArch = TARGET_XTENSA then
  begin
    EmitProcScopeExitCleanupForTarget(retSymIdx);
    if retSymIdx >= 0 then
    begin
      if ABIRetViaHiddenDestProc(CurProc) and
         (CurProc >= 0) and (ProcAggregateDestSym[CurProc] >= 0) then
      begin
        { Aggregate (record) result: copy the Result local into the caller's
          hidden destination and return that pointer in a2.
          PXXMemMove(dest, &Result, size). Call0 took the pointer from a8;
          windowed took it from incoming argument word 0 — either way the
          prologue stashed it in a frame slot by now. }
        EmitFrameAddrXtensa(reg_xtensa_a3, Syms[retSymIdx].Offset);   { a3 = &Result (src) }
        EmitLoadVarXtensa(ProcAggregateDestSym[CurProc]);             { a2 = dest ptr }
        sz := AggRetCopySize(retSymIdx);
        EmitLoadConstXtensa(reg_xtensa_a4, sz);                       { a4 = byte count }
        procIdx := FindProc('PXXMemMove');
        if procIdx < 0 then Error('compiler error: PXXMemMove not found');
        if XtensaABI = XTENSA_ABI_WINDOWED then
        begin
          { Outgoing args go in a10..a12; a2 (the dest) survives the rotation,
            so it is already the return value when the copy comes back. }
          xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);
          xtensa_mov(reg_xtensa_a11, reg_xtensa_a3);
          xtensa_mov(reg_xtensa_a12, reg_xtensa_a4);
          EmitCallProc(procIdx);
        end
        else
        begin
          EmitCallProc(procIdx);
          EmitLoadVarXtensa(ProcAggregateDestSym[CurProc]);           { a2 = dest (return value) }
        end;
      end
      else
      begin
        if Syms[retSymIdx].IsArray or (Syms[retSymIdx].Kind <> skLocal) or
           not (TypeIsOrdinal(Syms[retSymIdx].TypeKind) or TypeIsFloat(Syms[retSymIdx].TypeKind) or
                (Syms[retSymIdx].TypeKind in [tyAnsiString, tyPointer, tyClass])) then
          Error('target xtensa: only ordinal/float/pointer/string function results supported yet');
        { Float result carried as raw bits in the return reg(s): Double = a2:a3
          (8-byte slot), Single = a2 (4-byte slot) — same shape as Int64/ordinal. }
        if (Syms[retSymIdx].TypeKind = tyInt64) or (Syms[retSymIdx].TypeKind = tyUInt64) or
           (Syms[retSymIdx].TypeKind = tyDouble) then
          EmitLoadVar64Xtensa(retSymIdx)   { 64-bit result in a2:a3 }
        else
          EmitLoadVarXtensa(retSymIdx);
      end;
    end;
    if XtensaABI = XTENSA_ABI_WINDOWED then
    begin
      { sp stayed constant through the body, and the window spill area for our
        caller lives at [sp-16], so retw must keep sp as entry set it — no
        restore (matches gcc's bare `retw.n`). }
      xtensa_retw;
    end
    else
    begin
      xtensa_mov(reg_xtensa_sp, reg_xtensa_a15);
      xtensa_l32i(reg_xtensa_a15, reg_xtensa_sp, 8);
      xtensa_l32i(reg_xtensa_a0, reg_xtensa_sp, 12);
      xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 16);
      if (CurProc >= 0) and ProcIsInterrupt[CurProc] then
      begin
        { Restore the interrupted context (mirror of the prologue save area, now at
          sp after the normal frame unwound), then return from the exception via
          `rfe` (PC <- EPC1, PS.EXCM cleared). }
        xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, 0);  xtensa_l32i(reg_xtensa_a3, reg_xtensa_sp, 4);
        xtensa_l32i(reg_xtensa_a4, reg_xtensa_sp, 8);  xtensa_l32i(reg_xtensa_a5, reg_xtensa_sp, 12);
        xtensa_l32i(reg_xtensa_a6, reg_xtensa_sp, 16); xtensa_l32i(reg_xtensa_a7, reg_xtensa_sp, 20);
        xtensa_l32i(reg_xtensa_a8, reg_xtensa_sp, 24); xtensa_l32i(reg_xtensa_a10, reg_xtensa_sp, 28);
        xtensa_l32i(reg_xtensa_a11, reg_xtensa_sp, 32); xtensa_l32i(reg_xtensa_a12, reg_xtensa_sp, 36);
        xtensa_l32i(reg_xtensa_a13, reg_xtensa_sp, 40);
        xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 48);
        xtensa_rfe;
      end
      else
        xtensa_ret;
    end;
    Exit;
  end;
  if TargetArch = TARGET_RISCV32 then
  begin
    EmitProcScopeExitCleanupForTarget(retSymIdx);
    if retSymIdx >= 0 then
    begin
      if ABIRetViaHiddenDestProc(CurProc) and
         (CurProc >= 0) and (ProcAggregateDestSym[CurProc] >= 0) then
      begin
        { Aggregate (record) result: copy the Result local into the caller's
          hidden destination (the pointer the prologue stashed from t1), return
          that pointer in a0. PXXMemMove(dest, &Result, size). }
        if (Syms[retSymIdx].TypeKind = tyRecord) and not Syms[retSymIdx].IsArray and
           RecordHasManagedFields(SymTR[retSymIdx].RecId) then
        begin
          { A reused destination still holds the previous value's managed
            handles; release them before the raw copy orphans them. }
          EmitLoadVarRISCV32(ProcAggregateDestSym[CurProc]); { a0 = dest ptr }
          EmitLoadDataRefRISCV32(reg_a1,
            -(RECORD_RTTI_DATAREF_BASE + (SymTR[retSymIdx].RecId - REC_UCLASS_BASE)));
          procIdx := FindProc('PXXRecordRelease');
          if procIdx < 0 then Error('compiler error: PXXRecordRelease not found');
          EmitCallProc(procIdx);
        end;
        EmitSlotAddrRISCV32(reg_a1, retSymIdx);              { a1 = &Result (src) }
        EmitLoadVarRISCV32(ProcAggregateDestSym[CurProc]);   { a0 = dest ptr }
        sz := AggRetCopySize(retSymIdx);
        EmitLoadImmRISCV32(reg_a2, sz);                       { a2 = byte count }
        procIdx := FindProc('PXXMemMove');
        if procIdx < 0 then Error('compiler error: PXXMemMove not found');
        EmitCallProc(procIdx);
        EmitLoadVarRISCV32(ProcAggregateDestSym[CurProc]);   { a0 = dest (return value) }
      end
      else if Syms[retSymIdx].IsArray and (Syms[retSymIdx].ArrLen = -1) and
              (Syms[retSymIdx].Kind = skLocal) then
      begin
        { DYNAMIC-ARRAY result: the slot holds one pointer-sized heap
          handle, exactly like the tyAnsiString case below — not an aggregate.
          All four cross epilogues refused it outright on `IsArray`, so a
          function returning `array of T` did not BUILD for any non-x86-64
          target (three whole tests unbuildable). A STATIC array result IS the
          unsupported case and still errors below.

          Loaded at POINTER width by hand: EmitLoadVar* sizes by
          TypeSize(Syms[].TypeKind), and an array's TypeKind is its ELEMENT
          kind, so `array of Char` would come back through a byte load with the
          handle's top bytes gone — the truncation EmitLoadVarA64 carried until
          today. Ownership transfers to the caller, which is why every managed-
          local cleanup above already skips retSymIdx.
          bug-a-a-function-returning-a-dynamic-array-is-refused-on-every-cross-target }
        EmitSlotAddrRISCV32(reg_a0, retSymIdx);
        rv32_lw(reg_a0, reg_a0, 0);                  { a0 = handle }
      end
      else
      begin
        if Syms[retSymIdx].IsArray or (Syms[retSymIdx].Kind <> skLocal) or
           not (TypeIsOrdinal(Syms[retSymIdx].TypeKind) or TypeIsFloat(Syms[retSymIdx].TypeKind) or
                (Syms[retSymIdx].TypeKind in [tyAnsiString, tyPointer, tyClass])) then
          Error('target riscv32: only ordinal/float/pointer/string function results supported yet');
        { Float result carried as raw bits in the return reg(s): Double = a0:a1
          (8-byte slot), Single = a0 (4-byte slot) — same shape as Int64/ordinal. }
        if (Syms[retSymIdx].TypeKind = tyInt64) or (Syms[retSymIdx].TypeKind = tyUInt64) or
           (Syms[retSymIdx].TypeKind = tyDouble) then
          EmitLoadVar64RISCV32(retSymIdx)   { 64-bit result in a0:a1 }
        else
          EmitLoadVarRISCV32(retSymIdx);
      end;
    end;
    rv32_addi(reg_sp, reg_s0, 0);
    rv32_lw(reg_s0, reg_sp, 8);
    rv32_lw(reg_ra, reg_sp, 12);
    rv32_addi(reg_sp, reg_sp, 16);
    if (CurProc >= 0) and ProcIsInterrupt[CurProc] then
    begin
      { Restore the interrupted caller-saved context (mirror of the prologue),
        then return from the trap via mret (PC <- mepc). }
      rv32_lw(reg_t0, reg_sp, 0);  rv32_lw(reg_t1, reg_sp, 4);  rv32_lw(reg_t2, reg_sp, 8);
      rv32_lw(reg_t3, reg_sp, 12); rv32_lw(reg_t4, reg_sp, 16); rv32_lw(reg_t5, reg_sp, 20);
      rv32_lw(reg_t6, reg_sp, 24);
      rv32_lw(reg_a0, reg_sp, 28); rv32_lw(reg_a1, reg_sp, 32); rv32_lw(reg_a2, reg_sp, 36);
      rv32_lw(reg_a3, reg_sp, 40); rv32_lw(reg_a4, reg_sp, 44); rv32_lw(reg_a5, reg_sp, 48);
      rv32_lw(reg_a6, reg_sp, 52); rv32_lw(reg_a7, reg_sp, 56);
      rv32_addi(reg_sp, reg_sp, 64);
      rv32_mret;
    end
    else
      rv32_jalr(reg_zero, reg_ra, 0);
    Exit;
  end;
  { Release local managed variables before returning }
  EmitProcScopeExitCleanupForTarget(retSymIdx);

  if retSymIdx >= 0 then
  begin
    if ABIRetViaHiddenDestProc(CurProc) and
       (CurProc >= 0) and (ProcAggregateDestSym[CurProc] >= 0) then
    begin
      { Aggregate results use a hidden caller-owned destination pointer in r10.
        The prologue saves it in a local so nested calls cannot clobber it. }
      if (Syms[retSymIdx].TypeKind = tyRecord) and not Syms[retSymIdx].IsArray and
         RecordHasManagedFields(SymTR[retSymIdx].RecId) then
      begin
        { A reused destination (r := f(...) in a loop, or a re-executed hidden
          temp) still holds the previous value's managed handles; the raw copy
          below would orphan them. Release them first — safe here because the
          body is done reading any argument that may alias the destination,
          and any Result field copied from an alias was retained on copy-in. }
        x64_push_reg(rRBX);
        EmitLoadVar(ProcAggregateDestSym[CurProc]);
        x64_mov_reg_reg(8, rRBX, rRAX);            { rbx = dest }
        EmitAcquireHeapLock;
        EmitManagedRecordReleaseLocked(SymTR[retSymIdx].RecId);
        EmitReleaseHeapLock;
        x64_pop_reg(rRBX);
      end;
      EmitLoadVar(ProcAggregateDestSym[CurProc]);
      EmitB($50);                                  { push original destination }
      EmitB($48); EmitB($89); EmitB($C7);          { mov rdi, rax }
      EmitB($48); EmitB($8D); EmitB($B5); EmitI32(Syms[retSymIdx].Offset); { lea rsi, [rbp+off] }
      sz := AggRetCopySize(retSymIdx);
      EmitB($48); EmitB($B9); EmitI64(sz);          { movabs rcx, byte count }
      EmitB($F3); EmitB($A4);                       { rep movsb }
      EmitB($58);                                   { pop rax = result address }
    end
    else if Syms[retSymIdx].TypeKind = tyString then
    begin
      if Syms[retSymIdx].Kind = skGlobal then
      begin
        { Return BSS address of global string structure }
        EmitB($48); EmitB($C7); EmitB($C0); EmitGlobRef(Syms[retSymIdx].Offset);
      end
      else
      begin
        { Return address of the local string structure on the stack }
        EmitB($48); EmitB($8D); EmitB($85); EmitI32(Syms[retSymIdx].Offset);
      end;
    end
    else if Syms[retSymIdx].IsArray and (Syms[retSymIdx].ArrLen = -1) then
    begin
      { Dynamic-array result: the slot holds a pointer-sized heap handle. Return
        all 8 bytes; a narrow EmitLoadVar keyed on the element type would
        truncate (and sign-extend) the pointer. }
      EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[retSymIdx].Offset); { mov rax, [rbp+off] }
    end
    else if (CurProc >= 0) and ProcCdecl[CurProc] and
            (Syms[retSymIdx].TypeKind = tySingle) and
            (Syms[retSymIdx].Kind = skLocal) then
    begin
      { cdecl (C) function returning `float`: SysV returns a SINGLE in xmm0, and
        the cdecl call site widens it (cvtss2sd) into the double value model. So
        the callee must leave a RAW single in xmm0 — NOT the double that
        EmitLoadVar produces (movss + cvtss2sd). Emitting the widened double let
        the caller's cvtss2sd reinterpret double bits as single => garbage (~0);
        double returns were fine because neither side converts. Load the single
        with no widen and no rax bridge (the cdecl caller reads xmm0, not rax). }
      EmitB($F3); EmitB($0F); EmitB($10); EmitB($85); EmitI32(Syms[retSymIdx].Offset); { movss xmm0, [rbp+off] }
    end
    else
    begin
      EmitLoadVar(retSymIdx);
      { EmitLoadVar leaves a float in xmm0, but the internal call ABI / value
        model carries a float return as double-bits in rax (the caller bridges
        rax->xmm0 after the call). Without this bridge the return value is only
        correct when rax happens to still hold the bits from the last store; a
        loop in the body clobbers rax (e.g. the condition's setcc/test) and the
        result reads as 0. Mirrors the IR_LOAD_SYM bridge in ir_codegen.inc.
        See feature-result-in-loop. }
      if TypeIsFloat(Syms[retSymIdx].TypeKind) then
        begin EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0); end; { movq rax, xmm0 }
    end;
  end;
  { Register calling convention (feature-callconv-register-args): restore the
    caller's r14/r15 (callee-saved) from their reserved frame slots before the
    frame teardown. Reached by every return (early Exit and fall-through both go
    through EmitProcEpilog). rbp is still valid here; rax (the result) untouched. }
  for i := 0 to RcResidentCount - 1 do
  begin
    EmitB($4C); EmitB($8B); EmitB($85 or ((RcResidentReg[i] - 8) shl 3));           { mov r12..r15, [rbp+off] }
    EmitI32(RcResidentSaveOff[i]);
  end;
  { pxx internal ABI (optimization-architecture.md §5b): xmm8..xmm13 are
    callee-saved save-iff-used — restore the caller's registers from the slots
    UnifiedResidencyAssign reserved. Same every-return-path contract as the
    r14/r15 restore above; the float result (if any) is already bridged to rax. }
  for i := 0 to FrResidentCount - 1 do
  begin
    EmitB($F2); EmitB($44); EmitB($0F); EmitB($10);
    EmitB($85 or (i shl 3)); EmitI32(FrResidentSaveOff[i]);          { movsd xmm(8+i), [rbp+off] }
  end;
  { -O3 W1 callee-saved scratch: restore the caller's r12/r13 from their frame
    slots (saved once by CalleeScratchAssign). Reached by every return path,
    exactly like the r14/r15 residency restore above. }
  if CsScratchOn then
  begin
    EmitB($4C); EmitB($8B); EmitB($A5); EmitI32(CsSaveOff12);  { mov r12, [rbp+off] }
    EmitB($4C); EmitB($8B); EmitB($AD); EmitI32(CsSaveOff13);  { mov r13, [rbp+off] }
  end;
  EmitB($C9); EmitB($C3);
end;

{ ===== Call emission ===== }

{ Ensure the external procIdx has a GOT slot; return its ExternalProc[] index. }
function RegisterExternal(procIdx: Integer): Integer;
var i, extIdx: Integer; enm: AnsiString;
begin
  { A `__pxx_p*` name is one of OUR OWN pthread PAL helpers (palpthread.pas),
    not anything a shared library can supply. Reaching this point means a C
    program called into <pthread.h> without --threadsafe, so palpthread was
    never pulled and the extern stayed unbodied — it was then imported from
    libc.so.6, which has never heard of it, and the program died at LOAD with

        symbol lookup error: undefined symbol: __pxx_pmutex_init

    That message names an internal symbol absent from the user's source, after
    a build that reported no diagnostic at all, and survives every link-time
    check because it is a dynamic-loader failure. Refuse here instead — the
    choke point where an unresolved external becomes a real import.

    This fires for `#include <pthread.h>` even when nothing is CALLED, because
    pthread.c is compiled whole and its bodies reference the externs. That is
    not a regression: measured, `pinned` builds that program too and it dies at
    load the same way. Every program this rejects was already broken; the change
    is that it now says so at compile time, with the flag named.
    bug-c-pthread-without-threadsafe-builds-then-dies-at-load }
  { Matched against palpthread's ACTUAL export prefixes, not a bare `__pxx_p`.
    That 7-character test also caught `__pxx_pipe2` and `__pxx_poll`, which are
    pxxcio's ordinary PAL I/O wrappers with no thread content whatsoever — so a
    program that left `pipe()` external was told to rebuild with --threadsafe,
    naming a flag that has nothing to do with it. Surfaced by the --strict-uses
    corpus sweep, which was the only configuration that made pxxcio's body
    invisible and so turned pipe2 into a real external; the over-broad guard is
    latent without it, not introduced by it.
    bug-pascal-uses-is-transitive / task-t-strict-uses-corpus-sweep }
  if (procIdx >= 0) and (procIdx < ProcCount) then
  begin
    enm := Procs[procIdx].Name;
    if ((Copy(enm, 1, 14) = '__pxx_pthread_') or
        (Copy(enm, 1, 13) = '__pxx_pmutex_') or
        (Copy(enm, 1, 12) = '__pxx_pcond_') or
        (enm = '__pxx_ponce') or
        (enm = '__pxx_pmonotonic_ns')) and
       (not ThreadSafeMode) then
      Error(enm + ' needs the thread-safe runtime: rebuild with --threadsafe '
            + '(<pthread.h> lowers onto the pxx thread PAL, which that flag '
            + 'selects; without it this would import a pxx-internal symbol '
            + 'from libc and fail at load)');
    { …and the GENERAL rule the pthread case is one instance of. `__pxx_*` is
      the reserved prefix for pxx's own runtime bridge — the PAL wrappers, the
      heap bridge (__pxx_malloc/_free/_realloc/_atexit), the softfloat and
      cpyext helpers. No shared library on any system exports one, so an
      unbodied `__pxx_*` reaching the import table is ALWAYS a build that will
      die at load with `symbol lookup error`, naming a symbol absent from the
      user's source, after a compile that reported nothing.

      Three separate tickets were that same failure: __pxx_pmutex_init above,
      __pxx_malloc when the C bridge lost its visibility edge
      (bug-c-strict-uses-turns-pxxcio-bridge-into-undefined-dynamic-imports),
      and __pxx_PyErr_Message when two sibling C translation units stopped
      seeing each other. Each was diagnosed from a runtime message and an
      objdump; the invariant is one check at the choke point, which is where
      the parent ticket's IREmitCodeCall(0) guard already showed this shape
      pays. }
    if Copy(enm, 1, 6) = '__pxx_' then
      Error(enm + ' is a pxx-internal runtime symbol and cannot be imported '
            + 'dynamically: no library exports it, so this build would link '
            + 'clean and die at load with "undefined symbol: ' + enm + '". '
            + 'Something that should supply its body is not visible here — a '
            + 'missing `uses` of the unit that defines it, or a C translation '
            + 'unit compiled without its Pascal bridge.');
  end;
  extIdx := -1;
  for i := 0 to ExternalCount-1 do
    if ExternalProc[i] = procIdx then extIdx := i;
  if extIdx < 0 then
  begin
    if ExternalCount >= MAX_EXTERNAL then Error('external function overflow');
    extIdx := ExternalCount;
    ExternalProc[extIdx] := procIdx;
    ExternalGotOff[extIdx] := DataLen;
    for i := 0 to 7 do
    begin
      Data[DataLen] := 0;
      Inc(DataLen);
    end;
    Inc(ExternalCount);
  end;
  Result := extIdx;
end;

{ Emit the indirect call through the external's GOT slot and register the
  fixup. Caller is responsible for argument marshalling, stack alignment, and
  the variadic AL count. }
procedure EmitExternalIndirectCall(extIdx: Integer);
begin
  if DynCallCount >= MAX_CALLFIX then Error('external call fixup overflow');
  { pxx internal ABI: the external callee runs under SysV, where all XMM are
    volatile — save the callee-saved xmm8..13 pool around the call. }
  FloatPoolSave;
  EmitB($FF); EmitB($14); EmitB($25); { call qword ptr [absolute address] }
  DynCallCodePos[DynCallCount] := CodeLen;
  DynCallExtIdx[DynCallCount] := extIdx;
  Inc(DynCallCount);
  EmitI32(0);
  FloatPoolRestore;
end;

{ Load the resolved address of an external routine into rax. Reuses the dynamic
  GOT slot/fixup table used by external calls; x86-64 encodes `mov rax,[abs32]`.
  Other backends still reject this until they grow an equivalent address-load
  sequence. }
procedure EmitExternalProcAddr(procIdx: Integer);
var extIdx: Integer;
begin
  extIdx := RegisterExternal(procIdx);
  if DynCallCount >= MAX_CALLFIX then Error('external call fixup overflow');
  { @extern -> the resolved function pointer in the result register, via the same
    GOT slot the call path uses (PatchDynCallSites patches the address), but with
    a plain load instead of a call. Lets sqlite's unix VFS build its aSyscall[]
    table of pointers to open/close/fstat/... (never called with a :memory: DB). }
  if TargetArch = TARGET_X86_64 then
  begin
    EmitB($48); EmitB($8B); EmitB($04); EmitB($25); { mov rax, [abs GOT slot] }
    DynCallCodePos[DynCallCount] := CodeLen;
    DynCallExtIdx[DynCallCount] := extIdx;
    Inc(DynCallCount);
    EmitI32(0);
  end
  else if TargetArch = TARGET_AARCH64 then
  begin
    DynCallCodePos[DynCallCount] := CodeLen;   { movz/movk pair patched with slot VA }
    DynCallExtIdx[DynCallCount] := extIdx;
    Inc(DynCallCount);
    EmitI32($D2800010);   { movz x16, #0        (lo16 patched) }
    EmitI32($F2A00010);   { movk x16, #0, lsl 16 (hi16 patched) }
    EmitI32($F9400200);   { ldr  x0, [x16]      (resolved fn ptr) }
  end
  else if TargetArch = TARGET_ARM32 then
  begin
    DynCallCodePos[DynCallCount] := CodeLen;   { movw/movt pair patched with slot VA }
    DynCallExtIdx[DynCallCount] := extIdx;
    Inc(DynCallCount);
    EmitI32($E300C000);   { movw ip, #0   (lo16 patched) }
    EmitI32($E340C000);   { movt ip, #0   (hi16 patched) }
    EmitI32($E59C0000);   { ldr  r0, [ip] (resolved fn ptr) }
  end
  else if TargetArch = TARGET_RISCV32 then
  begin
    { Same inline-literal slot the riscv32 external CALL uses (EmitCallProc): the
      DynCall pass patches the 4-byte literal to the resolved fn address. Here we
      just load it into a0 instead of calling it — lets sqlite's unix VFS build
      its aSyscall[] table of open/close/fstat/... pointers. }
    rv32_auipc(reg_a0, 0);            { a0 = PC of this auipc }
    rv32_jal(reg_zero, 8);            { skip the 4-byte literal }
    DynCallCodePos[DynCallCount] := CodeLen;
    DynCallExtIdx[DynCallCount] := extIdx;
    Inc(DynCallCount);
    EmitI32(0);                       { literal: resolved fn addr (patched) }
    rv32_lw(reg_a0, reg_a0, 8);       { a0 = [auipc_pc + 8] = fn addr }
  end
  else
    Error('@ on external routine not supported on this target');
end;

{ aarch64 external call through the GOT slot. The slot's absolute VA (< 2^32
  under ET_EXEC) is built into x16 with movz/movk — both imm16 fields are patched
  by the writeELF DynCall pass (PatchDynCallSites) — then the resolved pointer is
  loaded and called. Caller marshals args into x0..x7 (AAPCS) first. }
procedure EmitExternalCallA64(extIdx: Integer);
begin
  if DynCallCount >= MAX_CALLFIX then Error('external call fixup overflow');
  DynCallCodePos[DynCallCount] := CodeLen;
  DynCallExtIdx[DynCallCount] := extIdx;
  Inc(DynCallCount);
  EmitI32($D2800010);   { movz x16, #0      (lo16 patched) }
  EmitI32($F2A00010);   { movk x16, #0, lsl 16  (hi16 patched) }
  EmitI32($F9400210);   { ldr  x16, [x16]   (resolved fn ptr) }
  EmitI32($D63F0200);   { blr  x16 }
end;

{ arm32 external call through the GOT slot. The slot's absolute VA is built into
  ip (r12) with movw/movt (both patched by the writeELF32 DynCall pass), then the
  resolved pointer is loaded and called. Caller marshals args into r0..r3 first. }
procedure EmitExternalCallArm32(extIdx: Integer);
begin
  if DynCallCount >= MAX_CALLFIX then Error('external call fixup overflow');
  DynCallCodePos[DynCallCount] := CodeLen;
  DynCallExtIdx[DynCallCount] := extIdx;
  Inc(DynCallCount);
  EmitI32($E300C000);   { movw ip, #0    (lo16 patched) }
  EmitI32($E340C000);   { movt ip, #0    (hi16 patched) }
  EmitI32($E59CC000);   { ldr  ip, [ip]  (resolved fn ptr) }
  EmitI32($E12FFF3C);   { blx  ip }
end;

{ Record an internal direct call for relocation.

  EVERY internal direct call, not only the forward ones. The old rule was "record
  it when the callee's address is not known yet, otherwise write the displacement
  and forget" -- which is exactly right until a body between the caller and the
  callee is dropped, at which point the forgotten displacement points into the
  middle of whatever slid into that gap. Recording unconditionally makes the
  table both the complete call graph the DCE pass reads and the complete set of
  call sites it can re-patch; ApplyCallFixups then rewrites displacements that
  were already correct, which costs a pass over an array and changes no byte.
  feature-emission-size-dce }
procedure RecordInternalCall(procIdx: Integer);
var n: Integer;
begin
  if CallFixCount >= CallFixCapacity then
  begin
    if CallFixCapacity = 0 then n := CALLFIX_BASE else n := CallFixCapacity * 2;
    SetLength(CallFix, n);
    CallFixCapacity := n;
  end;
  CallFix[CallFixCount].CodePos := CodeLen;
  CallFix[CallFixCount].ProcIdx := procIdx;
  Inc(CallFixCount);
end;

procedure EmitCallProc(procIdx: Integer);
var extIdx, rvHi, rvLo: Integer;
begin
  if ProcExternal[procIdx] then
  begin
    extIdx := RegisterExternal(procIdx);
    { esp32 targets: indirect call through a 32-bit literal slot. The slot is
      recorded as a DynCall fixup; the ET_REL writer turns it into an
      R_XTENSA_32/R_RISCV_32 data-word reloc against the undefined symbol, so
      no code relocations are needed (the zero-code-reloc property). }
    if TargetArch = TARGET_XTENSA then
    begin
      if DynCallCount >= MAX_CALLFIX then Error('external call fixup overflow');
      XtensaEmitLitHeader;
      DynCallCodePos[DynCallCount] := CodeLen;
      DynCallExtIdx[DynCallCount] := extIdx;
      Inc(DynCallCount);
      EmitI32(0);
      xtensa_l32r(reg_xtensa_a8, $FFFF);
      if XtensaABI = XTENSA_ABI_WINDOWED then
        xtensa_callx8(reg_xtensa_a8)
      else
        xtensa_callx0(reg_xtensa_a8);
      Exit;
    end;
    if TargetArch = TARGET_RISCV32 then
    begin
      if DynCallCount >= MAX_CALLFIX then Error('external call fixup overflow');
      rv32_auipc(reg_t0, 0);
      rv32_jal(reg_zero, 8);
      DynCallCodePos[DynCallCount] := CodeLen;
      DynCallExtIdx[DynCallCount] := extIdx;
      Inc(DynCallCount);
      EmitI32(0);
      rv32_lw(reg_t0, reg_t0, 8);
      rv32_jalr(reg_ra, reg_t0, 0);
      Exit;
    end;
    { Realign the stack to 16 bytes for the SysV call: our internal call
      convention does not keep rsp 16-aligned at every call site, but C
      callees (GTK/GLib) use aligned SSE (movaps) and fault otherwise. This
      path is for register-only externals (no stack args to disturb); the
      stack-spill path in IR_CALL handles its own alignment. Old rsp is saved
      and restored around the call; r11 is scratch under SysV. }
    EmitB($49); EmitB($89); EmitB($E3);             { mov r11, rsp }
    EmitB($48); EmitB($83); EmitB($E4); EmitB($F0); { and rsp, -16 }
    EmitB($48); EmitB($83); EmitB($EC); EmitB($08); { sub rsp, 8 }
    EmitB($41); EmitB($53);                         { push r11 }
    EmitB($31); EmitB($C0);                         { xor eax, eax (al=0) }
    EmitExternalIndirectCall(extIdx);
    EmitB($41); EmitB($5B);                         { pop r11 }
    EmitB($4C); EmitB($89); EmitB($DC);             { mov rsp, r11 }
    Exit;
  end;
  { Cross-section internal call (flash <-> iram): a direct PC-relative call can't
    span the two ELF sections (the linker places .iram1.text far from flash
    .text), so load the callee's absolute address from a relocated 32-bit literal
    and call indirect — same shape as an external call, but the literal is
    relocated against the callee proc's own local symbol (IramCallFix). ESP only;
    flash<->flash and iram<->iram stay direct PC-relative below. }
  if (TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32) then
    if (((CurProc >= 0) and ProcIram[CurProc]) <> ProcIram[procIdx]) then
    begin
      if IramCallFixCount >= MAX_CALLFIX then Error('iram call fixup overflow');
      if TargetArch = TARGET_RISCV32 then
      begin
        rv32_auipc(reg_t0, 0);
        rv32_jal(reg_zero, 8);
        IramCallFix[IramCallFixCount].CodePos := CodeLen;
        IramCallFix[IramCallFixCount].ProcIdx := procIdx;
        Inc(IramCallFixCount);
        EmitI32(0);
        rv32_lw(reg_t0, reg_t0, 8);
        rv32_jalr(reg_ra, reg_t0, 0);
      end
      else
      begin
        XtensaEmitLitHeader;
        IramCallFix[IramCallFixCount].CodePos := CodeLen;
        IramCallFix[IramCallFixCount].ProcIdx := procIdx;
        Inc(IramCallFixCount);
        EmitI32(0);
        xtensa_l32r(reg_xtensa_a8, $FFFF);
        if XtensaABI = XTENSA_ABI_WINDOWED then
          xtensa_callx8(reg_xtensa_a8)
        else
          xtensa_callx0(reg_xtensa_a8);
      end;
      Exit;
    end;
  if TargetArch = TARGET_ARM32 then
  begin
    RecordInternalCall(procIdx);
    if Procs[procIdx].BodyAddr >= 0 then
      EmitI32($EB000000 or ((((Procs[procIdx].BodyAddr - CodeLen) div 4) - 2) and $00ffffff))
    else
      EmitI32($EB000000);
    Exit;
  end;
  if TargetArch = TARGET_AARCH64 then
  begin
    RecordInternalCall(procIdx);
    if Procs[procIdx].BodyAddr >= 0 then
      EmitI32($94000000 or (((Procs[procIdx].BodyAddr - CodeLen) div 4) and $03ffffff))
    else
      EmitI32($94000000);
    Exit;
  end;
  if TargetArch = TARGET_XTENSA then
  begin
    RecordInternalCall(procIdx);
    if Procs[procIdx].BodyAddr >= 0 then
    begin
      if XtensaABI = XTENSA_ABI_WINDOWED then
        xtensa_call8(Procs[procIdx].BodyAddr - CodeLen)
      else
        xtensa_call0(Procs[procIdx].BodyAddr - CodeLen);
    end
    else
    begin
      if XtensaABI = XTENSA_ABI_WINDOWED then
        xtensa_call8(0)
      else
        xtensa_call0(0);
    end;
    Exit;
  end;
  if TargetArch = TARGET_RISCV32 then
  begin
    { auipc+jalr (full 32-bit range) rather than a single JAL (+/-1MB) — a large
      binary like cross lua (1.75MB code) places callees beyond JAL's reach, so a
      truncated offset jumped to garbage. reg_t0 is a caller-saved scratch. }
    RecordInternalCall(procIdx);
    if Procs[procIdx].BodyAddr >= 0 then
    begin
      RISCVPcrelSplit(Procs[procIdx].BodyAddr - CodeLen, rvHi, rvLo);
      rv32_auipc(reg_t0, rvHi);
      rv32_jalr(reg_ra, reg_t0, rvLo);
    end
    else
    begin
      rv32_auipc(reg_t0, 0);
      rv32_jalr(reg_ra, reg_t0, 0);
    end;
    Exit;
  end;
  EmitB($E8);
  RecordInternalCall(procIdx);
  if Procs[procIdx].BodyAddr >= 0 then
    EmitI32(Procs[procIdx].BodyAddr - (CodeLen + 4))
  else
    EmitI32(0);
end;

procedure ApplyCallFixups;
var i, procIdx, rvHi, rvLo: Integer;
begin
  if DebugTrace then
    for i := 0 to ProcCount-1 do
      writeln('Proc ', i, ': ', Procs[i].Name, ' at CodePos ', Procs[i].BodyAddr);
  for i := 0 to CallFixCount-1 do
  begin
    procIdx := CallFix[i].ProcIdx;
    if Procs[procIdx].BodyAddr < 0 then
      Error('unresolved forward: ' + Procs[procIdx].Name);
    if TargetArch = TARGET_ARM32 then
      Patch32(CallFix[i].CodePos, $EB000000 or ((((Procs[procIdx].BodyAddr - CallFix[i].CodePos) div 4) - 2) and $00ffffff))
    else if TargetArch = TARGET_AARCH64 then
      Patch32(CallFix[i].CodePos, $94000000 or (((Procs[procIdx].BodyAddr - CallFix[i].CodePos) div 4) and $03ffffff))
    else if TargetArch = TARGET_XTENSA then
    begin
      if XtensaABI = XTENSA_ABI_WINDOWED then
        Patch24(CallFix[i].CodePos, EncodeXtensaCall8(CallFix[i].CodePos, Procs[procIdx].BodyAddr))
      else
        Patch24(CallFix[i].CodePos, EncodeXtensaCall0(CallFix[i].CodePos, Procs[procIdx].BodyAddr));
    end
    else if TargetArch = TARGET_RISCV32 then
    begin
      { auipc+jalr pair (see EmitCallProc): patch both words. }
      RISCVPcrelSplit(Procs[procIdx].BodyAddr - CallFix[i].CodePos, rvHi, rvLo);
      Patch32(CallFix[i].CodePos, EncodeRISCVAuipc(reg_t0, rvHi));
      Patch32(CallFix[i].CodePos + 4, EncodeRISCVJalr(reg_ra, reg_t0, rvLo));
    end
    else
      Patch32(CallFix[i].CodePos, Procs[procIdx].BodyAddr - (CallFix[i].CodePos + 4));
  end;
end;


function GetASTStrVal(node: Integer): AnsiString;
var s: AnsiString; i, off, len, j: Integer;
begin
  s := '';
  off := ASTSOffset[node];
  len := ASTSLen[node];
  i := 0;
  while i < len do
  begin
    j := off + i;
    AppendChar(s, TokChars[j]);
    Inc(i);
  end;
  Result := s;
end;

function GetASTIdentName(node: Integer): AnsiString;
var s: AnsiString; i, off, len, j: Integer;
begin
  s := '';
  off := ASTSOffset[node];
  len := ASTSLen[node];
  i := 0;
  while i < len do
  begin
    j := off + i;
    AppendChar(s, TokChars[j]);
    Inc(i);
  end;
  Result := s;
end;

function ResolveNodeRec(node: Integer): Integer; forward;   { NodeMetaclassCi's FIELD arm needs it; real body just below }

function NodeMetaclassCi(node: Integer): Integer;
{ The class index a node's METACLASS VALUE refers to, or -1 when the node is not
  one. A metaclass value is a `class of T` — a tyPointer whose pointee is a class
  with a concrete id — and it can be spelled five ways, each of which carries the
  pointee somewhere different:

    a `class of T` VARIABLE          AN_IDENT     Syms[].PtrElemTk/PtrElemRec
    an inline metaclass CAST         AN_PTR_CAST  AliasElemTk/AliasElemRec
    an ELEMENT of an array of them   AN_INDEX     the ARRAY symbol's PtrElem*
    a metaclass-typed FIELD          AN_FIELD     UFldPtrElemTk/UFldPtrElemRec
    the RESULT of a function         AN_CALL      ProcRetPtrElemTk/ProcRetPtrElemRec

  The first four were each taught to be a receiver one ticket at a time, as four
  copies of this test in ParseLValueAST's suffix loop, and the fifth was the
  spelling nobody had added — `Give.Kind` reached the pointer-field walker and
  came out as IR_UNSUPPORTED. One predicate instead of five arms, so the next
  spelling is added once.
  bug-a-a-metaclass-returned-from-a-function-is-not-a-receiver }
var mcRec, mcFi, si: Integer;
begin
  Result := -1;
  if node < 0 then Exit;
  if ASTKind[node] = AN_IDENT then
  begin
    si := Integer(ASTIVal[node]);
    if (si >= 0) and (si < SymCount) and (Syms[si].TypeKind = tyPointer) and
       (Syms[si].PtrElemTk = tyClass) and (Syms[si].PtrElemRec >= REC_UCLASS_BASE) then
      Result := Syms[si].PtrElemRec - REC_UCLASS_BASE;
  end
  else if ASTKind[node] = AN_PTR_CAST then
  begin
    si := Integer(ASTIVal[node]);
    if (si >= 0) and (IntToTypeKind(AliasElemTk[si]) = tyClass) and
       (AliasElemRec[si] >= REC_UCLASS_BASE) then
      Result := AliasElemRec[si] - REC_UCLASS_BASE;
  end
  else if (ASTKind[node] = AN_INDEX) and (ASTLeft[node] >= 0) and
          (ASTKind[ASTLeft[node]] = AN_IDENT) then
  begin
    si := Integer(ASTIVal[ASTLeft[node]]);
    if (si >= 0) and (si < SymCount) and Syms[si].IsArray and
       (Syms[si].ElemType = tyPointer) and (Syms[si].PtrElemTk = tyClass) and
       (Syms[si].PtrElemRec >= REC_UCLASS_BASE) then
      Result := Syms[si].PtrElemRec - REC_UCLASS_BASE;
  end
  else if ASTKind[node] = AN_FIELD then
  begin
    mcRec := ResolveNodeRec(ASTLeft[node]);
    mcFi := -1;
    if mcRec >= REC_UCLASS_BASE then
      mcFi := FindUField(mcRec - REC_UCLASS_BASE, GetASTIdentName(node));
    if (mcFi >= 0) and (IntToTypeKind(UFldPtrElemTk[mcFi]) = tyClass) and
       (UFldPtrElemRec[mcFi] >= REC_UCLASS_BASE) then
      Result := UFldPtrElemRec[mcFi] - REC_UCLASS_BASE;
  end
  else if ASTKind[node] = AN_CALL then
  begin
    si := Integer(ASTIVal[node]);
    if (si >= 0) and (si < ProcCount) and (Procs[si].RetType = tyPointer) and
       (IntToTypeKind(ProcRetPtrElemTk[si]) = tyClass) and
       (ProcRetPtrElemRec[si] >= REC_UCLASS_BASE) then
      Result := ProcRetPtrElemRec[si] - REC_UCLASS_BASE;
  end;
end;

function ResolveNodeRec(node: Integer): Integer;
var baseNode, baseRec, fIdx, innerNode: Integer; fieldName: AnsiString;
begin
  if ASTKind[node] = AN_IDENT then
  begin
    { Array symbols store their ELEMENT record in ElemRecName, not RecName
      (RecName is for a plain scalar/record-typed symbol) -- a recurring
      landmine throughout this codebase. Reachable from C's `arr->field`
      where `arr` is an array (C array-to-pointer decay lets `->` apply to
      an array; CNodeIsPointer's array exclusion means cparser.inc builds a
      plain AN_FIELD directly over the array AN_IDENT, not a dereferenced
      pointer, so this path sees an array base where Pascal code never
      would). Reading RecName there previously resolved REC_NONE, which
      cascaded into the field's type tag defaulting to tyInteger (4 bytes)
      instead of the real (often 8-byte pointer) field type — the
      truncated/sign-extended values in
      bug-c-arrow-on-array-store-of-call-result-clobbered. }
    if Syms[ASTIVal[node]].IsArray then
      Result := Syms[ASTIVal[node]].ElemRecName
    else
      Result := Syms[ASTIVal[node]].RecName;
  end
  else if ASTKind[node] = AN_COMPOUND_LITERAL then
    { C99 compound literal — its record is the hidden temp's RecName. }
    Result := Syms[Integer(ASTIVal[node])].RecName
  else if ASTKind[node] = AN_AS_CAST then
    { `obj as T` yields type T — so (obj as T).field/.method resolves against T. }
    Result := REC_UCLASS_BASE + Integer(ASTIVal[node])
  else if ASTKind[node] = AN_CLASS_CAST then
    { `TClass(obj)` hard cast yields type TClass — same record resolution. }
    Result := REC_UCLASS_BASE + Integer(ASTIVal[node])
  else if ((ASTKind[node] = AN_CALL) or (ASTKind[node] = AN_VIRTUAL_CALL) or
           (ASTKind[node] = AN_CLASS_VIRTUAL_CALL) or (ASTKind[node] = AN_INTF_CALL)) and
          (Integer(ASTIVal[node]) >= 0) and (Integer(ASTIVal[node]) < ProcCount) then
    { A CALL's record is its return type's. A property GETTER is a call, so without this
      `for x in o.Bag` (Bag a property) could not tell that the container was a class at all.
      Guarded on a real proc index: the special-builtin calls carry a NEGATIVE id there. }
  begin
    Result := ProcRetRecId[Integer(ASTIVal[node])];
    { A RECORD-FACTORY call (TPt.Create(...) — a record CONSTRUCTOR) has no
      return-rec on the proc (ctors return nothing); its record is the hidden
      LIFTED TEMP's. Without this, `TPt.Create(1,2) + TPt.Create(3,4)` could
      not find the record's operator overload
      (bug-pascal-operator-on-record-call-result). }
    if (Result = REC_NONE) and (ASTLiftedVar[node] >= 0) and
       (ASTLiftedVar[node] < SymCount) then
      Result := Syms[ASTLiftedVar[node]].RecName;
  end
  else if (ASTKind[node] = AN_CALL) and (Integer(ASTIVal[node]) < 0) and
          (ASTRight[node] >= REC_UCLASS_BASE) then
    { A CONSTRUCTION — the GetMem-shaped call NilPy builds for `Cls(...)`. Its
      proc id is a negative builtin marker, so the branch above skips it, and the
      record it yields sits in ASTRight. Without this the construction had no
      class identity at all: `Path("d") / "sub"` could not find the operator
      overload (it fell into numeric division), and the same blindness is what
      makes `Cls().method()` fail to resolve. }
    Result := ASTRight[node]
  else if ASTKind[node] = AN_COMMA then
    { `(a, b)` yields b's value, so its record is b's. Without this a struct-valued
      comma resolved to REC_NONE and a call marshalled it as a SCALAR: csmith's
      `func_10(((*g_3), g_15), ...)` -- a struct handed over by value through a comma
      -- segfaulted, while the same struct passed directly was fine. }
    Result := ResolveNodeRec(ASTRight[node])
  else if ASTKind[node] = AN_ASSIGN then
    { `x = y` yields the value STORED, so its record is the DESTINATION's — the
      same rule the comma arm above states for its right operand, and the type
      half of the aggregate rule the AN_ASSIGN lowering states in ir.inc.
      Without it a struct assignment handed to a by-value parameter resolved to
      REC_NONE, so the argument temp was sized by the REC_NONE fallback (8
      bytes) and only the first eightbyte of the struct was copied: csmith seed
      91110 passed `func_27(((*l_1698) = l_1697), ...)` and the callee read a
      16-byte struct whose second half was stack garbage — every VALUE derived
      from the first field was right, which is why it took a checksum to see.
      bug-c-a-struct-assignment-passed-by-value-copies-only-eight-bytes }
    Result := ResolveNodeRec(ASTLeft[node])
  else if ASTKind[node] = AN_FIELD then
  begin
    Result := RecFieldRecId(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node));
  end
  else if ASTKind[node] = AN_INDEX then
  begin
    if ASTKind[ASTLeft[node]] = AN_IDENT then
    begin
      if Syms[ASTIVal[ASTLeft[node]]].TypeKind = tyPointer then
        Result := Syms[ASTIVal[ASTLeft[node]]].PtrElemRec
      else
        Result := Syms[ASTIVal[ASTLeft[node]]].ElemRecName;
    end
    else if ASTKind[ASTLeft[node]] = AN_FIELD then
    begin
      baseRec := ResolveNodeRec(ASTLeft[ASTLeft[node]]);
      fieldName := GetASTIdentName(ASTLeft[node]);
      fIdx := -1;
      if baseRec >= REC_UCLASS_BASE then
        fIdx := FindUField(baseRec - REC_UCLASS_BASE, fieldName);
      if (fIdx >= 0) and (UFldTk[fIdx] = Ord(tyPointer)) then
        Result := UFldPtrElemRec[fIdx]
      else
        Result := ResolveNodeRec(ASTLeft[node]);
    end
    else if ASTKind[ASTLeft[node]] = AN_INDEX then
      Result := ResolveNodeRec(ASTLeft[node])
    else if (ASTKind[ASTLeft[node]] = AN_CALL) or
            (ASTKind[ASTLeft[node]] = AN_VIRTUAL_CALL) or
            (ASTKind[ASTLeft[node]] = AN_CLASS_VIRTUAL_CALL) or
            (ASTKind[ASTLeft[node]] = AN_INTF_CALL) or
            (ASTKind[ASTLeft[node]] = AN_CALL_IND) then
      { An array-returning call indexed directly: `MkR[i].field`. ProcRetRecId
        of an array-of-record result already holds the ELEMENT record, which is
        what the index yields — so the ordinary call arm answers it. Every OTHER
        base kind had a case here and a call did not, so this fell to REC_NONE,
        the field lookup found nothing, and the `.field` was applied at OFFSET 0:
        `MkR[1].b` and `MkR[1].c` both answered `MkR[1].a`, silently.
        bug-a-indexing-a-function-call-result-drops-the-field-selector }
      Result := ResolveNodeRec(ASTLeft[node])
    else if ASTKind[ASTLeft[node]] = AN_ADDR then
      { `(&X)[i]` indexes a pointer to X, so the element record is X's own record. }
      Result := ResolveNodeRec(ASTLeft[ASTLeft[node]])
    else if ASTKind[ASTLeft[node]] = AN_PTR_CAST then
      { `((T *) x)[i]` — element record is the cast's pointee record (alias table).
        Without this the record id is lost and the subsequent `.field` type-tag
        defaults to tyInteger (4 bytes), truncating 8-byte pointer fields — the
        duktape value-stack `((duk_tval *) ...)[i].v.heaphdr` access, whose
        truncated pointer later crashes duk_pcompile. }
      if ASTIVal[ASTLeft[node]] >= 0 then
        Result := AliasElemRec[ASTIVal[ASTLeft[node]]]
      else
        Result := REC_NONE
    else
      Result := REC_NONE;
  end
  else if ASTKind[node] = AN_DEREF then
  begin
    baseNode := ASTLeft[node];
    if ASTIVal[node] > 0 then
      { Synthesised record deref (e.g. the for-in generator desugar derefs the
        CoCurrent address into the loop var): the record id is carried directly
        on the deref node, since the base is an untyped Int64 call result. }
      Result := ASTIVal[node]
    else if ASTKind[baseNode] = AN_IDENT then
      Result := Syms[ASTIVal[baseNode]].PtrElemRec
    else if ASTKind[baseNode] = AN_FIELD then
    begin
      baseRec := ResolveNodeRec(ASTLeft[baseNode]);
      fieldName := GetASTIdentName(baseNode);
      fIdx := -1;
      if baseRec >= REC_UCLASS_BASE then
        fIdx := FindUField(baseRec - REC_UCLASS_BASE, fieldName);
      if fIdx >= 0 then
        Result := UFldPtrElemRec[fIdx]
      else
        Result := REC_NONE;
    end
    else if ASTKind[baseNode] = AN_ADDR then
      Result := ResolveNodeRec(ASTLeft[baseNode])
    else if ASTKind[baseNode] = AN_INDEX then
    begin
      innerNode := ASTLeft[baseNode];
      if ASTKind[innerNode] = AN_IDENT then
        Result := Syms[ASTIVal[innerNode]].PtrElemRec
      else if ASTKind[innerNode] = AN_FIELD then
      begin
        baseRec := ResolveNodeRec(ASTLeft[innerNode]);
        fieldName := GetASTIdentName(innerNode);
        fIdx := -1;
        if baseRec >= REC_UCLASS_BASE then
          fIdx := FindUField(baseRec - REC_UCLASS_BASE, fieldName);
        if fIdx >= 0 then
          Result := UFldPtrElemRec[fIdx]
        else
          Result := REC_NONE;
      end
      else
        Result := REC_NONE;
    end
    else if ASTKind[baseNode] = AN_PTR_CAST then
    begin
      if ASTIVal[baseNode] >= 0 then
        Result := AliasElemRec[ASTIVal[baseNode]]
      else
        Result := REC_NONE;
    end
    else if ASTKind[baseNode] = AN_CALL then
    begin
      { f()^ : the pointed-at record comes from the callee's return element. }
      if ASTIVal[baseNode] >= 0 then
        Result := ProcRetPtrElemRec[ASTIVal[baseNode]]
      else
        Result := REC_NONE;
    end
    else
      Result := REC_NONE;
  end
  else if ASTKind[node] = AN_CALL then
  begin
    if ASTIVal[node] = -Ord(tkGetMem) then
      Result := ASTRight[node]
    else if ASTIVal[node] >= 0 then
      Result := ProcRetRecId[ASTIVal[node]]
    else
      Result := REC_NONE;
  end
  else if ASTKind[node] = AN_METACLASS_NEW then
    { `classRefVar.Create` yields an instance of the metaclass's base class;
      the record id is stashed in ASTSLen at parse time. }
    Result := ASTSLen[node]
  else if ASTKind[node] = AN_PTR_CAST then
  begin
    if ASTIVal[node] >= 0 then
      Result := AliasElemRec[ASTIVal[node]]
    else
      Result := REC_NONE;
  end
  else if ASTKind[node] = AN_BINOP then
  begin
    { An overloaded operator on record/class operands resolves to its result
      record (the call returns an aggregate). Without this, an inferred
      `var c := a + b` gets REC_NONE -> wrong RecSize -> truncated/garbage copy. }
    fIdx := FindOpOverload(ASTIVal[node], ASTTk[ASTLeft[node]], ResolveNodeRec(ASTLeft[node]));
    if fIdx >= 0 then
      Result := ProcRetRecId[fIdx]
    else
      Result := REC_NONE;
  end
  else if ASTKind[node] = AN_TERNARY then
  begin
    { A record-valued conditional (`cond ? recA : recB`) has the arms' record
      type. Without this a NESTED struct ternary resolved REC_NONE -> the outer
      arm's hidden temp got no RecName -> wrong RecSize -> garbage copy. }
    Result := ResolveNodeRec(ASTLeft[ASTRight[node]]);
    if Result = REC_NONE then Result := ResolveNodeRec(ASTRight[ASTRight[node]]);
  end
  else
    Result := REC_NONE;
end;

function DynArrayNodeDepth(node: Integer): Integer;
{ Remaining dynamic-array nesting of an AST expression. Keep this parser-side
  helper here because selectors are typed before IR lowering runs. }
var depth: Integer;
begin
  Result := 0;
  if node < 0 then Exit;
  if ASTKind[node] = AN_IDENT then
  begin
    if Syms[ASTIVal[node]].IsArray and (Syms[ASTIVal[node]].ArrLen = -1) then
      Result := SymDynDepth[ASTIVal[node]];
  end
  else if ASTKind[node] = AN_INDEX then
  begin
    depth := DynArrayNodeDepth(ASTLeft[node]);
    if depth > 0 then Result := depth - 1;
  end;
end;

function IsNodeArray(node: Integer): Boolean;
begin
  Result := False;
  if DynArrayNodeDepth(node) > 0 then
    Result := True
  else if ASTKind[node] = AN_IDENT then
    Result := Syms[ASTIVal[node]].IsArray
  else if ASTKind[node] = AN_FIELD then
    Result := RecFieldIsArray(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node));
end;

procedure ResolvePendingPointerAliases;
var
  i, ci, targetAlias, a: Integer;
  targetName: AnsiString;
begin
  for i := 0 to AliasCount - 1 do
  begin
    if (AliasTk[i] = Ord(tyPointer)) and (AliasElemRec[i] = REC_NONE) and (AliasTargetNLen[i] > 0) then
    begin
      targetName := GetSliceName(AliasTargetNOff[i], AliasTargetNLen[i]);
      ci := FindUClass(targetName);
      if ci >= 0 then
      begin
        if UClsIsRecord[ci] then
          AliasElemTk[i] := Ord(tyRecord)
        else
          AliasElemTk[i] := Ord(tyClass);
        AliasElemRec[i] := REC_UCLASS_BASE + ci;
        if AliasPtrDepth[i] = 1 then
        begin
          AliasPtrBaseTk[i] := AliasElemTk[i];
          AliasPtrBaseRec[i] := AliasElemRec[i];
        end;
      end
      else
      begin
        targetAlias := FindTypeAlias(targetName);
        if (targetAlias >= 0) and (AliasTk[targetAlias] = Ord(tyPointer)) and
           (AliasPtrDepth[targetAlias] > 0) and (AliasElemTk[i] = Ord(tyPointer)) then
        begin
          AliasPtrBaseTk[i] := AliasPtrBaseTk[targetAlias];
          AliasPtrBaseRec[i] := AliasPtrBaseRec[targetAlias];
        end
        else if (targetAlias >= 0) and (AliasTk[targetAlias] <> Ord(tyPointer)) and
                (AliasElemRec[targetAlias] <> REC_NONE) then
        begin
          { Forward pointee resolved to a plain (non-pointer) type alias — e.g. a
            cross-unit record alias `TRec3 = urec.TRec;`. The classic self-
            referential-record patch above (FindUClass) only covers a pointee that
            is itself a fresh `record`/`class` declaration; it misses a pointee
            that is an ALIAS to one. Left unpatched, AliasPtrBaseTk/BaseRec[i] keep
            the placeholder stashed when `PRec3 = ^TRec3;` was first parsed (before
            TRec3 existed), so every later `PRec3`-typed param/var is bound to the
            wrong record — self-consistent through that pointer, but disagreeing
            with the correctly-resolved TRec3 alias used by direct field access.
            bug-pascal-transitive-unit-crashes-at-startup-unless-named-first. }
          AliasElemTk[i] := AliasTk[targetAlias];
          AliasElemRec[i] := AliasElemRec[targetAlias];
          if AliasPtrDepth[i] = 1 then
          begin
            AliasPtrBaseTk[i] := AliasElemTk[i];
            AliasPtrBaseRec[i] := AliasElemRec[i];
          end;
        end;
      end;
    end;
  end;

  { Now the record FIELDS declared through one of those aliases. A field's pointee
    was copied out of the alias at AddUField time, which for the classic self-
    referential idiom

      type PNode = ^TNode;  TNode = record v: Integer; next: PNode; end;

    is BEFORE the loop above learns what TNode is — so `next` kept REC_NONE, the
    deref `p^.next^` lost the record identity, and every field after it resolved at
    offset 0. `p^.next^.v` still "worked" (v IS at offset 0), which is what hid this:
    only a second field, `p^.next^.next`, read back the wrong slot. }
  for i := 0 to UFldCount - 1 do
  begin
    a := UFldPtrAlias[i];
    if (UFldTk[i] = Ord(tyPointer)) and (UFldPtrElemRec[i] = REC_NONE) and
       (a >= 0) and (a < AliasCount) and (AliasElemRec[a] <> REC_NONE) then
    begin
      UFldPtrElemTk[i] := AliasElemTk[a];
      UFldPtrElemRec[i] := AliasElemRec[a];
    end;
  end;
end;

{ ===== Expression parser ===== }
