{ ===== pasparser_name.inc — Pascal frontend: names, qualifiers, set consts ===

  Carved out of pasparser_*.inc, byte-for-byte, by
  refactor-a-carve-out-plexer-pparser-so-p-owns-its-own-files.

  Owned by Track P (Pascal frontend). Included from compiler.pas at exactly the
  point it used to occupy, so include ORDER is unchanged — that is what makes
  the carve-out provable by the self-host fixedpoint rather than by reading it.

  Contents: deciding what a NAME is before anything is parsed — which tokens may
  serve as a member/method/declaration name (Read and Write are intrinsics, not
  reserved words), unit qualification and dotted `uses` names, `System.`
  qualifiers, enum type lookup, and the set-literal constant machinery that
  type-checks a set against the enum it is built from.

  It ends with the forward block for the parser proper, which must precede the
  slices that define those routines — that ordering is exactly why this file is
  included where it is.

  DO NOT factor anything here into a shared helper with pyparser.inc/cparser.inc.
  What is shared between frontends is the AST and the IR, never the parser:
  devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md }

{ Read/Write/Readln/Writeln are intrinsics resolved by context at the call site,
  not true reserved words — FPC lets a user declaration shadow them. Accept them
  (and plain identifiers) where a member/method NAME is expected, so e.g.
  TStream.Read / TStream.Write can be declared. The token's SVal carries the
  text, so name capture is unchanged. }
function IsMemberNameTok: Boolean;
begin
  IsMemberNameTok := (CurTok.Kind = tkIdent) or (CurTok.Kind = tkRead) or
    (CurTok.Kind = tkwrite) or (CurTok.Kind = tkReadln) or (CurTok.Kind = tkwriteln) or
    (CurTok.Kind = tkArgCount) or (CurTok.Kind = tkArgStr);   { ParamCount/ParamStr as member names (FPC custapp) }
end;

{ Predefined routines are not reserved words. In declaration-name position they
  must behave like ordinary identifiers so user parameters can shadow Chr/Ord,
  Length, Read/Write, etc. }
{ Method-NAME position: FPC (delphi mode) lets methods be NAMED after built-in
  type keywords — generics.defaults declares `class function Integer(constref
  ALeft, ARight: Integer): Integer;` and ~30 siblings per class. These lex as
  type-keyword tokens whose SVal is EMPTY, so name reads at the sites that
  accept this predicate must go through GetTokenStr, never SVal. }
function IsMethodNameTok: Boolean;
begin
  IsMethodNameTok := IsMemberNameTok or
    (CurTok.Kind in [tkInteger_T, tkBoolean_T, tkChar_T, tkString_T, tkReal_T,
                     tkLongWord_T, tkSingle_T, tkDouble_T, tkExtended_T]);
end;

{ Index-addressed IsMethodNameTok, for LOOKAHEAD past the current token — same
  token set, deliberately sharing the predicate above so the two cannot drift.
  A caller that accepts this must read the name with GetTokenStr(idx): the
  type-keyword tokens carry an EMPTY SVal. }
function IsMethodNameTokAt(idx: Integer): Boolean;
begin
  IsMethodNameTokAt := (idx >= 0) and (idx < TokCount) and
    (Tokens[idx].Kind in [tkIdent, tkRead, tkwrite, tkReadln, tkwriteln,
                          tkArgCount, tkArgStr,
                          tkInteger_T, tkBoolean_T, tkChar_T, tkString_T, tkReal_T,
                          tkLongWord_T, tkSingle_T, tkDouble_T, tkExtended_T]);
end;

function IsDeclNameTok: Boolean;
begin
  if IsMemberNameTok then
  begin
    IsDeclNameTok := True;
    Exit;
  end;
  case CurTok.Kind of
    tkSysOpen, tkSysRead, tkSyswrite, tkSysClose, tkSysFchmod,
    tkArgCount, tkArgStr:
      IsDeclNameTok := True;
  else
    IsDeclNameTok := False;
  end;
end;

{ Resolve a (possibly dotted) unit qualifier at the front of a reference:
  `Unit.Member` or `Posix.SysSocket.Member`. Greedily matches the LONGEST dotted
  prefix that is a compiled unit and still leaves a trailing `.member`, so a
  namespace unit (`Posix.SysSocket`) wins over its first component. Returns the
  unit index and leaves the parser ON the member name; returns -1 and consumes
  nothing when the leading name is not a compiled unit (e.g. `record.field`). }
{ Python attribute names that Pascal reserves. A library exposes them with a
  trailing underscore; this maps the spelling the application writes onto it. }
function PyMapReservedMember(const nm: AnsiString): AnsiString;
begin
  PyMapReservedMember := nm;
  if CaseEqual(nm, 'END') or CaseEqual(nm, 'TYPE') or CaseEqual(nm, 'FILE') or
     CaseEqual(nm, 'LABEL') or CaseEqual(nm, 'SET') or CaseEqual(nm, 'STRING') or
     CaseEqual(nm, 'ARRAY') or CaseEqual(nm, 'RECORD') or CaseEqual(nm, 'TEXT') or
     CaseEqual(nm, 'DIV') or CaseEqual(nm, 'MOD') or CaseEqual(nm, 'IN') or
     CaseEqual(nm, 'IS') or CaseEqual(nm, 'OR') or CaseEqual(nm, 'AND') or
     CaseEqual(nm, 'NOT') or CaseEqual(nm, 'WITH') then
    PyMapReservedMember := nm + '_';
end;

{ A dotted qualifier as NILPY spells its units. Pascal namespace units really
  are named `Posix.SysSocket`, so the candidate below is looked up verbatim; a
  NilPy dotted import is MANGLED to one underscore-joined unit
  (`mypkg.core.origin` -> `mypkg_core_origin`), so the same qualifier text has
  to be tried in that spelling too or `import a.b.c` binds a name no expression
  can then use. Underscore form only under isNilPy, so no Pascal qualifier
  changes meaning. feature-nilpy-dotted-imports-resolve-to-source-files }
function PyFindUnitDotted(const cand: AnsiString): Integer;
var m: AnsiString; i: Integer;
begin
  Result := FindUnitOrAlias(cand);
  if (Result >= 0) or (not isNilPy) then Exit;
  m := '';
  for i := 1 to Length(cand) do
    if cand[i] = '.' then m := m + '_' else m := m + cand[i];
  Result := FindUnitOrAlias(m);
end;

{ Strip a leading `System.` qualifier. pxx has no separate System unit — System
  IS the builtin layer — so FPC's `System.Move(p, q, n)`, `System.Integer(x)` and
  `SizeOf(System.TMethod)` must resolve exactly like the bare name. CurTok sits on
  the candidate `System`; on True the name and its dot are consumed, CurTok is the
  member, and `name` holds the member's spelling. False consumes nothing —
  including when something REAL is named System (a loaded unit, or a local /
  record var), which keeps its own meaning.

  The member may lex as an IDENTIFIER (`System.Move`) or as a builtin TYPE
  KEYWORD (`System.Integer`, `System.LongWord`) — the two are the same
  declaration read two ways, and every hand-rolled dispatch that forgot the
  second half broke on it. ONE function, two callers (the unit-qualifier
  resolver and SizeOf's own type dispatch), because each had to learn the strip
  separately and only the first one ever did: `System.Integer(ALeft)` and
  `SizeOf(System.TMethod)` — adjacent lines in rtl-generics' TCompare — failed
  for the one missing rule. }
function EatSystemQualifier(var name: AnsiString): Boolean;
var mk: TTokenKind;
begin
  Result := False;
  if (CurTok.Kind <> tkIdent) or (not CaseEqual(name, 'System')) then Exit;
  if not ((TokPos + 1 < TokCount) and (Tokens[TokPos].Kind = tkDot)) then Exit;
  mk := Tokens[TokPos + 1].Kind;
  if not ((mk = tkIdent) or (mk = tkInteger_T) or (mk = tkLongWord_T) or
          (mk = tkBoolean_T) or (mk = tkChar_T) or (mk = tkString_T) or
          (mk = tkReal_T) or (mk = tkSingle_T) or (mk = tkDouble_T) or
          (mk = tkExtended_T)) then Exit;
  if (FindUnitOrAlias(name) >= 0) or (FindSym(name) >= 0) then Exit;
  Next;                 { consume 'System' (CurTok -> '.') }
  Expect(tkDot, '.');   { consume '.'      (CurTok -> the member) }
  name := CurTok.SVal;
  { a keyword token carries no SVal in every lexer path — fall back to its text }
  if name = '' then name := GetTokenStr(TokPos - 1);
  Result := True;
end;

function ConsumeUnitQualifier(var name: AnsiString): Integer;
var cand: AnsiString; bestUnit, bestExtra, extra, ti, k, u: Integer;
begin
  Result := -1;
  if CurTok.Kind <> tkIdent then Exit;
  { `System.X` — stripped, and reported as -2: like unqualified (-1) everywhere,
    but the builtin soft-aliases must WIN over a same-named method of the
    enclosing class — TFPSList.Delete's System.Move(...) names the builtin
    precisely because the class has its own Move(CurIndex, NewIndex). Checked
    BEFORE the `.ident` guard below, because a System member may be a builtin
    TYPE, which lexes as a keyword token rather than an identifier. }
  if EatSystemQualifier(name) then
  begin
    Result := -2;
    Exit;
  end;

  { Need at least one `.ident` after the name to be a qualifier at all — or, in
    NilPy, a `.KEYWORD`: `tk.END` is written by every tkinter application and
    END is a reserved word here, so the façade spells the constant END_ and the
    member name is mapped to it below. The same trailing-underscore convention
    the reserved METHOD names use (set_, destroy_). }
  if not ((TokPos + 1 < TokCount) and (Tokens[TokPos].Kind = tkDot) and
          ((Tokens[TokPos + 1].Kind = tkIdent) or
           (isNilPy and (Tokens[TokPos + 1].Kind = tkEnd)))) then Exit;

  { A local/param/global SYMBOL shadows a same-named unit (FPC scoping):
    `function NetToHost(Net: in_addr)...` must keep `Net.s_addr` a record
    field access even when unit net.pas is loaded — the qualifier greedily
    ate the param and s_addr resolved against the unit (undefined). }
  if FindSym(name) >= 0 then Exit;

  cand := name;
  bestUnit := -1; bestExtra := -1;
  { 0-extra: the bare name is the unit, member = Tokens[TokPos+1]. }
  u := PyFindUnitDotted(cand);
  if u >= 0 then begin bestUnit := u; bestExtra := 0; end;

  { Extend with `.ident` groups; each is a unit-qualifier candidate only while a
    further `.ident` (the member) still remains. }
  ti := TokPos;                       { points at the first '.' }
  extra := 1;
  while (ti + 1 < TokCount) and (Tokens[ti].Kind = tkDot) and
        (Tokens[ti + 1].Kind = tkIdent) do
  begin
    AppendChar(cand, '.');
    AppendString(cand, GetTokenStr(ti + 1));
    if (ti + 3 < TokCount) and (Tokens[ti + 2].Kind = tkDot) and
       (Tokens[ti + 3].Kind = tkIdent) then
    begin
      u := PyFindUnitDotted(cand);
      if u >= 0 then begin bestUnit := u; bestExtra := extra; end;
    end;
    Inc(extra);
    ti := ti + 2;
  end;

  if bestUnit < 0 then Exit;
  Result := bestUnit;
  { Consume (bestExtra+1) identifiers, each with its trailing '.', leaving the
    parser on the member name (mirrors the old single-dot behavior). }
  for k := 0 to bestExtra do
  begin
    Next;                 { consume identifier (CurTok -> '.') }
    Expect(tkDot, '.');   { consume '.'        (CurTok -> next ident) }
  end;
  if CurTok.Kind = tkIdent then
  begin
    name := CurTok.SVal;
    { The trailing-underscore convention is not only for RESERVED words: a
      façade renames any constant whose bare spelling collides with something
      already in the flat namespace, and which names collide depends on what
      else the program links (`tk.X` resolved on its own and stopped resolving
      once the app pulled in a C unit). So when the plain member is not
      declared in the named unit but `NAME_` is, take that — the same rule
      `tk.END` -> END_ already follows, applied where the collision is
      accidental rather than syntactic. Retired by
      [[bug-pascal-uses-is-transitive]], with the rest of the flat namespace. }
    if isNilPy and (FindStrConst(name) < 0) and
       (FindStrConst(name + '_') >= 0) then
      name := name + '_';
  end
  else
    name := GetTokenStr(TokPos - 1) + '_';   { `tk.END` -> END_ }
end;

function LastDotName(const s: AnsiString): AnsiString;
{ Part of s after the last '.', else s. }
var i, p: Integer;
begin
  p := 0;
  for i := 1 to Length(s) do
    if s[i] = '.' then p := i;
  Result := '';
  for i := p + 1 to Length(s) do
    AppendChar(Result, s[i]);
end;

{ Read a (possibly dotted) unit name in a `uses` clause: ident('.'ident)* joined
  with dots (`Posix.SysSocket`, `System.Generics.Collections`). A path/string
  token (`uses 'foo/bar'`) is returned as-is. Consumes the whole name, leaving the
  parser on the following token (',' / ';' / next clause). Non-dotted names are
  returned unchanged, so existing lookup is untouched. }
function ReadDottedUsesName: AnsiString;
begin
  Result := CurTok.SVal;
  if CurTok.Kind <> tkIdent then begin Next; Exit; end;
  Next;                                  { consume the first identifier }
  while (CurTok.Kind = tkDot) and (TokPos < TokCount) and
        (Tokens[TokPos].Kind = tkIdent) do
  begin
    Next;                                { consume '.'  (CurTok -> identifier) }
    AppendChar(Result, '.');
    AppendString(Result, CurTok.SVal);
    Next;                                { consume identifier }
  end;
end;

procedure SkipSelectors;
begin
  while CurTok.Kind in [tkDot, tkLBrack] do
  begin
    if CurTok.Kind = tkDot then
    begin
      Next;
      if CurTok.Kind in [tkEOF, tkSemicolon, tkAssign, tkRBrack, tkRParen] then Error('expected field name');
      Next;
    end
    else
    begin
      Next;
      ParseExpr;
      Expect(tkRBrack, ']');
    end;
  end;
end;

function EnumTypeNameOf(eid: Integer): AnsiString;
begin
  if (eid >= 0) and (eid < EnumTypeCount) then
    Result := GetTokenStrFromRaw(EnumTypeNOff[eid], EnumTypeNLen[eid])
  else
    Result := '<anonymous enum>';
end;

procedure SetLitBegin;
{ Open a fresh element tally for one `[...]`. Callers save/restore the three
  globals around it, so a set literal nested inside an element expression
  cannot corrupt the enclosing one's tally. }
begin
  SetLitEnumId := -1;
  SetLitMixed := False;
  SetLitHasPlain := False;
end;

procedure SetLitNoteEnum(eid: Integer);
{ Tally one element known to be a member of enum `eid`. }
begin
  if SetLitEnumId < 0 then SetLitEnumId := eid
  else if SetLitEnumId <> eid then SetLitMixed := True;
end;

procedure SetLitNoteElem(symIdx: Integer);
{ Tally one CONSTANT element by the symbol it came from (-1 = a literal integer
  or char, which is never an enum member). Runtime elements are not tallied:
  their ordinal type is not knowable here, and being lenient there costs a
  diagnostic rather than producing a wrong value. }
var eid: Integer;
begin
  eid := -1;
  if symIdx >= 0 then eid := SymEnumId[symIdx];
  if eid < 0 then SetLitHasPlain := True else SetLitNoteEnum(eid);
end;

procedure SetLitCheckAgainst(targetEnumId: Integer);
{ The one rule, at the one place the target type is known: in a literal bound to
  a `set of TEnum`, every constant element must be a member of THAT enum.

  It subsumes the whole reported surface -- a plain integer, a char, True and an
  out-of-range ordinal are all "not a member of TEnum", and so is a member of a
  DIFFERENT enum with the same ordinal, which was the sharpest case: `[cGreen]`
  silently answered dTue, so swapping one enum for another could not be caught
  anywhere a set literal was involved.

  `[]` is always legal (nothing to check), and a set whose element type is not
  an enum (`set of Char`, `set of Byte`, `set of 0..7`) is left alone entirely.
  bug-p-set-literal-elements-are-not-type-checked }
begin
  if SetLitMixed then
    Error('set literal mixes elements from two different enum types');
  if targetEnumId < 0 then Exit;
  if SetLitHasPlain then
    Error('set element is not a member of ' + EnumTypeNameOf(targetEnumId));
  if (SetLitEnumId >= 0) and (SetLitEnumId <> targetEnumId) then
    Error('set of ' + EnumTypeNameOf(SetLitEnumId) +
          ' element in a set of ' + EnumTypeNameOf(targetEnumId));
end;

procedure SetLitCheckArg(node, procIdx, slot: Integer);
{ The call-argument arm. `node` must be the literal just parsed — the tally the
  check reads is the one left in the globals by its `]`, so anything else would
  be reading a previous literal's.

  Skipped for an OVERLOADED routine: `procIdx` here is the candidate the name
  resolved to first, not necessarily the one the call will bind, so its element
  type is not yet knowable. (A literal that mixes two enums is still rejected —
  that needs no target at all.) }
begin
  if (node < 0) or (ASTKind[node] <> AN_SET_LIT) then Exit;
  if (procIdx < 0) or (slot < 0) or (slot >= MAX_PROC_PARAMS) then Exit;
  if slot >= Procs[procIdx].ParamCount then Exit;
  if ProcOverloadDirective[procIdx] then
  begin
    if SetLitMixed then
      Error('set literal mixes elements from two different enum types');
    Exit;
  end;
  SetLitCheckAgainst(ProcParamSetEnumId[procIdx * MAX_PROC_PARAMS + slot]);
end;

function ParseSetConst: Int64;
var idx: Integer;
begin
  if CurTok.Kind = tkInteger then
  begin
    Result := CurTok.IVal;
    SetLitNoteElem(-1);
    Next;
  end
  else if CurTok.Kind = tkString then
  begin
    if Length(CurTok.SVal) <> 1 then Error('set item must be one character');
    Result := Ord(CurTok.SVal[1]);
    SetLitNoteElem(-1);
    Next;
  end
  else if CurTok.Kind = tkIdent then
  begin
    idx := FindSym(CurTok.SVal);
    if (idx < 0) or (Syms[idx].Kind <> skConst) then Error('set item must be constant');
    Result := Syms[idx].ConstVal;
    SetLitNoteElem(idx);
    Next;
  end
  else Error('expected set item');
end;

procedure ParseSetMembership;
const MAX_SET_JUMPS = 128;
var
  lo, hi: Int64;
  trueJumps: array[0..MAX_SET_JUMPS-1] of Integer;
  trueCount, falseJmp, nextJmp, i: Integer;
  done: Boolean;
begin
  { Left expression is in rax. Keep it in rcx and produce boolean in rax. }
  EmitB($48); EmitB($89); EmitB($C1);       { mov rcx, rax }
  Expect(tkLBrack, '[');
  trueCount := 0;
  if CurTok.Kind <> tkRBrack then
  begin
    done := False;
    while not done do
    begin
      lo := ParseSetConst;
      hi := lo;
      if Eat(tkDotDot) then hi := ParseSetConst;

      if lo = hi then
      begin
        EmitB($48); EmitB($81); EmitB($F9); EmitI32(lo); { cmp rcx, imm32 }
        EmitB($0F); EmitB($84);
        if trueCount >= MAX_SET_JUMPS then Error('set expression too large');
        trueJumps[trueCount] := CodeLen; Inc(trueCount);
        EmitI32(0);
      end
      else
      begin
        EmitB($48); EmitB($81); EmitB($F9); EmitI32(lo); { cmp rcx, lo }
        EmitB($0F); EmitB($8C); nextJmp := CodeLen; EmitI32(0); { jl next }
        EmitB($48); EmitB($81); EmitB($F9); EmitI32(hi); { cmp rcx, hi }
        EmitB($0F); EmitB($8E);
        if trueCount >= MAX_SET_JUMPS then Error('set expression too large');
        trueJumps[trueCount] := CodeLen; Inc(trueCount);
        EmitI32(0);
        Patch32(nextJmp, CodeLen - (nextJmp + 4));
      end;

      if not Eat(tkComma) then done := True;
    end;
  end;
  Expect(tkRBrack, ']');
  MovRaxImm(0);
  EmitB($E9); falseJmp := CodeLen; EmitI32(0);
  for i := 0 to trueCount-1 do
    Patch32(trueJumps[i], CodeLen - (trueJumps[i] + 4));
  MovRaxImm(1);
  Patch32(falseJmp, CodeLen - (falseJmp + 4));
end;

procedure CompileLValueAddressInternal(idx: Integer; var tk: TTypeKind; var recName: Integer); forward;
procedure CompileLValueAddress(const name: AnsiString; var tk: TTypeKind; var recName: Integer); forward;
procedure ParseLValue(const name: AnsiString); forward;
procedure EmitArgvToAddr; forward;

function ParseLValueAST(idx: Integer; identTokIdx: Integer): Integer; forward;
function GenMakeFreeObjectExpr(objNode, ci: Integer): Integer; forward;
function ParseSetMembershipAST(leftExpr: Integer): Integer; forward;
function ParseSetLiteralAST: Integer; forward;
function NodeEnumIdOf(node: Integer): Integer; forward;
function ParseVarRecLiteralAST: Integer; forward;
function ParseArrayCtorAST(elemTk: TTypeKind; rowLen, rowLo: Integer): Integer; forward;
function BuildMetaclassNew(crefNode, ci, mmi: Integer): Integer; forward;
function ParseStatementAST: Integer; forward;
procedure EnableCoroutineRuntime; forward;
function ParseWithStatementAST: Integer; forward;
function ParseAsmStatementAST: Integer; forward;
function ParseBlockAST: Integer; forward;
procedure CompileAST(node: Integer); forward;
function ParseTypeKind: TTypeKind; forward;
procedure ParseRecordFields(ci: Integer; isPackedRecord: Boolean); forward;
procedure ParseRecordMethodDecl(ci: Integer); forward;
var RecordMethodClassPrefix: Boolean = False;  { `class function` in a record/helper body }
procedure ParseRecordPropertyDecl(ci: Integer); forward;
function IsNodePChar(node: Integer): Boolean; forward;  { defined in ir.inc (included later) }
procedure ParseSubroutine; forward;
function NegWidensToInt64(tk: TTypeKind): Boolean; forward;  { FPC: unary minus yields Int64 for EVERY integer operand }
function ASTConstIntValue(node: Integer; var v: Int64; depth: Integer): Boolean; forward;  { ...except a CONSTANT, which FPC types by its folded VALUE }
procedure ParseGenericFunctionDef; forward;
procedure ParseOperatorDef; forward;
procedure ParseNestedRoutine; forward;
procedure FlushPendingNestedProcs; forward;
function ParseParallelFor: Integer; forward;

{ GetTokenStrFromRaw moved up to lexer.inc (before its lexer.inc use) for FPC
  declaration-order; see there. }
