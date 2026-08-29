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
    if not IsConcreteTypeArgKind(TemplateTokens[ts + j].Kind) then Exit;
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

{ Which template a TemplateTokens[] pool index belongs to, as a KeyStrs id for
  its source file (-1 when unknown). Templates are captured in pool order and
  there are at most MAX_TEMPLATES of them, so a linear scan is the whole
  implementation. }
function TemplateSrcKeyOfTok(t: Integer): Integer;
var i: Integer;
begin
  TemplateSrcKeyOfTok := -1;
  for i := 0 to TemplateCount - 1 do
    if (t >= Templates[i].TokStart) and
       (t < Templates[i].TokStart + Templates[i].TokCount) then
    begin
      TemplateSrcKeyOfTok := TemplateSrcKey[i];
      Exit;
    end;
end;

{ Is the identifier at TemplateTokens[base + i] a DECLARATION NAME rather than a
  use of a type? Substitution is token-based — it rewrites every tkIdent whose
  text matches a type-parameter name — and that is correct only in TYPE
  positions. A template may legally name a field, parameter, local, constant or
  method with the same identifier as one of its own type parameters, and Pascal
  is case-INSENSITIVE, so `record t: T; end` collides too. Rewriting the name
  turned `record t: T` into `record String: String` and the matching `FR.t` into
  `FR.String`, i.e. "no such member" — the declaration and its use were corrupted
  in lockstep, which is why the error surfaced far from the cause.

  Three name positions, each decided from adjacent tokens only (this runs over a
  flat token stream, before any parse):

  1. after `.` — a member selector (`FR.t`, `Self.T`). A type parameter never
     legitimately follows a dot inside a template body.
  2. after `procedure`/`function`/`property`/`constructor`/`destructor` — the
     routine being named. Implementation headers (`procedure TG.T`) are already
     covered by case 1.
  3. a declaration-name list: the identifier is followed by `:`, or by a run of
     `, ident` pairs that ends in `:` — `t: T`, `a, t: T`, `const t: T`. An
     identifier followed by `:` is a name or a label in every Pascal form; a type
     parameter in a genuine type position is followed by `;`, `)`, `of`, `=` or
     `end`, never by `:`.

  Knowing the name positions is only half of it: once a template DECLARES a
  colliding name, its ordinary USES (`t := x`, `Writeln(t)`) are bare
  identifiers that must not be substituted either. Those are indistinguishable
  from a type use by adjacency alone, so SpecializeStream runs this in two
  passes — pass 1 marks a type parameter SHADOWED if the template declares its
  name anywhere, and for a shadowed parameter only pass 2 substitutes just the
  unambiguous type positions (after `:` or `of`).

  The two-pass split is what keeps this from regressing working code: a
  parameter the template does not shadow behaves exactly as before, typecasts
  `T(x)` included. Only a template that declares a colliding name — which was
  broken outright — sees the narrower rule. A shadowed parameter used in a type
  position this rule does not list (a bare `T(x)` cast) stays unsubstituted;
  that is the residual, and it needs scope rather than adjacency. }
{ An unambiguous TYPE position for a SHADOWED type parameter: directly after
  `:` (`t: T`, `function F: T`) or after `of` (`array of T`, `set of T`). Kept
  deliberately narrow — it only ever narrows behaviour for a parameter the
  template shadows, and a false negative there costs an unsubstituted token in a
  program that did not compile at all before. }
function SpecTypePosition(base, i: Integer): Boolean;
begin
  SpecTypePosition := False;
  if i <= 0 then Exit;
  SpecTypePosition := (TemplateTokens[base + i - 1].Kind = tkColon) or
                      (TemplateTokens[base + i - 1].Kind = tkOf);
end;

function SpecSubNamePosition(base, i, count: Integer): Boolean;
var j: Integer; prev: AnsiString;
begin
  SpecSubNamePosition := True;
  if i > 0 then
  begin
    if TemplateTokens[base + i - 1].Kind = tkDot then Exit;
    if (TemplateTokens[base + i - 1].Kind = tkProcedure) or
       (TemplateTokens[base + i - 1].Kind = tkFunction) or
       (TemplateTokens[base + i - 1].Kind = tkProperty) then Exit;
    { `constructor` / `destructor` are SOFT keywords here -- compared by text and
      delivered as tkIdent (pasparser_class.inc), so there is no token kind to
      match on. }
    if TemplateTokens[base + i - 1].Kind = tkIdent then
    begin
      prev := GetTokenStrFromRaw(TemplateTokens[base + i - 1].SOffset,
                                 TemplateTokens[base + i - 1].SLen);
      if CaseEqual(prev, 'constructor') or CaseEqual(prev, 'destructor') then Exit;
    end;
  end;
  { `ident :` and `ident , ident , ... :` }
  j := i + 1;
  while (j + 1 < count) and (TemplateTokens[base + j].Kind = tkComma) and
        (TemplateTokens[base + j + 1].Kind = tkIdent) do
    Inc(j, 2);
  if (j < count) and (TemplateTokens[base + j].Kind = tkColon) then Exit;
  SpecSubNamePosition := False;
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
  { PASS 1 — which type parameters does this template also declare as a name?
    ACCUMULATES into SpecSubShadowed (reset per specialization in SetSpecSubs):
    the class body and each method body arrive as separate calls, and a field
    declared in the body is used in the methods. }
  for i := 0 to count - 1 do
    if (TemplateTokens[tokStart + i].Kind = tkIdent) and
       SpecSubNamePosition(tokStart, i, count) then
    begin
      s := GetTokenStrFromRaw(TemplateTokens[tokStart + i].SOffset,
                              TemplateTokens[tokStart + i].SLen);
      for k := 0 to SpecSubCount - 1 do
        if CaseEqual(s, SpecSubNames[k]) then SpecSubShadowed[k] := True;
    end;
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
      else if not SpecSubNamePosition(tokStart, i, count) then
        for k := 0 to SpecSubCount - 1 do
          if CaseEqual(s, SpecSubNames[k]) and
             ((not SpecSubShadowed[k]) or SpecTypePosition(tokStart, i)) then
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
  { A hand-rolled InsertTokens — so it owes the same bookkeeping. The token->file
    map is keyed on absolute indices, and a specialization splice is by far the
    largest edit any Pascal source sees (rtl-generics' Generics.Defaults grows by
    tens of thousands of tokens), so a missed adjustment here moved every later
    file boundary deep into the WRONG unit: the `in:` line then named a 707-line
    RTL file for an error on line 2074 of the corpus unit.
    bug-a-a-diagnostic-in-a-used-unit-names-the-wrong-source-file }
  AdjustSrcRanges(TokPos, subCount);
  { …and NOT AdjustPass2Spans, unlike InsertTokens, which calls both. That is
    correct here, not an omission: no splice site can be reached while
    Pass2Active is true, so the span adjustment would be a no-op.

    Pass 2 replays recorded DeclItem spans through ParseSubroutine and nothing
    else. Every caller of this splice is a DECLARATION parser:

      ParseSpecialization                 <- ParseTypeSection
      FlushPendingClassSpecializations    <- ParseTypeSection
      SpecializeInlineGenericFuncUses     <- ParseGenericFunctionDef
      ParseOperatorDef                    <- ParseProgram / ParseUnit
      BufferGenericMethod                 <- ParseSubroutine … but see below

    BufferGenericMethod is the one that looks reachable, and is not:
    GenericMethodBuffered (defs.inc) exists so the pass-1 driver does NOT record
    a generic method impl as a replayable DeclItem — "replaying it in pass 2
    would double-buffer and corrupt the token stream", which is a stronger
    statement than this one and already relied upon.

    A `specialize` written INSIDE a routine body does not splice from the body:
    it resolves a declaration-level specialization, which is why the hoisting
    SpecializeInlineGenericFuncUses does for the function form is the same shape
    the class form has always had.

    Measured 2026-08-27 as well as argued: with `if Pass2Active then Error(...)`
    at all five sites, a full self-host fixedpoint, gate.sh quick, 346 Pascal
    conformance tests, 220 C conformance tests and the fgl corpus all passed;
    and with a Warn instead, the sites demonstrably ARE reached (five times in a
    program written to put a specialization and an operator desugar inside
    routine bodies), every time with Pass2Active false.
    bug-a-the-specialization-splice-does-not-adjust-the-body-pass-spans }
  { ...and the pasted region's own provenance, which the adjustment above cannot
    supply: these tokens are the TEMPLATE's, not this file's. Without it the
    specialized body's diagnostics carried fgl.pp's line numbers under the
    program's file name. }
  PasSpliceTokFile(TokPos, subCount, TemplateSrcKeyOfTok(tokStart));
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
           IsConcreteTypeArgKind(Tokens[j].Kind) then
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
            { A method-implementation header is identified by what PRECEDES
              the name -- `procedure` / `function` / `constructor` /
              `destructor` (the last two are SOFT keywords, lexed as tkIdent,
              so they are compared by text) -- NOT by the dot that follows it.
              `TCmp<T>.Default` in EXPRESSION position also has a dot after the
              group, so the follow-test classified a USE as a header, deleted
              its `<T>`, and left a bare template name behind: `undefined
              variable (TCmp)` on rtl-generics' dominant comparer idiom.
              bug-p-a-generic-class-method-call-is-undefined-inside-another-generics-body }
            if (j + 1 < TokCount) and (Tokens[j + 1].Kind = tkDot) and
               (i > 0) and
               ((Tokens[i - 1].Kind = tkProcedure) or
                (Tokens[i - 1].Kind = tkFunction) or
                ((Tokens[i - 1].Kind = tkIdent) and
                 (CaseEqual(GetTokenStrFromRaw(Tokens[i - 1].SOffset,
                                               Tokens[i - 1].SLen), 'constructor') or
                  CaseEqual(GetTokenStrFromRaw(Tokens[i - 1].SOffset,
                                               Tokens[i - 1].SLen), 'destructor')))) then
            begin
              { Deleting `<T>` here makes this header indistinguishable from the
                impl of a same-named NON-generic class's method, and the resolver
                downstream then picks by name. Record the class-name token's
                source offset first so it can pick by fact instead. See
                GenMethImplSOff in defs.inc. }
              if GenMethImplCount < MAX_GEN_METH_IMPL then
              begin
                GenMethImplSOff[GenMethImplCount] := Tokens[i].SOffset;
                Inc(GenMethImplCount);
              end;
              RemoveTokens(i + 1, j - i);   { method impl reference }
            end
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
  { Where this template's tokens CAME from, captured now because it is the only
    moment the answer is available: at splice time the body has been copied into
    the template pool and its origin index is gone. }
  if PasSrcOfTok(startTok) <> '' then
    TemplateSrcKey[TemplateCount] := InternKey(PasSrcOfTok(startTok))
  else
    TemplateSrcKey[TemplateCount] := -1;

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
  { Shadowing is a property of the TEMPLATE's own declarations, so it is
    computed once per template and survives every stream of it. Resetting per
    specialization cleared the class body's findings before the method bodies
    streamed, which is exactly the case a field named after a type parameter
    hits. }
  if (not SpecSubShadowValid) or (ti <> SpecSubShadowTi) then
  begin
    for k := 0 to SpecSubCount - 1 do SpecSubShadowed[k] := False;
    SpecSubShadowTi := ti;
    SpecSubShadowValid := True;
  end;
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
{ Sweep this template's mode-Delphi method impls for nested prerequisites,
  bounded by the header offsets DelphiRewriteGenericUses RECORDED when it deleted
  a `<T>` (GenMethImplSOff). Attribution is by construction: a range is scanned
  only when its offset is a recorded header of THIS template, never by matching
  argument names -- `T` and `U` are the commonest parameter names there are, and
  matching on shape would register a prerequisite under the wrong substitution.

  The copy is SCRATCH. BufferGenericMethod keeps "each (method, specialization)
  pair is materialised exactly once" by a before/after split, so registering
  these as buffered methods would make the parser's own later call the second
  buffering of the same body. TemplateTokenCount is restored.

  Called twice, at two different times, and the second time is the point:
  from ParseSpecialization (the method impls the parser has not reached yet) and
  from EmitLateNestedSpecDecls at the end of the type section, by which time the
  rewrite has run over bodies it had not reached the first time. }
{ Forwards for the three helpers below. All three are DEFINED later in this file
  and CALLED here, by ScanDelphiMethodImplsForNestedSpecs. pxx's own self-host
  resolves that either way; the FPC seed build does not, and fails with
  `Identifier not found`. See bug-a-fpc-seed-drift-emitasmx64-forward -- `make
  compiler/pascal26` is green in exactly this situation, so gate.sh quick is what
  catches it. Keep these ABOVE the first caller, not merely somewhere in the file. }
function GenericMethodBodyEnd(startTokIdx: Integer): Integer; forward;
procedure AppendTokenRangeToTemplateArena(fromIdx, toIdx: Integer;
                                         var ts, tc: Integer); forward;
procedure ScanRangeForNestedSpecs(ts, tc: Integer; const specName: AnsiString); forward;
function IsDelphiGenMethImplHdr(soff: Integer): Boolean; forward;

procedure ScanDelphiMethodImplsForNestedSpecs(ti: Integer; const specName: AnsiString);
var dScan, dHdr, dBase, ts, tc: Integer;
begin
  if GenMethImplCount = 0 then Exit;
  for dScan := 0 to TokCount - 1 do
    if (Tokens[dScan].Kind = tkIdent) and (dScan + 1 < TokCount) and
       (Tokens[dScan + 1].Kind = tkDot) and (dScan >= 1) and
       CaseEqual(GetTokenStrFromRaw(Tokens[dScan].SOffset, Tokens[dScan].SLen),
                 Templates[ti].Name) and
       IsDelphiGenMethImplHdr(Tokens[dScan].SOffset) then
    begin
      { the captured range starts at `procedure`/`function`, one earlier for a
        `class` method -- the same two shapes BufferGenericMethod is called with }
      dHdr := dScan - 1;
      if (dScan >= 2) and (Tokens[dScan - 2].Kind = tkClass) then dHdr := dScan - 2;
      dBase := TemplateTokenCount;
      AppendTokenRangeToTemplateArena(dHdr, GenericMethodBodyEnd(dHdr), ts, tc);
      ScanRangeForNestedSpecs(ts, tc, specName);
      TemplateTokenCount := dBase;   { scratch only: NOT a buffered method }
    end;
end;

{ End of a top-level type section: emit alias declarations for nested
  specializations that could not be seen when the class was specialized.

  WHY THIS TIME AND NOT EARLIER. In mode Delphi the rewrite emits a template's
  alias right behind THAT template's own declaration, so ParseSpecialization can
  run before a template mentioned in its method bodies has even been declared --
  and until that template is declared, `TDeriv<T>` in the body has not been
  rewritten to `specialize TDeriv<T>`, so there is nothing for any scan to match
  (the trace shows a bare `nested=0`). By the end of the section every template
  in it is declared and the rewrite has swept the bodies, so the same scan now
  finds them.

  WHY EMITTING HERE IS ENOUGH. The alias only has to be REGISTERED before the
  method is streamed, not before the class is specialized: `NestedSpecKnown`
  consults registered specializations, and the method impls sit after this
  section, so a declaration inserted at TokPos is parsed first. Verified
  directly before this was written -- adding a plain `TDeriv<UnicodeString>`
  instantiation by hand ahead of the method impl makes the failing program
  compile and match FPC.
  bug-p-a-generic-specialized-before-its-declaration-is-unresolvable }
procedure EmitLateNestedSpecDecls;
var si, ti, k: Integer;
begin
  if (GenMethImplCount = 0) or (SpecializationCount = 0) then Exit;
  NSpecCount := 0;
  NSpecInsCnt := 0;
  for si := 0 to SpecializationCount - 1 do
  begin
    ti := -1;
    for k := 0 to TemplateCount - 1 do
      if CaseEqual(Templates[k].Name, Specializations[si].TemplateName) then ti := k;
    if ti < 0 then Continue;
    SpecializeTemplateName := Templates[ti].Name;
    SetSpecSubs(ti, si);
    ScanDelphiMethodImplsForNestedSpecs(ti, Specializations[si].Name);
  end;
  if NSpecCount > 0 then
  begin
    { A leading `type`. The section loop has already EXITED, so these land at top
      level, where a bare `X = specialize Y<Z>;` is not a declaration -- the
      parser reads it where it expects `begin`/`procedure`/`type` and reports
      *Expected: begin*. The pending-flush path next door needs no such keyword
      because what IT inserts is `procedure` bodies, which are valid there as
      they stand. }
    NSpecIns[NSpecInsCnt].Kind := tkType; NSpecIns[NSpecInsCnt].IVal := 0;
    NSpecIns[NSpecInsCnt].Line := Tokens[TokPos].Line;
    NSpecIns[NSpecInsCnt].SOffset := 0; NSpecIns[NSpecInsCnt].SLen := 0;
    Inc(NSpecInsCnt);
    for k := 0 to NSpecCount - 1 do
      EmitSpecDecl(NSpecName[k], NSpecTmpl[k], k * MAX_TEMPLATE_PARAMS, NSpecNArg[k]);
    InsertTokens(TokPos, NSpecIns, NSpecInsCnt);
  end;
  NSpecCount := 0;
end;

{ Forwards: both are DEFINED beside BufferGenericMethod, further down this file,
  and USED by ParseSpecialization above it. pxx's own self-host resolves that
  either way; the FPC seed build does not, and fails with `Identifier not found`.
  See bug-a-fpc-seed-drift-emitasmx64-forward -- `make compiler/pascal26` is
  green in exactly this situation, so gate.sh quick is what catches it. }

{ Was this class-name token offset recorded by DelphiRewriteGenericUses as a
  method-impl header it stripped a `<T>` from? See GenMethImplSOff in defs.inc. }
function IsDelphiGenMethImplHdr(soff: Integer): Boolean;
var i: Integer;
begin
  IsDelphiGenMethImplHdr := False;
  for i := 0 to GenMethImplCount - 1 do
    if GenMethImplSOff[i] = soff then
    begin
      IsDelphiGenMethImplHdr := True;
      Exit;
    end;
end;

{ Record every `specialize NAME<args>` in one template-arena range as a nested
  prerequisite, skipping this declaration itself and anything already known or
  already queued. One body, three callers (the class body, each buffered method,
  and each not-yet-buffered mode-Delphi method impl) -- a second copy per source
  is how the method-body arm came to be missing in the first place. }
procedure ScanRangeForNestedSpecs(ts, tc: Integer; const specName: AnsiString);
var i, j, k, na, gEnd: Integer; aliasNm: AnsiString; dup: Boolean;
begin
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
end;

function ParseSpecialization(const specName: AnsiString): Boolean;
var
  templateName, aliasNm: AnsiString;
  cNames: array[0..MAX_TEMPLATE_PARAMS-1] of AnsiString;
  cKinds: array[0..MAX_TEMPLATE_PARAMS-1] of TTokenKind;
  nc, ti, i, j, k, na, ts, tc, gEnd, si, dfIdx: Integer;
  gmScan: Integer;   { -1 = the class body, >= 0 = a buffered method body }
  nDeclEdges: Integer;   { NSpec entries below this came from the CLASS BODY }
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
    if not IsConcreteTypeArgKind(CurTok.Kind) then
      Error('expected concrete type name');
    if nc >= MAX_TEMPLATE_PARAMS then Error('too many specialization arguments (MAX_TEMPLATE_PARAMS)');
    { GetTokenStr, not SVal: a builtin type spelled as a KEYWORD token carries an
      EMPTY SVal (see IsMethodNameTok's note), so every keyword-spelled argument
      recorded the same empty name — which is what the duplicate-specialization
      check below compares, so `TA = specialize TBox<Integer>` and a later
      `TA = specialize TBox<Double>` read as the same declaration. }
    if CurTok.SVal <> '' then cNames[nc] := CurTok.SVal
    else cNames[nc] := GetTokenStr(TokPos - 1);
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
    with args mapped through the substitution, that is not a type yet.

    Swept over the class body AND every buffered METHOD body of this template
    (gmScan = -1 is the class body, >= 0 each GenericMethods[] entry). Method
    bodies are buffered separately by BufferGenericMethod, so scanning only
    Templates[ti] missed any nested specialization that appears solely inside a
    method -- no prerequisite was registered, no alias declaration emitted,
    SpecializeStream's collapse found NestedSpecKnown false, and the literal
    word `specialize` survived into the stream: `undefined variable
    (specialize)`. That is rtl-generics' dominant comparer idiom, which lives in
    a class constructor body and nowhere else.
    bug-p-a-generic-class-method-call-is-undefined-inside-another-generics-body }
  { THE CLASS BODY FIRST, AND SEPARATELY -- the order is the classification.

    A `specialize X<..>` in the class body is a DECLARATION-TIME dependency:
    `TDel<T> = class(specialize TEq<T>)` cannot be declared before its parent
    exists. One in a METHOD BODY is a MATERIALISATION-TIME reference: it has to
    exist by the time that method is streamed, which is after this class is
    declared. Treating the second as the first manufactures a cycle out of a
    program that has none -- bug-p-mutually-referencing-generics-are-rejected-as-circular.

    The distinction needs no new state: the scans already run class body first,
    so the boundary is an index. Everything below nDeclEdges is
    declaration-time; everything at or above it is materialisation-time. }
  ScanRangeForNestedSpecs(Templates[ti].TokStart, Templates[ti].TokCount, specName);
  nDeclEdges := NSpecCount;

  for gmScan := 0 to GenericMethodCount - 1 do
  begin
    if GenericMethods[gmScan].TemplateIdx <> ti then Continue;
    ScanRangeForNestedSpecs(GenericMethods[gmScan].TokStart,
                            GenericMethods[gmScan].TokCount, specName);
  end;   { gmScan }

  { MODE DELPHI: the same sweep over this template's method impls that the
    parser HAS NOT REACHED YET.

    The rewrite emits its alias declaration right behind the template
    declaration, so ParseSpecialization runs while GenericMethodCount is still 0
    -- the method bodies exist as TOKENS (LexAll fills Tokens[] completely before
    parsing starts) but are not buffered, so the loop above has nothing to scan
    and reported nested=0 where objfpc reported nested=1. The literal word
    `specialize` then survived into the stream: `undefined variable (specialize)`.

    BOUNDED BY RECORDED FACT, WHICH IS THE WHOLE DIFFICULTY. The tempting
    version of this sweep -- walk raw Tokens[] for `specialize X<...>` whose
    arguments match this template's parameter names -- OVER-APPROXIMATES, because
    `T` and `U` are the commonest parameter names there are, so a nested
    specialization inside a DIFFERENT template's method matches just as well and
    would be registered under THIS substitution. That is a silently wrong
    specialization, strictly worse than the honest error it replaces. So the
    ranges come from GenMethImplSOff -- the class-name token offsets the Delphi
    rewrite RECORDED when it deleted a `<T>` from a method-impl header -- and a
    range is scanned only when that offset is a recorded header of THIS template.
    Attribution is by construction, never by argument shape.

    The copy is SCRATCH: TemplateTokenCount is restored, so no GenericMethods
    entry is created. That matters -- BufferGenericMethod maintains "each
    (method, specialization) pair is materialised exactly once" by a
    before/after split, and buffering here would make the parser's own later
    call the second buffering of the same body and emit it twice. }
  ScanDelphiMethodImplsForNestedSpecs(ti, specName);

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

  { MATERIALISATION-TIME ONLY: emit the prerequisites and DO NOT defer.

    Deferring would re-emit this declaration behind them, and on the re-parse the
    method-body reference is still undeclared -- it now sits AFTER this
    declaration in the stream -- so the scan finds it again, defers again, and
    the round counter eventually calls it a cycle. That is the false circularity:
    two specializations each waiting for the other to be declared first, when
    only one of them actually needs to be.

    So register THIS specialization now (fall through) and put the prerequisite
    declarations at TokPos, where they are parsed straight after it and well
    before FlushPendingClassSpecializations streams any method that needs them.
    A genuine cycle is unaffected: both its edges are declaration-time, so
    nDeclEdges > 0 on at least one side and the deferral path below still runs.
    test/test_generic_cycle_fail.pas is the control and must keep failing. }
  if (NSpecCount > 0) and (nDeclEdges = 0) then
  begin
    NSpecInsCnt := 0;
    for k := 0 to NSpecCount - 1 do
      EmitSpecDecl(NSpecName[k], NSpecTmpl[k], k * MAX_TEMPLATE_PARAMS, NSpecNArg[k]);
    InsertTokens(TokPos, NSpecIns, NSpecInsCnt);
    NSpecCount := 0;
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

{ One token past a generic method impl's terminating `end;`, given the token
  index its header starts at. Factored out of BufferGenericMethod because the
  mode-Delphi prerequisite scan needs the SAME range for a method the parser has
  not reached yet -- and a second, independently-written range finder is exactly
  the drift this file has been bitten by before. }
function GenericMethodBodyEnd(startTokIdx: Integer): Integer;
var depth, cur: Integer;
begin
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
  GenericMethodBodyEnd := cur;
end;

{ Copy Tokens[fromIdx .. toIdx-1] into the TemplateTokens arena, reporting the
  span. The arena is append-only, so a caller that does NOT want a permanent
  buffered method (the prerequisite scan) restores TemplateTokenCount afterwards
  and the copy is pure scratch. }
procedure AppendTokenRangeToTemplateArena(fromIdx, toIdx: Integer;
                                         var ts, tc: Integer);
var cur: Integer;
begin
  ts := TemplateTokenCount;
  tc := 0;
  for cur := fromIdx to toIdx - 1 do
  begin
    if TemplateTokenCount >= MAX_TEMPLATE_TOKENS then
      Error('generic template tokens overflow');
    TemplateTokens[TemplateTokenCount].Kind := Tokens[cur].Kind;
    TemplateTokens[TemplateTokenCount].IVal := Tokens[cur].IVal;
    TemplateTokens[TemplateTokenCount].Line := Tokens[cur].Line;
    TemplateTokens[TemplateTokenCount].SOffset := Tokens[cur].SOffset;
    TemplateTokens[TemplateTokenCount].SLen := Tokens[cur].SLen;
    Inc(TemplateTokenCount);
    tc := tc + 1;
  end;
end;

procedure BufferGenericMethod(ti, startTokIdx: Integer);
var
  finalCur: Integer;
  si, mStart, mCount: Integer;
begin
  finalCur := GenericMethodBodyEnd(startTokIdx);

  AppendTokenRangeToTemplateArena(startTokIdx, finalCur, mStart, mCount);

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

{ FPC lets a generic ROUTINE be specialized INLINE at the call site --
  `specialize MaxOf<Integer>(3, 9)` in an expression, `specialize Swp<Integer>(x, y)`
  as a statement -- as well as in the DECLARATION form ParseTopLevelSpecialize
  handles (`specialize MaxOf<Integer> as MaxIntF;`). Those are one
  specialization under two spellings, so this rewrites the inline spelling INTO
  the declaration one rather than growing a second specialization path:

    - every `specialize F<C>(` group still in the token stream collapses to the
      single identifier `F_C` — the very name the declaration form
      auto-generates when no `as` clause is given;
    - one declaration-form specialization is emitted per DISTINCT C, right here,
      immediately after F's template, which is exactly where a hand-written
      `specialize F<C> as F_C;` would have sat.

  Everything downstream then sees an ordinary call of an ordinary routine — no
  call site, overload rule or diagnostic has to learn about generics.

  The `(` in the pattern is load-bearing: it is what separates a CALL from the
  declaration form (`... > as Name;`), which must keep its own path, and from a
  bare `a < b` comparison that happens to sit beside the word.

  Called from ParseGenericFunc, so the scan sees the whole rest of the unit and
  a routine used before it is declared is refused as it always was.
  compat-pascal-inline-generic-specialization }
procedure SpecializeInlineGenericFuncUses(gfi: Integer);
const MAX_INLINE_SPECS = 64;
var i, k, nSpec: Integer;
    fname, cname, specName: AnsiString;
    seen: Boolean;
    specArgs: array[0..MAX_INLINE_SPECS-1] of AnsiString;
    specNames: array[0..MAX_INLINE_SPECS-1] of AnsiString;
    specKinds: array[0..MAX_INLINE_SPECS-1] of TTokenKind;
begin
  fname := GenericFuncs[gfi].Name;
  nSpec := 0;
  i := TokPos;
  while i + 5 < TokCount do
  begin
    if (Tokens[i].Kind = tkIdent) and CaseEqual(GetTokenStr(i), 'specialize') and
       (Tokens[i + 1].Kind = tkIdent) and CaseEqual(GetTokenStr(i + 1), fname) and
       (Tokens[i + 2].Kind = tkLt) and
       IsConcreteTypeArgKind(Tokens[i + 3].Kind) and
       (Tokens[i + 4].Kind = tkGt) and (Tokens[i + 5].Kind = tkLParen) then
    begin
      cname := GetTokenStr(i + 3);
      specName := fname + '_' + cname;
      seen := False;
      for k := 0 to nSpec - 1 do
        if CaseEqual(specNames[k], specName) then seen := True;
      if not seen then
      begin
        if nSpec >= MAX_INLINE_SPECS then
          Error('too many inline specializations of ' + fname);
        specArgs[nSpec] := cname;
        specNames[nSpec] := specName;
        specKinds[nSpec] := Tokens[i + 3].Kind;
        Inc(nSpec);
      end;
      { collapse `specialize F < C >` to the one identifier F_C }
      Tokens[i].Kind := tkIdent;
      Tokens[i].IVal := 0;
      Tokens[i].SOffset := TokCharsAppend(specName);
      Tokens[i].SLen := Length(specName);
      RemoveTokens(i + 1, 4);
    end;
    Inc(i);
  end;

  for k := 0 to nSpec - 1 do
  begin
    { A name already taken means the DECLARATION form got here first (its
      auto-generated name is the same one) — one specialization is what we
      want, so leave that one alone. }
    if FindProc(specNames[k]) >= 0 then Continue;
    SpecializeTemplateName := GenericFuncs[gfi].Name;
    { generic FUNCTIONS stay single-parameter — load the substitution directly }
    SpecSubCount := 1;
    SpecSubNames[0]  := GenericFuncs[gfi].Param;
    SpecSubValues[0] := specArgs[k];
    SpecSubKinds[0]  := specKinds[k];
    { SpecializeStream splices at TokPos, and CurTok is holding the token AT
      TokPos-1 — so step back, splice in front of it, and the `Next` below reads
      the first spliced token. When ParseSubroutine finishes, CurTok is back on
      the token it was holding, which is what the caller expects. }
    Dec(TokPos);
    SpecializeStream(GenericFuncs[gfi].TokStart, GenericFuncs[gfi].TokCount,
                     specNames[k]);
    Next;
    ParseSubroutine;
  end;
end;

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
  SpecializeInlineGenericFuncUses(gfi);
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
