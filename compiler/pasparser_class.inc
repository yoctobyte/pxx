{ ===== pasparser_class.inc — Pascal frontend: class/record member support ====

  Carved out of pasparser_*.inc, byte-for-byte, by
  refactor-a-carve-out-plexer-pparser-so-p-owns-its-own-files.

  Owned by Track P (Pascal frontend). Included from compiler.pas at exactly the
  point it used to occupy, so include ORDER is unchanged — that is what makes
  the carve-out provable by the self-host fixedpoint rather than by reading it.

  Contents: what a class or advanced-record BODY needs — the soft keywords that
  open a member or visibility section, visibility enforcement for fields and
  methods, class variables, class constants and their mangling, nested types,
  and registering the class-like type itself.

  DO NOT factor anything here into a shared helper with pyparser.inc/cparser.inc.
  What is shared between frontends is the AST and the IR, never the parser:
  devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md }

function IsClassMemberStartWord(const s: AnsiString): Boolean;
{ Soft keywords that open a class member or visibility section but lex as plain
  identifiers (they are not reserved words). A name list inside a class body must
  stop here instead of eating the word as another name. }
begin
  Result := CaseEqual(s, 'private') or CaseEqual(s, 'protected') or
            CaseEqual(s, 'public') or CaseEqual(s, 'published') or
            CaseEqual(s, 'constructor') or CaseEqual(s, 'destructor');
end;

{ The class/record that DECLARES the field at UFld index fIdx (its window
  contains fIdx). -1 if none — the caller then skips the visibility check. }
function FieldDeclClass(fIdx: Integer): Integer;
var c: Integer;
begin
  FieldDeclClass := -1;
  for c := 0 to UClsCount - 1 do
    if (fIdx >= UClsFBase[c]) and (fIdx < UClsFBase[c] + UClsFCount[c]) then
      begin FieldDeclClass := c; Exit; end;
end;

{ The class/record that DECLARES the method at UMth index mIdx. -1 if none. }
function MethDeclClass(mIdx: Integer): Integer;
var c: Integer;
begin
  MethDeclClass := -1;
  for c := 0 to UClsCount - 1 do
    if (mIdx >= UClsMBase[c]) and (mIdx < UClsMBase[c] + UClsMCount[c]) then
      begin MethDeclClass := c; Exit; end;
end;

{ Member-access control (feature member-visibility). No-op unless
  StrictVisibility (the PXX dialect is lax by default). Rejects an access to a
  member of visibility `vis` declared in class `declCi` from a context FPC would
  forbid. Context comes from globals: CurrentUnitIdx (accessing unit) and
  CurSelfClass (the class whose method is being compiled). FPC scoping:
  private/protected are UNIT-scoped (whole declaring unit sees them); the strict
  variants are TYPE-scoped (declaring class + — for strict protected — its
  descendants). A missing/unknown declCi fails OPEN (no rejection). }
procedure EnforceMemberVis(declCi, vis: Integer; const memberName: AnsiString);
var accUnit, accCi: Integer; sameUnit, inHier, ok: Boolean; vn: AnsiString;
begin
  if not StrictVisibility then Exit;
  if (declCi < 0) or (declCi >= UClsCount) then Exit;
  if vis = VIS_PUBLIC then Exit;
  accUnit := CurrentUnitIdx;
  if CurSelfClass >= REC_UCLASS_BASE then accCi := CurSelfClass - REC_UCLASS_BASE else accCi := -1;
  sameUnit := (accUnit = UClsUnitIdx[declCi]);
  inHier := (accCi = declCi) or ((accCi >= 0) and IsSubclassOf(accCi, declCi));
  ok := False;
  if vis = VIS_PRIVATE then ok := sameUnit
  else if vis = VIS_PROTECTED then ok := sameUnit or inHier
  else if vis = VIS_STRICT_PRIVATE then ok := (accCi = declCi)
  else if vis = VIS_STRICT_PROTECTED then ok := inHier;
  if ok then Exit;
  if vis = VIS_PRIVATE then vn := 'private'
  else if vis = VIS_PROTECTED then vn := 'protected'
  else if vis = VIS_STRICT_PRIVATE then vn := 'strict private'
  else vn := 'strict protected';
  Error('cannot access ' + vn + ' member "' + memberName + '" of ' +
        GetTokenStrFromRaw(UClsNOff[declCi], UClsNLen[declCi]) +
        ' from here (--strict-visibility)');
end;

{ Enforce access control for a field `fieldName` of class/record `recId` at a
  genuine access site. No-op unless StrictVisibility (so the lax default runs no
  FindUField and stays byte-identical). }
procedure EnforceFieldVis(recId: Integer; const fieldName: AnsiString);
var fi: Integer;
begin
  if not StrictVisibility then Exit;
  if recId < REC_UCLASS_BASE then Exit;
  fi := FindUField(recId - REC_UCLASS_BASE, fieldName);
  if fi >= 0 then EnforceMemberVis(FieldDeclClass(fi), UFldVis[fi], fieldName);
end;

{ Enforce access control for a METHOD call at a committed dispatch site (the
  resolved UMth index). No-op unless StrictVisibility. Call it only where the
  method call is actually being built, never on a speculative probe — a probe
  that would fall through to another meaning must not error. }
procedure EnforceMethVis(mIdx: Integer; const methName: AnsiString);
begin
  if not StrictVisibility then Exit;
  if mIdx < 0 then Exit;
  EnforceMemberVis(MethDeclClass(mIdx), UMthVis[mIdx], methName);
end;

function FindClassVar(ci: Integer; const name: AnsiString): Integer;
{ Class-variable lookup by (class ci, name), walking up the parent chain so a
  subclass sees an inherited `class var`. Returns the backing global var sym idx,
  or -1. }
var i, cur: Integer;
begin
  Result := -1;
  cur := ci;
  while cur >= 0 do
  begin
    for i := 0 to ClassVarCount - 1 do
      if (ClassVarCi[i] = cur) and
         CaseEqual(GetTokenStrFromRaw(ClassVarNOff[i], ClassVarNLen[i]), name) then
      begin Result := ClassVarSym[i]; Exit; end;
    cur := UClsParent[cur];
  end;
end;

function FindVarSym(const name: AnsiString): Integer;
{ FindSym, plus the bare `class var` a method body may name without a qualifier.

  FindSym only knows plain scoped symbols. A class var is reachable inside its own
  class's methods through the ClassVar registry, and ParseLValueAST does that lookup
  when it parses an lvalue — so an *expression* naming a class var has always worked.
  What did not work is the intrinsics that resolve their OPERAND themselves with a raw
  FindSym before handing it to ParseLValueAST: they saw -1 and silently took whatever
  their no-symbol arm was. For SetLength that arm classifies the target as a STRING, so
  `SetLength(G, n)` on a dynamic-array class var wrote a string header over the array
  handle and the next read segfaulted. For SizeOf it was the honest
  `SizeOf: unknown type or variable`.

  One lookup, one answer: an intrinsic that wants "the symbol this name denotes here"
  calls THIS, not FindSym. Roughly forty other operand lookups in this file still call
  FindSym directly; each is a one-word change when its own ticket arrives — do not
  grow a second class-var branch beside one
  (devdocs/dev/normalise-dont-special-case.md). }
begin
  Result := FindSym(name);
  if (Result < 0) and (CurMethClass >= REC_UCLASS_BASE) and (CurProc >= 0) then
    Result := FindClassVar(CurMethClass - REC_UCLASS_BASE, name);
end;

function ClassConstMangle(ownerCi: Integer; const nm: AnsiString): AnsiString;
{ The mangled backing key a class const lives under in the ordinary const tables
  (Syms skConst / StrConst / SetConst). Keyed by the OWNING class's NAME (unique
  per program) so an inherited const resolves to the ancestor that declared it,
  reconstructed identically from ClassConstCi at every access path. The '$cc$'
  prefix cannot occur in a user identifier, so it never collides with a global of
  the same bare name. }
begin
  ClassConstMangle := '$cc$' + GetTokenStrFromRaw(UClsNOff[ownerCi], UClsNLen[ownerCi]) + '.' + nm;
end;

function FindNestedType(ci: Integer; const nm: AnsiString): Integer;
{ A type declared inside class `ci`'s body, by its BARE name — walking own ->
  ancestors, the same order FindClassConst uses, because a nested type is
  inherited exactly as a class const is. -1 when this class chain declares none.
  bug-a-duplicate-class-name-check-is-scope-blind }
var i, c: Integer;
begin
  Result := -1;
  c := ci;
  while c >= 0 do
  begin
    for i := 0 to NestedTypeCount - 1 do
      if (NestedTypeOwner[i] = c) and CaseEqual(NestedTypeName[i], nm) then
      begin
        Result := NestedTypeCi[i];
        Exit;
      end;
    c := UClsParent[c];
  end;
end;

function NestedOwnerCi(const nm: AnsiString): Integer;
{ The UClass row a `TOuter.TInner` qualifier names as its OUTER scope — a class
  OR a record. A record body now claims its nested types the same way a class
  body does (ParseRecordFields), so every `TOuter.` walk must accept one: the
  expression path gated on IsClassType and therefore refused
  `TRec.TNestedClass.Create` while the identical shape under a class worked.
  Class-first, so today's behaviour is unchanged wherever a class of the name
  exists (see FindUClassNonRecord's note on same-named rows). }
begin
  Result := FindUClassNonRecord(nm);
  if Result < 0 then Result := FindUClass(nm);
end;

{ Scan — WITHOUT consuming — the `TOuter.TInner[.TDeeper…]` qualifier run that
  starts at the current token (`nm` = the outermost spelling, CurTok = that
  identifier, Tokens[TokPos] = the '.' after it). Returns the DEEPEST nested
  UClass row the registry resolves, -1 when the leading name owns no nested
  types or the run resolves none. `hops` is how many `.ident` pairs resolved and
  `lastName` the final bare spelling.

  Scanning rather than consuming is what lets a caller decide before it commits:
  a nested RECORD must be taken through the registry (scope-correctly), while a
  nested subrange/enum/array is not a UClass row at all and belongs to
  ParseTypeKind, which has its own strip. A resolver that ate the tokens first
  would have to hand a half-parsed run to that fallback.

  ONE resolver for a rule three constructs need. `var r: TTest.TRecord` had it
  (ParseTypeKind), `SizeOf(TTest.TRecord)` grew its own copy, and `Default()` —
  which also carries a hand-rolled type dispatch — never learned it at all, so
  `Default(TTest.TRecord)` fell past the aggregate arm to the integer-zero one
  and produced an Int64 where a record belonged. It compiled: tdefault8.pp is
  `%NORUN`, so the conformance suite only ever typed it, and at runtime the
  record assignment copied RecSize bytes from address 0 and SEGFAULTED.
  devdocs/dev/normalise-dont-special-case.md }
function ScanNestedTypeRun(const nm: AnsiString; var lastName: AnsiString;
                           var hops: Integer): Integer;
var scanCi, scanPos: Integer;
begin
  Result := -1;
  hops := 0;
  lastName := nm;
  scanCi := NestedOwnerCi(nm);
  if scanCi < 0 then Exit;
  scanPos := TokPos;          { the '.' following the outermost name }
  while (scanPos + 1 < TokCount) and (Tokens[scanPos].Kind = tkDot) and
        (Tokens[scanPos + 1].Kind = tkIdent) and
        (FindNestedType(scanCi, GetTokenStr(scanPos + 1)) >= 0) do
  begin
    scanCi := FindNestedType(scanCi, GetTokenStr(scanPos + 1));
    Result := scanCi;
    lastName := GetTokenStr(scanPos + 1);
    Inc(hops);
    scanPos := scanPos + 2;
  end;
end;

{ Register `nm` as a type declared inside class `ownerCi`'s body. Idempotent per
  (owner, name): a re-parse of the same body must not grow the table. }
procedure AddNestedType(ownerCi: Integer; const nm: AnsiString; ci: Integer);
var i: Integer;
begin
  if (ownerCi < 0) or (ci < 0) then Exit;
  for i := 0 to NestedTypeCount - 1 do
    if (NestedTypeOwner[i] = ownerCi) and CaseEqual(NestedTypeName[i], nm) then
    begin
      NestedTypeCi[i] := ci;
      Exit;
    end;
  if NestedTypeCount >= MAX_TYPEALIAS then Error('too many nested class types');
  NestedTypeOwner[NestedTypeCount] := ownerCi;
  NestedTypeName[NestedTypeCount]  := nm;
  NestedTypeCi[NestedTypeCount]    := ci;
  Inc(NestedTypeCount);
end;

function FindClassConst(ci: Integer; const nm: AnsiString): Integer;
{ Registry lookup by (class ci, bare name), walking the parent chain (own ->
  ancestors) so a subclass method sees an inherited class const. Returns the
  ClassConst* registry index, or -1. Newest-first within a class so a later
  redeclaration shadows an earlier one. }
var i, cur: Integer;
begin
  Result := -1;
  cur := ci;
  while cur >= 0 do
  begin
    for i := ClassConstCount - 1 downto 0 do
      if (ClassConstCi[i] = cur) and CaseEqual(ClassConstName[i], nm) then
        begin Result := i; Exit; end;
    cur := UClsParent[cur];
  end;
end;

function FindClassConstSym(ci: Integer; const nm: AnsiString): Integer;
{ The backing SYMBOL of a class const that has real storage rather than a
  literal value — i.e. a TYPED one, `const X: T = ...`. -1 when this class chain
  declares no const of that name, or when it does but the const is one of the
  untyped forms (whose backing lives in the const tables and is answered by
  EmitClassConstNode instead).

  Exists so the three access paths — qualified `TFoo.X`, bare-in-method, and the
  const-expression folder — ask ONE question rather than each rebuilding the
  mangle-then-FindSym pair. Same shape as FindClassVar above, and for the same
  reason: a typed const, like a class var, is storage the caller must re-enter
  ParseLValueAST on so that suffixes (`[i]`, `.f`, `^`) parse.
  bug-p-two-classes-typed-consts-of-the-same-name-collide }
var reg: Integer;
begin
  Result := -1;
  if ci < 0 then Exit;
  reg := FindClassConst(ci, nm);
  if reg < 0 then Exit;
  Result := FindSym(ClassConstMangle(ClassConstCi[reg], nm));
end;

function EmitClassConstNode(const key: AnsiString; var outTk: TTypeKind): Integer;
{ Build a literal AST node for a resolved class-const backing entry (its mangled
  key). Scalar -> AN_INT_LIT/AN_FLOAT_LIT (carrying any enum identity), string ->
  AN_STR_LIT, set -> AN_SET_CONST_REF — exactly the shapes an ordinary const use
  builds. Does NOT consume the source token (the caller does). Returns the node,
  or -1 if the key has no backing (should not happen once the registry hit). }
var si, sti, seti, nd: Integer;
begin
  Result := -1; outTk := tyUnknown;
  si := FindSym(key);
  if (si >= 0) and (Syms[si].Kind = skConst) then
  begin
    if TypeIsFloat(Syms[si].TypeKind) then nd := AllocNode(AN_FLOAT_LIT)
    else nd := AllocNode(AN_INT_LIT);
    ASTIVal[nd] := Syms[si].ConstVal;
    ASTTk[nd] := Ord(Syms[si].TypeKind);
    ASTEnumId[nd] := SymEnumId[si];
    outTk := Syms[si].TypeKind;
    Result := nd; Exit;
  end;
  sti := FindStrConst(key);
  if sti >= 0 then
  begin
    nd := AllocNode(AN_STR_LIT);
    ASTSOffset[nd] := StrConstSOff[sti];
    ASTSLen[nd] := StrConstSLen[sti];
    ASTTk[nd] := Ord(tyString);
    outTk := tyString;
    Result := nd; Exit;
  end;
  seti := FindSetConst(key);
  if seti >= 0 then
  begin
    nd := AllocNode(AN_SET_CONST_REF);
    ASTIVal[nd] := SetConstOff[seti];
    ASTTk[nd] := Ord(tySet);
    outTk := tySet;
    Result := nd; Exit;
  end;
end;

{ Append a string to the TokChars pool and return its offset (for synthesized
  identifier tokens — the mode-Delphi generics desugar mints alias names). }
function TokCharsAppend(const s: AnsiString): Integer;
var i: Integer;
begin
  Result := TokCharLen;
  for i := 1 to Length(s) do
  begin
    if TokCharLen >= STRING_CAP then Error('token character pool overflow');
    TokChars[TokCharLen] := s[i];
    Inc(TokCharLen);
  end;
end;

function AddClassLikeType(existingCi, tnOff, tnLen: Integer;
                          const tname: AnsiString): Integer;
{ Register a class/record/interface type declaration, honouring an enclosing
  class body as a SCOPE rather than as part of the flat per-unit type table.

  Inside a class body the name is not the unit's, it is that class's:
  `TOuter.TInner` and `TOther.TInner` are two legal, distinct types, and a
  generic's nested type is re-materialised once per specialization on purpose
  (tgeneric72 asserts those two are unique). So when the bare name is already
  taken in this unit, register the nested one under its QUALIFIED name — the
  first keeps the bare one, and every existing unqualified use resolves exactly
  as before — and make it reachable by (owning class, bare name) either way.
  One registry, so the qualified `TOuter.TInner` spelling and a bare `TInner`
  inside the owner's own body find the same entry.
  bug-a-duplicate-class-name-check-is-scope-blind

  ONE function, because the class branch had this and the RECORD branch did
  not: a nested record was registered flat under its bare name and was invisible
  to FindNestedType, so `function TOuter.TInner.M` parsed when TInner was a
  class and failed when it was a record — the exact sibling case
  normalise-dont-special-case is about. rtl-generics' TComparerService.TInstance
  is a nested record. }
var qualNm: AnsiString;
begin
  if (existingCi >= 0) and (ParsingClassBodyCi >= 0) and
     (UClsUnitIdx[existingCi] = CurrentUnitIdx) then
  begin
    qualNm := GetTokenStrFromRaw(UClsNOff[ParsingClassBodyCi],
                                 UClsNLen[ParsingClassBodyCi]) + '.' + tname;
    Result := AddUClass(TokCharsAppend(qualNm), Length(qualNm));
  end
  else
    Result := AddUClass(tnOff, tnLen);
  if ParsingClassBodyCi >= 0 then
    AddNestedType(ParsingClassBodyCi, tname, Result);
end;
