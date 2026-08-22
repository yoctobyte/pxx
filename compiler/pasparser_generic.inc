{ ===== pasparser_generic.inc — Pascal frontend: generics =====================

  Carved out of pasparser_*.inc, byte-for-byte, by
  refactor-a-carve-out-plexer-pparser-so-p-owns-its-own-files.

  Owned by Track P (Pascal frontend). Included from compiler.pas at exactly the
  point it used to occupy, so include ORDER is unchanged — that is what makes
  the carve-out provable by the self-host fixedpoint rather than by reading it.

  Contents: `generic` templates and `specialize` in both the FPC and the Delphi
  spellings, the token-stream re-parse that instantiates a template, nested
  specializations (a template naming another template with the enclosing
  template's own type parameters), generic FUNCTIONS, and the buffered
  generic-method bodies flushed when a class specialization closes.

  DO NOT factor anything here into a shared helper with pyparser.inc/cparser.inc.
  What is shared between frontends is the AST and the IR, never the parser:
  devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md }

{ ---- nested generic specializations ---------------------------------------

  A template body may name ANOTHER template using the ENCLOSING template's own
  type parameters — as a base class (`generic TDer<T> = class(specialize
  TBase<T>)`), as a field type, anywhere a type may appear. The
  concrete-argument form written inside a template (`specialize TBase<Integer>`)
  already resolves: DelphiRewriteGenericUses sweeps the token stream before the
  enclosing template captures it, mints `TBase$Integer` and inserts the alias
  declaration. The PARAMETER form cannot resolve there — `TBase$T` is not a
  type, and what T is only becomes known when the enclosing template is
  specialized.

  So it resolves at that moment instead. Before streaming TDer<Integer>'s body,
  ParseSpecialization walks the template tokens for `specialize NAME<args>`
  groups, maps each argument through the substitution it is about to apply, and
  mints the same alias name the concrete path would have. If that specialization
  does not exist yet, TDer<Integer> cannot be bound — a parent must exist before
  its child — so the declaration is DEFERRED: emit `TBase$Integer = specialize
  TBase<Integer>;` and then a fresh copy of the declaration we were in the
  middle of, and hand control back to the type-section loop. It parses the
  prerequisite (which defers again if IT nests, so a chain unwinds), then
  re-parses ours, which now finds the alias registered and proceeds. Termination
  is by construction: the retry mints the identical name and finds it.

  Once the prerequisites exist, SpecializeStream collapses each group to the
  single alias identifier, so the body it inserts speaks the ordinary
  non-generic surface the rest of the parser already understands.

  ONE mechanism, both surfaces: the mode-Delphi spelling `TBase<T>` is rewritten
  to `specialize TBase<T>` by DelphiRewriteGenericUses rather than given a
  resolver of its own. }

function FindSpecialization(const nm: AnsiString): Integer;
{ VISIBILITY-AWARE, and it has to be. The table is one flat global list, but a
  specialization is not a global fact: SpecializeStream declares an ordinary
  class or record under `nm` in whatever unit is being parsed, and that
  declaration obeys the same one-hop uses rule as every other type. So a row
  written by a unit this scope cannot see is not an answer — reporting it made
  the caller skip the declaration as "already declared" and the very next line,
  `var lt: T;`, then failed with `unknown type` (tgeneric96: two units each
  writing `T = specialize TTest<LongInt>;`, neither using the other).
  Last visible row wins, matching FindUClass's rule that the later unit hides
  the earlier one. }
var i: Integer;
begin
  Result := -1;
  for i := 0 to SpecializationCount - 1 do
    if CaseEqual(Specializations[i].Name, nm) and DeclVisible(SpecUnitIdx[i]) then
      Result := i;
end;

{ Does TemplateTokens[ts + i] open a `specialize NAME<...>` group naming a
  template we know? Returns the offset of the closing `>`, or -1. A binder
  (`X = specialize ...`, a nested type declaration) is ParseSpecialization's
  own business and is skipped. }
function NestedSpecGroup(ts, i, count: Integer): Integer;
var j, k, ti: Integer; nm: AnsiString; scanning: Boolean;
begin
  Result := -1;
  if i + 3 >= count then Exit;
  if TemplateTokens[ts + i].Kind <> tkIdent then Exit;
  if not CaseEqual(GetTokenStrFromRaw(TemplateTokens[ts + i].SOffset,
                                     TemplateTokens[ts + i].SLen), 'specialize') then Exit;
  if (i > 0) and (TemplateTokens[ts + i - 1].Kind = tkEq) then Exit;
  if TemplateTokens[ts + i + 1].Kind <> tkIdent then Exit;
  if TemplateTokens[ts + i + 2].Kind <> tkLt then Exit;
  nm := GetTokenStrFromRaw(TemplateTokens[ts + i + 1].SOffset, TemplateTokens[ts + i + 1].SLen);
  ti := -1;
  for k := 0 to TemplateCount - 1 do
    if CaseEqual(Templates[k].Name, nm) then ti := k;
  if ti < 0 then Exit;
  j := i + 3;
  scanning := True;
  while scanning do
  begin
    if j >= count then Exit;
    if not (TemplateTokens[ts + j].Kind in [tkIdent, tkInteger_T, tkBoolean_T, tkChar_T, tkString_T]) then Exit;
    Inc(j);
    if (j < count) and (TemplateTokens[ts + j].Kind = tkComma) then Inc(j)
    else scanning := False;
  end;
  if (j >= count) or (TemplateTokens[ts + j].Kind <> tkGt) then Exit;
  Result := j;
end;

{ One argument token of such a group, mapped through the substitution set in
  force (SpecSub*): a reference to the enclosing template's parameter becomes
  the concrete type it is being specialized with. }
procedure NestedSpecArg(ts, at: Integer; var t: TRawToken);
var k: Integer; nm: AnsiString;
begin
  t.Kind := TemplateTokens[ts + at].Kind;
  t.IVal := TemplateTokens[ts + at].IVal;
  t.Line := TemplateTokens[ts + at].Line;
  t.SOffset := TemplateTokens[ts + at].SOffset;
  t.SLen := TemplateTokens[ts + at].SLen;
  if t.Kind <> tkIdent then Exit;
  nm := GetTokenStrFromRaw(t.SOffset, t.SLen);
  for k := 0 to SpecSubCount - 1 do
    if CaseEqual(nm, SpecSubNames[k]) then
    begin
      t.Kind := SpecSubKinds[k];
      t.SOffset := TokCharsAppend(SpecSubValues[k]);
      t.SLen := Length(SpecSubValues[k]);
      Break;
    end;
end;

{ The alias name the group resolves to — the SAME minting DelphiRewriteGenericUses
  uses for a concrete use, so the two paths never disagree about a name. }
function NestedSpecAlias(ts, i, gEnd: Integer): AnsiString;
var j: Integer; t: TRawToken;
begin
  Result := GetTokenStrFromRaw(TemplateTokens[ts + i + 1].SOffset, TemplateTokens[ts + i + 1].SLen);
  j := i + 3;
  while j < gEnd do
  begin
    if TemplateTokens[ts + j].Kind <> tkComma then
    begin
      NestedSpecArg(ts, j, t);
      Result := Result + '$' + GetTokenStrFromRaw(t.SOffset, t.SLen);
    end;
    Inc(j);
  end;
end;

{ Is the alias already available as a type? }
function NestedSpecKnown(const nm: AnsiString): Boolean;
begin
  Result := (FindSpecialization(nm) >= 0) or (FindUClass(nm) >= 0);
end;

procedure SpecializeStream(tokStart, count: Integer; const specName: AnsiString);
{ Substitutions come from the SpecSub* globals (param name -> concrete
  name/kind), set by the caller — multi-param generics replace every type
  parameter in one pass. }
var
  i, j, k: Integer;
  subCount: Integer;
  gEnd: Integer;
  s, aliasNm: AnsiString;
begin
  subCount := 0;
  i := 0;
  while i < count do
  begin
    { A nested generic use collapses to the single alias identifier naming its
      specialization — `specialize TBase<T>` with T:=Integer becomes
      `TBase$Integer`. ParseSpecialization has already guaranteed the alias
      exists (it defers the whole declaration otherwise), so an unresolved group
      here means a name that is not a type at all: leave it alone and let the
      ordinary error reporting name it. }
    gEnd := NestedSpecGroup(tokStart, i, count);
    if gEnd >= 0 then
    begin
      aliasNm := NestedSpecAlias(tokStart, i, gEnd);
      if CaseEqual(aliasNm, specName) or NestedSpecKnown(aliasNm) then
      begin
        SpecializeTokens[subCount].Kind := tkIdent;
        SpecializeTokens[subCount].IVal := 0;
        SpecializeTokens[subCount].Line := TemplateTokens[tokStart + i].Line;
        SpecializeTokens[subCount].SOffset := TokCharsAppend(aliasNm);
        SpecializeTokens[subCount].SLen := Length(aliasNm);
        Inc(subCount);
        i := gEnd + 1;
        Continue;
      end;
    end;
    SpecializeTokens[subCount].Kind := TemplateTokens[tokStart + i].Kind;
    SpecializeTokens[subCount].IVal := TemplateTokens[tokStart + i].IVal;
    SpecializeTokens[subCount].Line := TemplateTokens[tokStart + i].Line;
    SpecializeTokens[subCount].SOffset := TemplateTokens[tokStart + i].SOffset;
    SpecializeTokens[subCount].SLen := TemplateTokens[tokStart + i].SLen;

    if SpecializeTokens[subCount].Kind = tkIdent then
    begin
      s := GetTokenStrFromRaw(SpecializeTokens[subCount].SOffset, SpecializeTokens[subCount].SLen);
      { …except in a BASE-CLASS position (`= class(` immediately before it),
        where the template's own name cannot mean this specialization -- a class
        may not inherit from itself -- and so must mean the ordinary class
        sharing the name (rtl-generics' `THashService<T> = class(THashService)`).
        Rewriting it there produced `base type not found: THS$LongInt`, i.e. the
        specialization looking for itself as its own parent.

        Keyed on the two preceding tokens being `class` `(`, so an ordinary
        typecast `TFoo(x)` inside the body -- where the name DOES mean the
        specialization -- is untouched. }
      if CaseEqual(s, SpecializeTemplateName) and (i >= 2) and
         (TemplateTokens[tokStart + i - 1].Kind = tkLParen) and
         (TemplateTokens[tokStart + i - 2].Kind = tkClass) then
      begin
        { leave the token exactly as it is: names the non-generic sibling }
      end
      else if CaseEqual(s, SpecializeTemplateName) then
      begin
        SpecializeTokens[subCount].SOffset := TokCharLen;
        SpecializeTokens[subCount].SLen := Length(specName);
        if TokCharLen + Length(specName) > STRING_CAP then Error('token char pool overflow');
        j := 1;
        while j <= Length(specName) do
        begin
          TokChars[TokCharLen] := specName[j];
          Inc(TokCharLen);
          Inc(j);
        end;
      end
      else
        for k := 0 to SpecSubCount - 1 do
          if CaseEqual(s, SpecSubNames[k]) then
          begin
            SpecializeTokens[subCount].Kind := SpecSubKinds[k];
            SpecializeTokens[subCount].SOffset := TokCharLen;
            SpecializeTokens[subCount].SLen := Length(SpecSubValues[k]);
            if TokCharLen + Length(SpecSubValues[k]) > STRING_CAP then Error('token char pool overflow');
            j := 1;
            while j <= Length(SpecSubValues[k]) do
            begin
              TokChars[TokCharLen] := SpecSubValues[k][j];
              Inc(TokCharLen);
              Inc(j);
            end;
            Break;
          end;
    end;

    Inc(subCount);
    Inc(i);
  end;

  EnsureTokCapacity(TokCount + subCount + 1);
  i := TokCount - 1;
  while i >= TokPos do
  begin
    Tokens[i + subCount].Kind := Tokens[i].Kind;
    Tokens[i + subCount].IVal := Tokens[i].IVal;
    Tokens[i + subCount].Line := Tokens[i].Line;
    Tokens[i + subCount].SOffset := Tokens[i].SOffset;
    Tokens[i + subCount].SLen := Tokens[i].SLen;
    Dec(i);
  end;
  i := 0;
  while i < subCount do
  begin
    Tokens[TokPos + i].Kind := SpecializeTokens[i].Kind;
    Tokens[TokPos + i].IVal := SpecializeTokens[i].IVal;
    Tokens[TokPos + i].Line := SpecializeTokens[i].Line;
    Tokens[TokPos + i].SOffset := SpecializeTokens[i].SOffset;
    Tokens[TokPos + i].SLen := SpecializeTokens[i].SLen;
    Inc(i);
  end;
  Inc(TokCount, subCount);
end;

procedure ParseGenericTemplateNamed(const templateNameIn: AnsiString; delphiForm: Boolean); forward;
function OrdinalNameToTk(const nm: AnsiString): TTypeKind; forward;
function BuiltinTypeNameTk(const nm: AnsiString): TTypeKind; forward;   { body in pasparser_lval.inc, which also CALLS it above the body (the type-helper type-name receiver). pxx pre-scans and does not need this; FPC does. }

{ mode-Delphi generics desugar. After template ti (`TFoo<T> = class...`) is
  captured, rewrite every later use of the Delphi surface into the objfpc
  surface the existing template/specialization machinery parses:
  - `TFoo<Concrete,...>`  -> a minted alias ident `TFoo$Concrete$...`, with
    ONE alias declaration `TFoo$... = specialize TFoo<Concrete,...>;` inserted
    at insertAt (right after the template declaration, still inside the type
    section) per distinct argument tuple;
  - `TFoo<T>` spelled with the template's OWN param names (method impls:
    `procedure TFoo<T>.M;`) -> the `<...>` group is removed, leaving
    `procedure TFoo.M;` which BufferGenericMethod already handles.
  Guards: the name must match ti's, the `<...>` group must be a plain
  comma-separated list of type idents closed by `>`, and the arity must match
  — anything else (e.g. a real `a < b` comparison) is left untouched. }
procedure DelphiRewriteGenericUses(ti: Integer; var insertAt: Integer; delphiPattern: Boolean);
{ insertAt is VAR so a caller can run this to a FIXED POINT: each round leaves it
  past the alias declarations that round emitted, so the next round's aliases land
  AFTER them -- which is the whole ordering requirement, since an outer alias
  refers to an inner one. See the nested-specialization note at the call site.
  bug-a-a-nested-inline-specialize-is-refused-outside-a-type-section }
const MAX_DGEN_TUPLES = 512;
var
  i, j, k, kk, na, np, seenCnt, insCnt, aOff, sOff, tOff: Integer;
  tname, aname, key: AnsiString;
  argTok: array[0..MAX_TEMPLATE_PARAMS-1] of TRawToken;
  seenKey: array[0..MAX_DGEN_TUPLES-1] of AnsiString;
  seenOff: array[0..MAX_DGEN_TUPLES-1] of Integer;
  seenLen: array[0..MAX_DGEN_TUPLES-1] of Integer;
  seenArg: array[0..MAX_DGEN_TUPLES*MAX_TEMPLATE_PARAMS-1] of TRawToken;
  ins: array[0..MAX_TEMPLATE_PARAMS*2+8] of TRawToken;
  ok, isParamForm, specB: Boolean;
  si: Integer;
begin
  tname := Templates[ti].Name;
  np := TemplateNParams[ti];
  seenCnt := 0;
  i := insertAt;
  while i < TokCount - 1 do
  begin
    { Pattern A (mode-Delphi only): bare `TFoo<Args>`. Pattern B (both modes):
      INLINE `specialize TFoo<Args>` in a non-binder position (^specialize
      pointer decls, `var x: specialize TFoo<T>`, typed consts — tgeneric33/
      87/88). The binder form `X = specialize TFoo<...>;` stays with the
      native ParseSpecialization path (previous token = '='). }
    specB := (i + 2 < TokCount) and (Tokens[i].Kind = tkIdent) and
             CaseEqual(GetTokenStr(i), 'specialize') and
             (Tokens[i+1].Kind = tkIdent) and CaseEqual(GetTokenStr(i+1), tname) and
             (Tokens[i+2].Kind = tkLt) and
             ((i = 0) or (Tokens[i-1].Kind <> tkEq));
    if specB or
       (delphiPattern and (Tokens[i].Kind = tkIdent) and (Tokens[i+1].Kind = tkLt) and
        CaseEqual(GetTokenStr(i), tname) and
        { ...but NOT when the previous round already put `specialize` in front of
          this very group. The paramform arm below REWRITES `TFoo<T>` into
          `specialize TFoo<T>` in place; on the next round specB matches the new
          keyword and correctly does nothing, but the loop's Inc(i) then lands on
          the `TFoo` `<` immediately after it and pattern A matched all over
          again, inserting a second `specialize`, then a third. Two tokens per
          round, forever, until the runaway guard fired with "nested deeper than
          16 levels" on a file nested one level deep.

          Harmless while each template was swept EXACTLY ONCE, which is what it
          was until this procedure was run to a fixed point for nested inline
          specializations. A rewrite that a fixed-point loop calls repeatedly has
          to be IDEMPOTENT, and this one silently was not.
          bug-a-the-delphi-generic-rewrite-is-not-idempotent }
        ((i = 0) or (Tokens[i-1].Kind <> tkIdent) or
         (not CaseEqual(GetTokenStr(i-1), 'specialize')))) then
    begin
      { collect the <...> argument list }
      ok := True; na := 0;
      if specB then j := i + 3 else j := i + 2;
      while ok do
      begin
        if (j < TokCount) and (na < MAX_TEMPLATE_PARAMS) and
           (Tokens[j].Kind in [tkIdent, tkInteger_T, tkBoolean_T, tkChar_T, tkString_T]) then
        begin
          argTok[na] := Tokens[j]; Inc(na); Inc(j);
          if (j < TokCount) and (Tokens[j].Kind = tkComma) then Inc(j)
          else Break;
        end
        else ok := False;
      end;
      if ok and ((j >= TokCount) or (Tokens[j].Kind <> tkGt)) then ok := False;
      if ok and (na <> np) then ok := False;
      if ok then
      begin
        { A `<...>` group can be resolved EAGERLY into an alias only when every
          argument is a concrete type. An argument spelled with one of this
          template's own parameter names is not concrete: inside another
          template's body it stands for whatever that outer template is
          specialized with, and the two spellings MIX in one group --
          rtl-generics writes
            `TGStringComparer<T> = class(TGStringComparer<T, TDelphiQuadrupleHashFactory>)`.
          So one parameter name anywhere in the group sends the whole group down
          the deferred path (method impls) or the nested-specialization path
          (type references). Matching is by name against ANY parameter, not
          position: `TBar<V, K>` forwards the same names in the other order. }
        isParamForm := False;
        for k := 0 to na - 1 do
          for kk := 0 to np - 1 do
            if (argTok[k].Kind = tkIdent) and
               CaseEqual(GetTokenStrFromRaw(argTok[k].SOffset, argTok[k].SLen),
                         TemplateParamNames[ti * MAX_TEMPLATE_PARAMS + kk]) then
              isParamForm := True;
        if DebugTrace then writeln('DGEN match at ', i, ' na=', na, ' paramform=', isParamForm);
        if isParamForm then
        begin
          if not specB then
          begin
            { `TFoo<T>` spelled with TFoo's OWN parameter names. Only a METHOD
              IMPLEMENTATION header — `procedure TFoo<T>.M` — means "this
              template's own methods", and only there is dropping the `<T>`
              right. Everywhere else it is a TYPE reference carrying the
              ENCLOSING template's parameters (`class(TOrdinalComparer<T,
              THashFactory>)`, a field, a local), which resolves only once that
              enclosing template is specialized: give it the objfpc spelling and
              let ParseSpecialization's nested-prerequisite pass do it. Stripping
              `<T>` there left a bare template name behind and produced
              `base type not found` on rtl-generics. }
            if (j + 1 < TokCount) and (Tokens[j + 1].Kind = tkDot) then
              RemoveTokens(i + 1, j - i)   { method impl reference }
            else
            begin
              ins[0].Kind := tkIdent; ins[0].IVal := 0; ins[0].Line := Tokens[i].Line;
              ins[0].SOffset := TokCharsAppend('specialize'); ins[0].SLen := 10;
              InsertTokens(i, ins, 1);
              i := j + 1;   { the loop's Inc(i) lands past the inserted group }
            end;
          end;
          { specB paramform (inside a later generic body): already objfpc }
        end
        else
        begin
          key := '';
          for k := 0 to na - 1 do
          begin
            key := key + '$';
            key := key + GetTokenStrFromRaw(argTok[k].SOffset, argTok[k].SLen);
          end;
          si := -1;
          for k := 0 to seenCnt - 1 do
            if seenKey[k] = key then si := k;
          if si < 0 then
          begin
            if seenCnt >= MAX_DGEN_TUPLES then Error('too many distinct generic specializations (MAX_DGEN_TUPLES)');
            si := seenCnt;
            aname := tname + key;
            seenKey[si] := key;
            seenOff[si] := TokCharsAppend(aname);
            seenLen[si] := Length(aname);
            for k := 0 to na - 1 do
              seenArg[si * MAX_TEMPLATE_PARAMS + k] := argTok[k];
            Inc(seenCnt);
          end;
          Tokens[i].SOffset := seenOff[si];
          Tokens[i].SLen := seenLen[si];
          { for specB, Tokens[i] was the 'specialize' keyword ident — it
            becomes the alias ident and the whole `TFoo<...>` tail goes }
          RemoveTokens(i + 1, j - i);
        end;
      end;
    end;
    Inc(i);
  end;

  { one alias declaration per distinct tuple, inserted in first-seen order }
  for si := 0 to seenCnt - 1 do
  begin
    sOff := TokCharsAppend('specialize');
    tOff := TokCharsAppend(tname);
    insCnt := 0;
    ins[insCnt].Kind := tkIdent; ins[insCnt].IVal := 0; ins[insCnt].Line := Tokens[insertAt].Line;
    ins[insCnt].SOffset := seenOff[si]; ins[insCnt].SLen := seenLen[si]; Inc(insCnt);
    ins[insCnt].Kind := tkEq; ins[insCnt].IVal := 0; ins[insCnt].Line := ins[0].Line;
    ins[insCnt].SOffset := 0; ins[insCnt].SLen := 0; Inc(insCnt);
    ins[insCnt].Kind := tkIdent; ins[insCnt].IVal := 0; ins[insCnt].Line := ins[0].Line;
    ins[insCnt].SOffset := sOff; ins[insCnt].SLen := 10; Inc(insCnt);
    ins[insCnt].Kind := tkIdent; ins[insCnt].IVal := 0; ins[insCnt].Line := ins[0].Line;
    ins[insCnt].SOffset := tOff; ins[insCnt].SLen := Length(tname); Inc(insCnt);
    ins[insCnt].Kind := tkLt; ins[insCnt].IVal := 0; ins[insCnt].Line := ins[0].Line;
    ins[insCnt].SOffset := 0; ins[insCnt].SLen := 0; Inc(insCnt);
    for k := 0 to np - 1 do
    begin
      if k > 0 then
      begin
        ins[insCnt].Kind := tkComma; ins[insCnt].IVal := 0; ins[insCnt].Line := ins[0].Line;
        ins[insCnt].SOffset := 0; ins[insCnt].SLen := 0; Inc(insCnt);
      end;
      ins[insCnt] := seenArg[si * MAX_TEMPLATE_PARAMS + k]; Inc(insCnt);
    end;
    ins[insCnt].Kind := tkGt; ins[insCnt].IVal := 0; ins[insCnt].Line := ins[0].Line;
    ins[insCnt].SOffset := 0; ins[insCnt].SLen := 0; Inc(insCnt);
    ins[insCnt].Kind := tkSemicolon; ins[insCnt].IVal := 0; ins[insCnt].Line := ins[0].Line;
    ins[insCnt].SOffset := 0; ins[insCnt].SLen := 0; Inc(insCnt);
    InsertTokens(insertAt, ins, insCnt);
    insertAt := insertAt + insCnt;
  end;
end;

procedure ParseGenericTemplate;
begin
  Next; { consume 'generic' }
  if CurTok.Kind <> tkIdent then Error('expected generic class name');
  ParseGenericTemplateNamed(CurTok.SVal, False);
end;

procedure ParseGenericTemplateNamed(const templateNameIn: AnsiString; delphiForm: Boolean);
var
  templateName, nextStr: AnsiString;
  depth, startTok, cur, finalCur, np, gi, scan: Integer;
  dgenAt, dgenRounds, dgenBefore, dgenT: Integer;   { the nested-specialize fixed point }
  pnames: array[0..MAX_TEMPLATE_PARAMS-1] of AnsiString;
  isOpener, doneParams, bodyless: Boolean;
begin
  { Copy BEFORE Next: callers pass CurTok.SVal, and a const AnsiString param
    aliases it by reference — Next would mutate the name out from under us. }
  templateName := templateNameIn;
  Next; { consume the template name (caller verified it) }

  { <T> / <TKey, TData> / <T: TObject> / <TKey; TData: TObject> — groups of
    comma-separated names, each group with an optional `: constraint` (the
    constraint list runs to the next `;` or `>`), groups separated by `;`.
    Constraints are parse-and-ignore: pxx generics are token-substitution, so
    the constraint has no checked meaning here (FPC enforces it at compile of
    the generic itself, which substitution defers to the specialization). }
  Expect(tkLt, '<');
  np := 0;
  doneParams := False;
  repeat
    repeat
      if CurTok.Kind <> tkIdent then Error('expected generic parameter name');
      if np >= MAX_TEMPLATE_PARAMS then Error('too many generic parameters (MAX_TEMPLATE_PARAMS)');
      pnames[np] := CurTok.SVal; Inc(np); Next;
    until not Eat(tkComma);
    if Eat(tkColon) then
      while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkGt) and
            (CurTok.Kind <> tkEOF) do
        Next;   { skip the constraint list }
    if not Eat(tkSemicolon) then doneParams := True;
  until doneParams;
  Expect(tkGt, '>');
  Expect(tkEq, '=');

  { Generic templates: class / record / packed record (depth-counted to the
    matching `end`), or array / procedure / function types (run to the
    terminating `;`) — feature-pascal-generic-nonclass-templates. Generics are
    token substitution, so capture is purely lexical; the specialization
    streams the body and ParseTypeSection's ordinary type-decl dispatch
    (class/record/array/procvar branches) parses it. }
  if not ((CurTok.Kind in [tkClass, tkRecord, tkPacked, tkArray,
                            tkProcedure, tkFunction]) or
          ((CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'interface'))) then
    Error('generic templates must be class, record, interface, array or procedure declarations');

  startTok := TokPos - 1;
  if CurTok.Kind = tkPacked then
  begin
    Next;   { capture includes 'packed'; depth-count from the 'record' }
    if CurTok.Kind <> tkRecord then Error('generic packed template must be a record');
  end;
  if (Tokens[startTok].Kind = tkArray) or (Tokens[startTok].Kind = tkProcedure) or
     (Tokens[startTok].Kind = tkFunction) then
  begin
    { no `end`: the body runs to the first ';' outside (),[] — and outside an
      inline `record ... end` element type (tgeneric25's
      `array[0..1] of record A: T; B: String; end`), whose own semicolons
      must not terminate the capture. }
    depth := 0;
    cur := TokPos;
    while cur < TokCount do
    begin
      if (Tokens[cur].Kind = tkLParen) or (Tokens[cur].Kind = tkLBrack) then Inc(depth)
      else if (Tokens[cur].Kind = tkRParen) or (Tokens[cur].Kind = tkRBrack) then Dec(depth)
      else if (Tokens[cur].Kind = tkRecord) or (Tokens[cur].Kind = tkClass) then
      begin
        { skip the whole record/class body: end-depth count }
        gi := 1;   { reuse gi as the end-depth counter }
        Inc(cur);
        while (cur < TokCount) and (gi > 0) do
        begin
          if (Tokens[cur].Kind = tkRecord) or (Tokens[cur].Kind = tkClass) then Inc(gi)
          else if Tokens[cur].Kind = tkEnd then Dec(gi);
          Inc(cur);
        end;
        continue;
      end
      else if (Tokens[cur].Kind = tkSemicolon) and (depth = 0) then Break;
      Inc(cur);
    end;
    if cur < TokCount then Inc(cur);   { include the ';' }
    finalCur := cur;
  end
  else
  begin
  { A class or interface declaration need not HAVE a body: a forward
    `class;`, a bodyless derived class `class(TBase);`, or a metaclass
    `class of T;`. There is no `end` to count down to, so the depth loop
    below would run on and swallow whatever declaration ends next --
    rtl-generics' one-line
      `TGStringComparer<T> = class(TGStringComparer<T, TDelphiQuadrupleHashFactory>);`
    captured 126 further lines into the template and reported the damage as
    an error deep inside the swallowed text. Detect the bodyless forms up
    front; only a real body goes through the depth count. }
  bodyless := False;
  cur := TokPos;
  if (Tokens[startTok].Kind = tkClass) or
     ((Tokens[startTok].Kind = tkIdent) and CaseEqual(GetTokenStr(startTok), 'interface')) then
  begin
    if (Tokens[startTok].Kind = tkClass) and (cur < TokCount) and (Tokens[cur].Kind = tkOf) then
    begin
      while (cur < TokCount) and (Tokens[cur].Kind <> tkSemicolon) do Inc(cur);
      bodyless := True;
    end
    else
    begin
      scan := cur;
      if (scan < TokCount) and (Tokens[scan].Kind = tkLParen) then
      begin
        depth := 0;
        repeat
          if Tokens[scan].Kind = tkLParen then Inc(depth)
          else if Tokens[scan].Kind = tkRParen then Dec(depth);
          Inc(scan);
        until (scan >= TokCount) or (depth = 0);
      end;
      if (scan < TokCount) and (Tokens[scan].Kind = tkSemicolon) then
      begin
        cur := scan;
        bodyless := True;
      end;
    end;
  end;

  if bodyless then
  begin
    if cur < TokCount then Inc(cur);   { include the ';' }
    finalCur := cur;
  end
  else
  begin
  depth := 1;
  cur := TokPos;
  while (cur < TokCount) and (depth > 0) do
  begin
    if Tokens[cur].Kind = tkClass then
    begin
      { `class function/procedure/var/property/of` (and soft
        constructor/destructor/operator) is a member prefix, not a nested
        class body — counting it as an opener swallowed the rest of the
        unit into the template. }
      isOpener := True;
      if cur + 1 < TokCount then
      begin
        if Tokens[cur+1].Kind in [tkFunction, tkProcedure, tkVar, tkProperty, tkOf] then
          isOpener := False
        else if Tokens[cur+1].Kind = tkIdent then
        begin
          nextStr := GetTokenStr(cur+1);
          if CaseEqual(nextStr, 'constructor') or CaseEqual(nextStr, 'destructor') or
             CaseEqual(nextStr, 'operator') then
            isOpener := False;
        end;
      end;
      if isOpener then Inc(depth);
    end
    else if Tokens[cur].Kind = tkRecord then
      Inc(depth)
    else if Tokens[cur].Kind = tkEnd then
      Dec(depth);
    Inc(cur);
  end;

  if (cur < TokCount) and (Tokens[cur].Kind = tkSemicolon) then
    Inc(cur);

  finalCur := cur;  { save before for-loop clobbers 'cur' }
  end;
  end;

  if TemplateCount >= MAX_TEMPLATES then Error('too many generic templates');
  Templates[TemplateCount].Name := templateName;
  for gi := 0 to np - 1 do
    TemplateParamNames[TemplateCount * MAX_TEMPLATE_PARAMS + gi] := pnames[gi];
  TemplateNParams[TemplateCount] := np;
  TemplateIsDelphi[TemplateCount] := delphiForm;
  Templates[TemplateCount].TokStart := TemplateTokenCount;
  Templates[TemplateCount].TokCount := 0;

  for cur := startTok to finalCur - 1 do
  begin
    if TemplateTokenCount >= MAX_TEMPLATE_TOKENS then
      Error('generic template tokens overflow');
    TemplateTokens[TemplateTokenCount].Kind := Tokens[cur].Kind;
    TemplateTokens[TemplateTokenCount].IVal := Tokens[cur].IVal;
    TemplateTokens[TemplateTokenCount].Line := Tokens[cur].Line;
    TemplateTokens[TemplateTokenCount].SOffset := Tokens[cur].SOffset;
    TemplateTokens[TemplateTokenCount].SLen := Tokens[cur].SLen;
    Inc(TemplateTokenCount);
    Templates[TemplateCount].TokCount := Templates[TemplateCount].TokCount + 1;
  end;

  Inc(TemplateCount);

  if DebugTrace then
    writeln('TEMPLATE ', templateName, ' startTok=', startTok, ' endTok=', finalCur,
            ' endLine=', Tokens[finalCur-1].Line);

  { mode-Delphi form (`TFoo<T> = class`): desugar the rest of the token stream
    to the objfpc surface the machinery above already speaks — rewrite each
    concrete use `TFoo<Args>` to a minted alias ident (registering the alias
    declaration tokens `alias = specialize TFoo<Args>;` right after this
    template), and strip `<T>` from method impls `procedure TFoo<T>.M`. }
  { Run to a FIXED POINT, not once. One round can only collapse a `<...>` group
    whose arguments are already plain idents, so
    `specialize TBox<specialize TBox<Integer>>` needs two: round 1 rewrites the
    INNER group (its own arguments are concrete) to the alias `TBox$Integer`,
    which leaves the outer group in the collapsible shape for round 2. The
    outer's arm bailed out on the inner `specialize` ident and left the literal
    word in the stream, so every position except a type section reported
    `unknown type: specialize` -- var, local, field, parameter and function
    result alike, all five of which FPC accepts.

    A round that rewrites nothing inserts no alias declaration, so an unchanged
    TokCount is exactly "nothing left to collapse". The cap is a runaway guard,
    not a real limit: depth is the nesting depth of the source expression.
    bug-a-a-nested-inline-specialize-is-refused-outside-a-type-section }
  dgenAt := finalCur;
  dgenRounds := 0;
  repeat
    dgenBefore := TokCount;
    { EVERY template each round, not just the one that was just parsed. The
      nesting crosses templates as readily as it repeats one --
      `specialize TList<specialize TPair<Integer, AnsiString>>` -- and TList's
      own sweep ran before TPair existed, so it could not have collapsed the
      inner group then. Re-sweeping the earlier templates once TPair's round has
      turned the inner group into a plain ident is what finishes the outer one. }
    for dgenT := 0 to TemplateCount - 1 do
      DelphiRewriteGenericUses(dgenT, dgenAt, TemplateIsDelphi[dgenT]);
    Inc(dgenRounds);
    if dgenRounds > 16 then
      Error('generic specialization nested deeper than 16 levels (or a rewrite loop)');
  until TokCount = dgenBefore;

  TokPos := finalCur;
  Next;
end;

{ Load the SpecSub* substitution set from a (template, specialization) pair. }
procedure SetSpecSubs(ti, si: Integer);
var k: Integer;
begin
  SpecSubCount := TemplateNParams[ti];
  for k := 0 to SpecSubCount - 1 do
  begin
    SpecSubNames[k]  := TemplateParamNames[ti * MAX_TEMPLATE_PARAMS + k];
    SpecSubValues[k] := SpecConcreteNames[si * MAX_TEMPLATE_PARAMS + k];
    SpecSubKinds[k]  := SpecConcreteKinds[si * MAX_TEMPLATE_PARAMS + k];
  end;
end;

{ Emit one `alias = specialize NAME<args>;` declaration into NSpecIns, reading
  the argument tokens from NSpecArg[base..base+nArgs-1]. }
procedure EmitSpecDecl(const aliasNm, tmplNm: AnsiString; base, nArgs: Integer);
var k: Integer; ln: Integer;
begin
  ln := 0;
  if TokPos > 0 then ln := Tokens[TokPos - 1].Line;
  if NSpecInsCnt + 8 + 2 * nArgs > MAX_NESTED_SPECS * (8 + 2 * MAX_TEMPLATE_PARAMS) then
    Error('nested specialization token buffer overflow');
  NSpecIns[NSpecInsCnt].Kind := tkIdent; NSpecIns[NSpecInsCnt].IVal := 0;
  NSpecIns[NSpecInsCnt].Line := ln;
  NSpecIns[NSpecInsCnt].SOffset := TokCharsAppend(aliasNm);
  NSpecIns[NSpecInsCnt].SLen := Length(aliasNm); Inc(NSpecInsCnt);
  NSpecIns[NSpecInsCnt].Kind := tkEq; NSpecIns[NSpecInsCnt].IVal := 0;
  NSpecIns[NSpecInsCnt].Line := ln; NSpecIns[NSpecInsCnt].SOffset := 0;
  NSpecIns[NSpecInsCnt].SLen := 0; Inc(NSpecInsCnt);
  NSpecIns[NSpecInsCnt].Kind := tkIdent; NSpecIns[NSpecInsCnt].IVal := 0;
  NSpecIns[NSpecInsCnt].Line := ln;
  NSpecIns[NSpecInsCnt].SOffset := TokCharsAppend('specialize');
  NSpecIns[NSpecInsCnt].SLen := 10; Inc(NSpecInsCnt);
  NSpecIns[NSpecInsCnt].Kind := tkIdent; NSpecIns[NSpecInsCnt].IVal := 0;
  NSpecIns[NSpecInsCnt].Line := ln;
  NSpecIns[NSpecInsCnt].SOffset := TokCharsAppend(tmplNm);
  NSpecIns[NSpecInsCnt].SLen := Length(tmplNm); Inc(NSpecInsCnt);
  NSpecIns[NSpecInsCnt].Kind := tkLt; NSpecIns[NSpecInsCnt].IVal := 0;
  NSpecIns[NSpecInsCnt].Line := ln; NSpecIns[NSpecInsCnt].SOffset := 0;
  NSpecIns[NSpecInsCnt].SLen := 0; Inc(NSpecInsCnt);
  for k := 0 to nArgs - 1 do
  begin
    if k > 0 then
    begin
      NSpecIns[NSpecInsCnt].Kind := tkComma; NSpecIns[NSpecInsCnt].IVal := 0;
      NSpecIns[NSpecInsCnt].Line := ln; NSpecIns[NSpecInsCnt].SOffset := 0;
      NSpecIns[NSpecInsCnt].SLen := 0; Inc(NSpecInsCnt);
    end;
    NSpecIns[NSpecInsCnt] := NSpecArg[base + k]; Inc(NSpecInsCnt);
  end;
  NSpecIns[NSpecInsCnt].Kind := tkGt; NSpecIns[NSpecInsCnt].IVal := 0;
  NSpecIns[NSpecInsCnt].Line := ln; NSpecIns[NSpecInsCnt].SOffset := 0;
  NSpecIns[NSpecInsCnt].SLen := 0; Inc(NSpecInsCnt);
  NSpecIns[NSpecInsCnt].Kind := tkSemicolon; NSpecIns[NSpecInsCnt].IVal := 0;
  NSpecIns[NSpecInsCnt].Line := ln; NSpecIns[NSpecInsCnt].SOffset := 0;
  NSpecIns[NSpecInsCnt].SLen := 0; Inc(NSpecInsCnt);
end;

{ Result = True means the declaration was DEFERRED: its nested generic
  prerequisites have been emitted ahead of a fresh copy of it, nothing was
  registered, and the caller must go round the type-section loop again rather
  than bind a class. See the nested-specialization note above SpecializeStream. }
function ParseSpecialization(const specName: AnsiString): Boolean;
var
  templateName, aliasNm: AnsiString;
  cNames: array[0..MAX_TEMPLATE_PARAMS-1] of AnsiString;
  cKinds: array[0..MAX_TEMPLATE_PARAMS-1] of TTokenKind;
  nc, ti, i, j, k, na, ts, tc, gEnd, si, dfIdx: Integer;
  dup: Boolean;
begin
  Result := False;
  Next; { consume 'specialize' }
  if CurTok.Kind <> tkIdent then Error('expected generic template name');
  templateName := CurTok.SVal; Next;

  Expect(tkLt, '<');
  nc := 0;
  NSpecCount := 0;
  repeat
    if (CurTok.Kind <> tkIdent) and (CurTok.Kind <> tkInteger_T) and (CurTok.Kind <> tkBoolean_T) and (CurTok.Kind <> tkChar_T) and (CurTok.Kind <> tkString_T) then
      Error('expected concrete type name');
    if nc >= MAX_TEMPLATE_PARAMS then Error('too many specialization arguments (MAX_TEMPLATE_PARAMS)');
    cNames[nc] := CurTok.SVal;
    cKinds[nc] := CurTok.Kind;
    { keep the raw token too — a deferral re-emits this declaration verbatim }
    NSpecArg[(MAX_NESTED_SPECS - 1) * MAX_TEMPLATE_PARAMS + nc] := Tokens[TokPos - 1];
    Inc(nc);
    Next;
  until not Eat(tkComma);
  Expect(tkGt, '>');
  { Leave CurTok on the trailing ';' (do NOT Eat) so SpecializeStream inserts
    the class-body tokens right after it; the final Next then lands CurTok on
    the inserted 'class', and the caller falls through to the class-binding
    branch (which names the concrete class from the saved tnOff/tnLen). }

  { Arity-overloaded template names are legal (`TD`, `TD<K>`, `TD<K,V>` — see
    test_generic_name_overload.pas), so the ARGUMENT COUNT is part of the
    lookup. Order alone used to be enough because a concrete use's alias
    declaration is inserted right behind its own template, and so is parsed
    before the next arity is even captured; a nested prerequisite is emitted
    much further down the stream, where every arity is visible at once. }
  ti := -1;
  for i := 0 to TemplateCount - 1 do
    if CaseEqual(Templates[i].Name, templateName) then
      if (ti < 0) or (TemplateNParams[i] = nc) then ti := i;
  if ti < 0 then Error('generic template ' + templateName + ' not found');
  if nc <> TemplateNParams[ti] then
    Error('specialize ' + templateName + ': wrong number of type arguments');

  { The substitution set is established HERE, before anything is registered,
    because the prerequisite scan below decides whether this declaration gets
    registered at all this time round. }
  SpecSubCount := nc;
  for i := 0 to nc - 1 do
  begin
    SpecSubNames[i]  := TemplateParamNames[ti * MAX_TEMPLATE_PARAMS + i];
    SpecSubValues[i] := cNames[i];
    SpecSubKinds[i]  := cKinds[i];
  end;

  { Nested generic prerequisites: every `specialize NAME<args>` in the body,
    with args mapped through the substitution, that is not a type yet. }
  ts := Templates[ti].TokStart;
  tc := Templates[ti].TokCount;
  i := 0;
  while i < tc do
  begin
    gEnd := NestedSpecGroup(ts, i, tc);
    if gEnd >= 0 then
    begin
      aliasNm := NestedSpecAlias(ts, i, gEnd);
      if (not CaseEqual(aliasNm, specName)) and (not NestedSpecKnown(aliasNm)) then
      begin
        dup := False;
        for k := 0 to NSpecCount - 1 do
          if CaseEqual(NSpecName[k], aliasNm) then dup := True;
        if not dup then
        begin
          if NSpecCount >= MAX_NESTED_SPECS - 1 then
            Error('too many nested generic specializations (MAX_NESTED_SPECS)');
          NSpecName[NSpecCount] := aliasNm;
          NSpecTmpl[NSpecCount] := GetTokenStrFromRaw(TemplateTokens[ts + i + 1].SOffset,
                                                     TemplateTokens[ts + i + 1].SLen);
          na := 0;
          j := i + 3;
          while j < gEnd do
          begin
            if TemplateTokens[ts + j].Kind <> tkComma then
            begin
              NestedSpecArg(ts, j, NSpecArg[NSpecCount * MAX_TEMPLATE_PARAMS + na]);
              Inc(na);
            end;
            Inc(j);
          end;
          NSpecNArg[NSpecCount] := na;
          Inc(NSpecCount);
        end;
      end;
      i := gEnd + 1;
    end
    else
      Inc(i);
  end;

  { A prerequisite queued by one deferral may already have been satisfied by
    another: rtl-generics reaches TCustomComparer$string through BOTH
    TGStringComparer and TOrdinalComparer, and each deferral emits its own copy
    of the alias declaration. The second copy is an exact re-statement of the
    first -- same template, same arguments, and the name is minted from exactly
    those -- so it is a no-op, not a redeclaration. Consume it and let the
    type-section loop go round again. A name that collides with a DIFFERENT
    template or different arguments still falls through to the ordinary
    duplicate-class diagnosis. }
  si := FindSpecialization(specName);
  if (si >= 0) and CaseEqual(Specializations[si].TemplateName, templateName) and
     (SpecNParams[si] = nc) then
  begin
    dup := True;
    for i := 0 to nc - 1 do
      if not CaseEqual(SpecConcreteNames[si * MAX_TEMPLATE_PARAMS + i], cNames[i]) then
        dup := False;
    if dup then
    begin
      if DebugTrace then writeln('SPEC ', specName, ' = ', templateName, ' (already declared)');
      NSpecCount := 0;
      Next;
      Result := True;
      Exit;
    end;
  end;

  if DebugTrace then
  begin
    writeln('SPEC ', specName, ' = ', templateName, ' nested=', NSpecCount);
    for k := 0 to NSpecCount - 1 do
      writeln('  needs ', NSpecName[k], ' from ', NSpecTmpl[k]);
  end;

  if NSpecCount > 0 then
  begin
    { Defer. CurTok is this declaration's trailing ';', so TokPos is exactly
      where the type-section loop reads next: put the prerequisites there,
      followed by a fresh copy of this declaration. Nothing has been registered,
      so the retry is a clean re-parse. }
    dfIdx := -1;
    for k := 0 to SpecDeferCount - 1 do
      if CaseEqual(SpecDeferName[k], specName) then dfIdx := k;
    if dfIdx < 0 then
    begin
      if SpecDeferCount >= MAX_SPECIALIZATIONS then Error('too many deferred specializations');
      dfIdx := SpecDeferCount;
      SpecDeferName[dfIdx] := specName;
      SpecDeferRound[dfIdx] := 0;
      Inc(SpecDeferCount);
    end;
    Inc(SpecDeferRound[dfIdx]);
    { A deferral is only progress while the unmet prerequisite set shrinks, and
      it cannot legitimately take more rounds than there are specializations in
      the whole program. More than that means a CYCLE -- two specializations
      requiring each other -- which used to spin forever, inserting a fresh copy
      of both declarations into the token stream every round with no diagnostic
      and no end. Name both sides: the cycle is what the author has to break. }
    if SpecDeferRound[dfIdx] > MAX_SPECIALIZATIONS then
      Error('circular generic specialization: ' + specName + ' requires ' +
            NSpecName[0] + ', which requires ' + specName + ' back');
    NSpecInsCnt := 0;
    for k := 0 to NSpecCount - 1 do
      EmitSpecDecl(NSpecName[k], NSpecTmpl[k], k * MAX_TEMPLATE_PARAMS, NSpecNArg[k]);
    EmitSpecDecl(specName, templateName, (MAX_NESTED_SPECS - 1) * MAX_TEMPLATE_PARAMS, nc);
    InsertTokens(TokPos, NSpecIns, NSpecInsCnt);
    NSpecCount := 0;
    Next;
    Result := True;
    Exit;
  end;

  if SpecializationCount >= MAX_SPECIALIZATIONS then Error('too many specializations');
  Specializations[SpecializationCount].Name := specName;
  Specializations[SpecializationCount].TemplateName := templateName;
  for i := 0 to nc - 1 do
  begin
    SpecConcreteKinds[SpecializationCount * MAX_TEMPLATE_PARAMS + i] := cKinds[i];
    SpecConcreteNames[SpecializationCount * MAX_TEMPLATE_PARAMS + i] := cNames[i];
  end;
  SpecNParams[SpecializationCount] := nc;
  SpecUnitIdx[SpecializationCount] := CurrentUnitIdx;
  Inc(SpecializationCount);

  { Stream the concrete class body inline so the fall-through binds the alias
    name. Methods that were buffered BEFORE this specialization (template in a
    used unit) cannot be streamed here — a `procedure` token would close the
    type section and orphan any following specialization — so defer them to a
    pending queue that ParseTypeSection flushes once the section ends. Methods
    buffered AFTER this point are streamed by BufferGenericMethod, so each
    (method, specialization) pair is materialised exactly once. }
  if GenericMethodCount > 0 then
  begin
    if PendingSpecCount >= MAX_PENDING_SPECS then Error('too many pending specializations');
    PendingSpecTi[PendingSpecCount] := ti;
    PendingSpecIdx[PendingSpecCount] := SpecializationCount - 1;
    Inc(PendingSpecCount);
  end;

  SpecializeTemplateName := Templates[ti].Name;
  SetSpecSubs(ti, SpecializationCount - 1);
  SpecializeStream(Templates[ti].TokStart, Templates[ti].TokCount, specName);
  Next;
end;

{ Materialise the methods of every class specialization buffered during the
  type section just parsed. Called once the section's token loop exits, so the
  streamed `procedure`/`function` bodies land after the whole `type` block and
  are parsed as ordinary top-level subroutines. Inserting at TokPos prepends
  before the section-terminating token, which was un-read by the caller. }
procedure FlushPendingClassSpecializations;
var p, gm, ti, si: Integer;
begin
  for p := 0 to PendingSpecCount - 1 do
  begin
    ti := PendingSpecTi[p];
    si := PendingSpecIdx[p];
    SpecializeTemplateName := Templates[ti].Name;
    SetSpecSubs(ti, si);
    for gm := 0 to GenericMethodCount - 1 do
      if GenericMethods[gm].TemplateIdx = ti then
        SpecializeStream(GenericMethods[gm].TokStart, GenericMethods[gm].TokCount,
          Specializations[si].Name);
  end;
  PendingSpecCount := 0;
end;

procedure BufferGenericMethod(ti, startTokIdx: Integer);
var
  depth, cur, finalCur: Integer;
  si, mStart, mCount: Integer;
begin
  depth := 0;
  cur := startTokIdx;
  while (cur < TokCount) and (Tokens[cur].Kind <> tkBegin) do
    Inc(cur);
  if cur >= TokCount then Error('expected begin in generic method');

  depth := 1;
  Inc(cur);
  while (cur < TokCount) and (depth > 0) do
  begin
    if Tokens[cur].Kind in [tkBegin, tkCase] then
      Inc(depth)
    else if Tokens[cur].Kind = tkEnd then
      Dec(depth);
    Inc(cur);
  end;

  if (cur < TokCount) and (Tokens[cur].Kind = tkSemicolon) then
    Inc(cur);

  finalCur := cur;  { save before for-loop clobbers 'cur' }

  mStart := TemplateTokenCount;
  mCount := 0;
  for cur := startTokIdx to finalCur - 1 do
  begin
    if TemplateTokenCount >= MAX_TEMPLATE_TOKENS then
      Error('generic template tokens overflow');
    TemplateTokens[TemplateTokenCount].Kind := Tokens[cur].Kind;
    TemplateTokens[TemplateTokenCount].IVal := Tokens[cur].IVal;
    TemplateTokens[TemplateTokenCount].Line := Tokens[cur].Line;
    TemplateTokens[TemplateTokenCount].SOffset := Tokens[cur].SOffset;
    TemplateTokens[TemplateTokenCount].SLen := Tokens[cur].SLen;
    Inc(TemplateTokenCount);
    mCount := mCount + 1;
  end;

  { Remember the buffered method so a later specialization (parsed after this
    method, e.g. template in a unit + `specialize` in the program) can still
    materialise it. See ParseSpecialization. }
  if GenericMethodCount >= MAX_GENERIC_METHODS then Error('too many generic methods');
  GenericMethods[GenericMethodCount].TemplateIdx := ti;
  GenericMethods[GenericMethodCount].TokStart := mStart;
  GenericMethods[GenericMethodCount].TokCount := mCount;
  Inc(GenericMethodCount);

  { Insert specializations AFTER the template method body, not at the dot
    position. Only specializations already registered are streamed here; ones
    declared later stream this method from ParseSpecialization, so each
    (method, specialization) pair is materialised exactly once. }
  TokPos := finalCur;
  for si := 0 to SpecializationCount - 1 do
  begin
    if CaseEqual(Specializations[si].TemplateName, Templates[ti].Name) then
    begin
      SpecializeTemplateName := Templates[ti].Name;
      SetSpecSubs(ti, si);
      SpecializeStream(mStart, mCount, Specializations[si].Name);
    end;
  end;

  { TokPos = finalCur (InsertTokens doesn't change it); parser reads from first specialization }
  Next;
end;

function FindGenericFunc(const name: AnsiString): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to GenericFuncCount - 1 do
    if CaseEqual(GenericFuncs[i].Name, name) then begin Result := i; Exit; end;
end;

function IsGenericTemplateName(const name: AnsiString): Boolean;
{ True when the name is a registered generic TEMPLATE (`TFoo<T>`), i.e. not a type on
  its own — it has no size and no zero value until it is specialized. A specialization
  is registered under its own concrete name, so this never fires for one. }
var i: Integer;
begin
  Result := False;
  for i := 0 to TemplateCount - 1 do
    if CaseEqual(Templates[i].Name, name) then begin Result := True; Exit; end;
end;

{ Parses: generic function Max<T>(A, B: T): T; begin...end;
  Called when CurTok = tkIdent('generic') }
procedure ParseGenericFunctionDef;
var isFunc: Boolean; funcName, paramName: AnsiString;
    gfi, j, cur, finalCur, depth: Integer;
begin
  Next; { consume 'generic' }
  if (CurTok.Kind <> tkFunction) and (CurTok.Kind <> tkProcedure) then
    Error('expected function or procedure after generic');
  isFunc := CurTok.Kind = tkFunction;
  Next; { consume function/procedure }

  if CurTok.Kind <> tkIdent then Error('expected generic function name');
  funcName := CurTok.SVal; Next;

  Expect(tkLt, '<');
  if CurTok.Kind <> tkIdent then Error('expected generic type parameter');
  paramName := CurTok.SVal; Next;
  Expect(tkGt, '>');
  { CurTok = '(' of param list, or ';' / ':' if no params }

  if GenericFuncCount >= MAX_GENERIC_FUNCS then Error('too many generic functions');
  gfi := GenericFuncCount;
  GenericFuncs[gfi].Name     := funcName;
  GenericFuncs[gfi].Param    := paramName;
  GenericFuncs[gfi].IsFunc   := isFunc;
  GenericFuncs[gfi].TokStart := TemplateTokenCount;
  GenericFuncs[gfi].TokCount := 0;

  { Prepend synthetic 'function/procedure funcName' tokens into template buffer }
  TemplateTokens[TemplateTokenCount].IVal := 0;
  TemplateTokens[TemplateTokenCount].Line := 0;
  if isFunc then TemplateTokens[TemplateTokenCount].Kind := tkFunction
  else TemplateTokens[TemplateTokenCount].Kind := tkProcedure;
  TemplateTokens[TemplateTokenCount].SOffset := TokCharLen;
  TemplateTokens[TemplateTokenCount].SLen := 0;
  Inc(TemplateTokenCount);
  GenericFuncs[gfi].TokCount := GenericFuncs[gfi].TokCount + 1;

  TemplateTokens[TemplateTokenCount].Kind := tkIdent;
  TemplateTokens[TemplateTokenCount].IVal := 0;
  TemplateTokens[TemplateTokenCount].Line := 0;
  TemplateTokens[TemplateTokenCount].SOffset := TokCharLen;
  TemplateTokens[TemplateTokenCount].SLen := Length(funcName);
  if TokCharLen + Length(funcName) > STRING_CAP then Error('token char pool overflow');
  for j := 1 to Length(funcName) do
  begin
    TokChars[TokCharLen] := funcName[j];
    Inc(TokCharLen);
  end;
  Inc(TemplateTokenCount);
  GenericFuncs[gfi].TokCount := GenericFuncs[gfi].TokCount + 1;

  { Buffer remaining tokens: (A,B:T):T; begin...end; }
  { TokPos-1 = index of current token '(' in Tokens array }
  cur := TokPos - 1;
  while (cur < TokCount) and (Tokens[cur].Kind <> tkBegin) do Inc(cur);
  depth := 1; Inc(cur);
  while (cur < TokCount) and (depth > 0) do
  begin
    if Tokens[cur].Kind in [tkBegin, tkCase] then Inc(depth)
    else if Tokens[cur].Kind = tkEnd then Dec(depth);
    Inc(cur);
  end;
  if (cur < TokCount) and (Tokens[cur].Kind = tkSemicolon) then Inc(cur);
  finalCur := cur;

  for cur := TokPos - 1 to finalCur - 1 do
  begin
    if TemplateTokenCount >= MAX_TEMPLATE_TOKENS then Error('generic template tokens overflow');
    TemplateTokens[TemplateTokenCount].Kind := Tokens[cur].Kind;
    TemplateTokens[TemplateTokenCount].IVal := Tokens[cur].IVal;
    TemplateTokens[TemplateTokenCount].Line := Tokens[cur].Line;
    TemplateTokens[TemplateTokenCount].SOffset := Tokens[cur].SOffset;
    TemplateTokens[TemplateTokenCount].SLen := Tokens[cur].SLen;
    Inc(TemplateTokenCount);
    GenericFuncs[gfi].TokCount := GenericFuncs[gfi].TokCount + 1;
  end;

  Inc(GenericFuncCount);
  TokPos := finalCur;
  Next;
end;

{ Parses: specialize Max<Integer> as MaxInt;
  Called when CurTok = tkIdent('specialize') at top level }
procedure ParseTopLevelSpecialize;
var templateName, concreteName, specName: AnsiString;
    concreteKind: TTokenKind; gfi, i: Integer;
begin
  Next; { consume 'specialize' }
  if CurTok.Kind <> tkIdent then Error('expected generic function name after specialize');
  templateName := CurTok.SVal; Next;

  Expect(tkLt, '<');
  if (CurTok.Kind = tkIdent) or (CurTok.Kind = tkInteger_T) or
     (CurTok.Kind = tkBoolean_T) or (CurTok.Kind = tkChar_T) or
     (CurTok.Kind = tkString_T) then
  begin
    concreteName := CurTok.SVal;
    concreteKind := CurTok.Kind;
    Next;
  end
  else
    Error('expected concrete type in specialize');
  Expect(tkGt, '>');

  { Optional 'as Name' }
  if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'as') then
  begin
    Next;
    if CurTok.Kind <> tkIdent then Error('expected name after as');
    specName := CurTok.SVal; Next;
  end
  else
  begin
    { Auto-generate: Max_Integer }
    specName := templateName;
    AppendChar(specName, '_');
    i := 1;
    while i <= Length(concreteName) do begin AppendChar(specName, concreteName[i]); Inc(i); end;
  end;
  { CurTok = ';' — do NOT Eat here. Insert at TokPos (after ';') so that
    after ParseSubroutine finishes its own 'end;', CurTok lands on the next
    top-level token (next specialize/begin/etc.) rather than skipping it. }

  gfi := FindGenericFunc(templateName);
  if gfi < 0 then Error('generic function ' + templateName + ' not found');

  SpecializeTemplateName := GenericFuncs[gfi].Name;
  { generic FUNCTIONS stay single-parameter — load the substitution set directly }
  SpecSubCount := 1;
  SpecSubNames[0]  := GenericFuncs[gfi].Param;
  SpecSubValues[0] := concreteName;
  SpecSubKinds[0]  := concreteKind;
  SpecializeStream(GenericFuncs[gfi].TokStart, GenericFuncs[gfi].TokCount, specName);
  Next;
  ParseSubroutine;
end;
