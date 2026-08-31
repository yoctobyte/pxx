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

{ ---- HOISTING a template's own nested types --------------------------------

  `TDict<TKey,TVal>` declaring `type TPair = record K: TKey; V: TVal; end;` and
  then using `specialize TEnum<TPair>` inside its own body. `TPair` names
  something that exists only inside a specialization of TDict, so the group
  cannot be minted concretely -- that half is fixed, and the group is correctly
  deferred to the nested-prerequisite path. The prerequisite is then emitted at
  the TOP LEVEL as `TEnum$TPair = specialize TEnum<TPair>`, where `TPair` does
  not exist.

  ROUTE, chosen after hand-compiling both desugarings rather than reasoning about
  them. The obvious repair -- name it in qualified form,
  `specialize TEnum<TDict$Integer$LongInt.TPair>` -- is IMPOSSIBLE, and not
  because pxx cannot parse it (it can, since
  bug-p-a-qualified-type-name-cannot-be-a-generic-argument). It needs three
  declarations in a cycle: the alias needs the specialized class declared, that
  class body names the TEnum prerequisite, and the prerequisite needs the alias.
  FPC rejects the hand-written desugaring too, so there is no order to find.

  So HOIST instead. The nested type is lifted to its own top-level declaration
  with the substitution applied, and the declaration left behind in the class body
  becomes an ALIAS to it:

    TDict$I$L$TPair = record K: Integer; V: LongInt; end;
    TEnum$TDict$I$L$TPair = specialize TEnum<TDict$I$L$TPair>;
    TDict$I$L = class
    type TPair = TDict$I$L$TPair;              <- alias, NOT a second copy
      ...
    end;

  Each line names only what precedes it.

  AN ALIAS AND NOT A COPY, which is the load-bearing half. Emitting a top-level
  duplicate of the record and leaving the in-class declaration alone is easier and
  is wrong: the two would be structurally identical but DISTINCT types, so `d.P`
  would have one and the specialization's result the other, and assigning between
  them fails. That is a silent-shaped defect, so the rewrite of the in-body
  declaration is the part to get right.

  ONLY WHAT IS ACTUALLY USED AS A GENERIC ARGUMENT IS HOISTED. Hoisting every
  nested type of every specialization would rewrite programs that work today --
  test_generic_nested_type_identity and test_generic_nested_type_field_name are
  both nested-type programs with no generic-argument use in sight -- so the
  trigger is the argument, not the declaration. A template with nested types and
  no such use produces byte-identical output to before. }

const MAX_HOISTED_NESTED = 32;
var
  { in-body name, e.g. TPair }
  HoistName  : array[0..MAX_HOISTED_NESTED-1] of AnsiString;
  { the top-level name it is lifted to, e.g. TDict$Integer$LongInt$TPair }
  HoistFull  : array[0..MAX_HOISTED_NESTED-1] of AnsiString;
  { ABSOLUTE TemplateTokens indices of the declaration RHS, both inclusive }
  HoistStart : array[0..MAX_HOISTED_NESTED-1] of Integer;
  HoistEnd   : array[0..MAX_HOISTED_NESTED-1] of Integer;
  { set when some generic argument in the body actually named it }
  HoistUsed  : array[0..MAX_HOISTED_NESTED-1] of Boolean;
  HoistCount : Integer;
  { False while the hoisted RHS is itself being substituted, so the replacement
    hook below does not eat its own body }
  HoistActive: Boolean;
  { Every hoisted declaration ALREADY emitted, for the whole compilation.

    Without this the fix does not terminate. Emitting the hoists takes the
    DEFERRAL path, which re-emits `TE = specialize TDict<...>` behind them; the
    re-parse runs CollectHoistCandidates again, NestedSpecArg marks the same
    candidate used again, and it defers again -- redeclaring the hoisted type
    every round until the deferral counter calls it a cycle. The re-parse must
    still SEE the candidate as used, because the class body streaming needs it to
    collapse the in-body RHS to an alias; what it must not do is emit it twice.
    So "used" and "still to emit" are separate questions, and this answers the
    second. }
  HoistEmitted     : array[0..MAX_HOISTED_NESTED*8-1] of AnsiString;
  HoistEmittedCount: Integer;

{ Has this hoisted declaration already been written into the stream? }
function HoistAlreadyEmitted(const nm: AnsiString): Boolean;
var k: Integer;
begin
  HoistAlreadyEmitted := False;
  for k := 0 to HoistEmittedCount - 1 do
    if CaseEqual(HoistEmitted[k], nm) then HoistAlreadyEmitted := True;
end;

{ The hoisted name for an in-body nested type, or '' when the name is not one.
  Marks it used, which is what makes it hoisted at all. }
function HoistedNameFor(const nm: AnsiString): AnsiString;
var k: Integer;
begin
  HoistedNameFor := '';
  for k := 0 to HoistCount - 1 do
    if CaseEqual(HoistName[k], nm) then
    begin
      HoistUsed[k] := True;
      HoistedNameFor := HoistFull[k];
      Exit;
    end;
end;

{ Does TemplateTokens[ts + i] open a `specialize NAME<...>` group naming a
  template we know? Returns the offset of the closing `>`, or -1. A binder
  (`X = specialize ...`, a nested type declaration) is ParseSpecialization's
  own business and is skipped. }
function SelfSpecGroupEnd(ts, i, count: Integer): Integer;
{ `i` indexes an occurrence of the template's OWN name inside its own body. If
  what follows is `<` naming this template's own type parameters, in order,
  closed by `>`, return the index of that `>`; otherwise -1.

  `TOuter<T>` written inside `TOuter<T>`'s body means THIS specialization, whose
  name is `specName` — so once the name has been rewritten to `TOuter$LongInt`
  the argument list is not merely redundant, it is wrong: it survives into the
  output and its `T` is then substituted by the ordinary parameter pass, giving
  `TOuter$LongInt<LongInt>`, which is not a type. NestedSpecGroup would have
  collapsed the whole group, but it requires the literal `specialize` keyword
  and mode-delphi code does not write one, so in mode delphi nothing consumed
  the group and both rewrites ran. bug-p-a-nested-class-naming-its-enclosing-
  template-is-substituted-twice — where the name says "nested class" and the
  measurement says nesting is irrelevant: a plain self-referential field
  (`FNext: TOuter<T>`, the linked-list idiom) fails identically.

  Matching the parameter names IN ORDER is what keeps this from eating a
  reference to a DIFFERENT specialization of the same template: `TOuter<Integer>`
  inside `TOuter<T>`'s body is a nested specialization and must keep its group. }
var j, k: Integer;
begin
  Result := -1;
  if SpecSubCount <= 0 then Exit;
  if TemplateTokens[ts + i + 1].Kind <> tkLt then Exit;
  j := i + 2;
  for k := 0 to SpecSubCount - 1 do
  begin
    if j >= count then Exit;
    if TemplateTokens[ts + j].Kind <> tkIdent then Exit;
    if not CaseEqual(GetTokenStrFromRaw(TemplateTokens[ts + j].SOffset,
                                        TemplateTokens[ts + j].SLen),
                     SpecSubNames[k]) then Exit;
    Inc(j);
    if k < SpecSubCount - 1 then
    begin
      if (j >= count) or (TemplateTokens[ts + j].Kind <> tkComma) then Exit;
      Inc(j);
    end;
  end;
  if (j >= count) or (TemplateTokens[ts + j].Kind <> tkGt) then Exit;
  Result := j;
end;

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
var k: Integer; nm, hn: AnsiString;
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
      Exit;
    end;
  { ...and a name the template declares in its OWN body becomes the top-level
    name that body's declaration is hoisted to. Second mapping, same reason as
    the first: the argument means something only inside a specialization, and a
    prerequisite is emitted OUTSIDE one. See the hoisting note. }
  hn := HoistedNameFor(nm);
  if hn <> '' then
  begin
    t.Kind := tkIdent;
    t.SOffset := TokCharsAppend(hn);
    t.SLen := Length(hn);
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
  implementation.

  THE ARENA HOLDS TWO KINDS OF REGION and this must answer for both. A captured
  template is covered by Templates[i].TokStart/TokCount; a generic METHOD BODY
  buffered by BufferGenericMethod is appended to the same arena but is covered
  only by GenericMethods[i].TokStart/TokCount — Templates[].TokCount stops
  growing when the template's own capture ends and never takes the bodies in.
  Scanning only the first table therefore returned -1 for every method body,
  PasSpliceTokFile took its `srcKeyId < 0` early exit, and the pasted region
  silently inherited the DESTINATION file's provenance: the tokens kept the
  template's `.Line` (it rides on the token) under the instantiating unit's name
  (it rides on the index).

  That is why the defect looked shape-dependent rather than total. Splice the
  bodies where ParseSpecialization does — just after the class declaration, still
  inside the region that splice attributed to the template — and inheriting the
  destination is inheriting the right answer, by luck. Splice them anywhere else
  (FlushPendingClassSpecializations puts them past `implementation`) and the
  luck runs out. One arm being accidentally correct is what kept this alive.
  bug-p-a-specialized-body-reports-errors-in-the-wrong-file }
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
  { a buffered method body carries its owning TEMPLATE's file, which is where its
    tokens were read from -- not the unit that specializes it.

    GenericFuncs[] is a THIRD kind of region in this same arena and has the same
    gap, deliberately not covered here: a generic FUNCTION cannot be declared in
    a unit interface at all today (`unexpected token in a unit interface section`),
    so its body never crosses a file boundary, and inheriting the destination is
    always inheriting the right file. There is no reachable wrong output to fix,
    and GenericFuncs has no source-key field to answer with. Whoever makes
    `generic function` work in an interface must add the third scan with it. }
  for i := 0 to GenericMethodCount - 1 do
    if (t >= GenericMethods[i].TokStart) and
       (t < GenericMethods[i].TokStart + GenericMethods[i].TokCount) and
       (GenericMethods[i].TemplateIdx >= 0) and
       (GenericMethods[i].TemplateIdx < TemplateCount) then
    begin
      TemplateSrcKeyOfTok := TemplateSrcKey[GenericMethods[i].TemplateIdx];
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

{ The SUBSTITUTION half of SpecializeStream, ending at a filled
  SpecializeTokens[0..Result-1] and touching Tokens[] not at all.

  Split out because a hoisted nested type needs the same substituted token run
  put somewhere ELSE -- into a prerequisite declaration emitted ahead of the
  specialization, rather than spliced at the cursor. The buffer was always
  there; only the splice was welded to it.
  bug-p-a-nested-type-of-the-enclosing-template-is-minted-as-a-concrete-generic-argument }
function SpecializeToBuffer(tokStart, count: Integer; const specName: AnsiString): Integer;
{ Substitutions come from the SpecSub* globals (param name -> concrete
  name/kind), set by the caller — multi-param generics replace every type
  parameter in one pass. }
var
  i, j, k: Integer;
  subCount: Integer;
  gEnd, hoistHit, gSelf: Integer;
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
    { A hoisted nested type's RHS collapses to the single identifier of the
      top-level declaration it was lifted to, turning `TPair = record ... end`
      into `TPair = TDict$Integer$LongInt$TPair`. An ALIAS, so the in-class name
      and the hoisted name are ONE type -- a second copy would be structurally
      identical and distinct, and assigning between them would fail. Guarded by
      HoistActive so that substituting the hoisted RHS itself does not collapse
      it into a reference to the declaration being written. }
    if HoistActive then
    begin
      hoistHit := -1;
      for k := 0 to HoistCount - 1 do
        if HoistUsed[k] and (tokStart + i = HoistStart[k]) then hoistHit := k;
      if hoistHit >= 0 then
      begin
        SpecializeTokens[subCount].Kind := tkIdent;
        SpecializeTokens[subCount].IVal := 0;
        SpecializeTokens[subCount].Line := TemplateTokens[tokStart + i].Line;
        SpecializeTokens[subCount].SOffset := TokCharsAppend(HoistFull[hoistHit]);
        SpecializeTokens[subCount].SLen := Length(HoistFull[hoistHit]);
        Inc(subCount);
        i := HoistEnd[hoistHit] - tokStart + 1;
        Continue;
      end;
    end;

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
        { ...and drop a `<T>` that merely re-spells this same specialization.
          specName already carries the arguments, so leaving the group behind
          emits `TOuter$LongInt<LongInt>`. The loop tail's Inc(i) lands just
          past the `>`. }
        gSelf := SelfSpecGroupEnd(tokStart, i, count);
        if gSelf >= 0 then i := gSelf;
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
  SpecializeToBuffer := subCount;
end;

{ Substitute one template range and SPLICE it at the parse cursor. }
function SpecializeStreamAt(tokStart, count: Integer; const specName: AnsiString;
                            at: Integer): Integer;
{ The splice, at an EXPLICIT index rather than at the parse cursor, returning how
  many tokens it inserted so a caller placing several in a row can advance its own
  anchor. SpecializeStream below is this with `at` = TokPos, which is what every
  caller but the unit-interface deferral wants. }
var i, subCount: Integer;
begin
  subCount := SpecializeToBuffer(tokStart, count, specName);
  EnsureTokCapacity(TokCount + subCount + 1);
  i := TokCount - 1;
  while i >= at do
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
    Tokens[at + i].Kind := SpecializeTokens[i].Kind;
    Tokens[at + i].IVal := SpecializeTokens[i].IVal;
    Tokens[at + i].Line := SpecializeTokens[i].Line;
    Tokens[at + i].SOffset := SpecializeTokens[i].SOffset;
    Tokens[at + i].SLen := SpecializeTokens[i].SLen;
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
  AdjustSrcRanges(at, subCount);
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
  PasSpliceTokFile(at, subCount, TemplateSrcKeyOfTok(tokStart));
  SpecializeStreamAt := subCount;
end;

procedure SpecializeStream(tokStart, count: Integer; const specName: AnsiString);
{ Splice at the parse cursor: the parser reads the inserted tokens next. }
var n: Integer;
begin
  n := SpecializeStreamAt(tokStart, count, specName, TokPos);
  if n < 0 then Error('specialize splice');   { n is used; keeps the FPC seed quiet }
end;

procedure ParseGenericTemplateNamed(const templateNameIn: AnsiString; delphiForm: Boolean); forward;
function OrdinalNameToTk(const nm: AnsiString): TTypeKind; forward;
function BuiltinTypeNameTk(const nm: AnsiString): TTypeKind; forward;   { body in pasparser_lval.inc, which also CALLS it above the body (the type-helper type-name receiver). pxx pre-scans and does not need this; FPC does. }
function QualArgAliasName(const path: AnsiString): AnsiString; forward;
procedure EmitQualAliasDecl(const aliasNm, path: AnsiString); forward;   { both bodies live below their first CALL (the qualified-type-name-as-generic-argument arms). pxx resolves across the unit; FPC resolves in source order and the seed build fails without these. }

{ Every name whose meaning DEPENDS ON A SPECIALIZATION, read straight out of
  Tokens[] rather than out of Templates[]. Two kinds, one concept:

    - a template's PARAMETER names          -- `TDict<TKey, TValue>`
    - the type names its BODY declares      -- `TDict<..> = class type TPair = ..`

  Both are meaningless until the template that owns them is specialized, and a
  generic argument spelled with either must go down the deferred / nested-
  prerequisite path instead of being minted into a concrete alias. They are
  collected by ONE procedure on purpose: the parameter case was fixed first and
  the nested-type case walked straight through it, which is the two-mechanisms-
  for-one-concept smell from root-cause-over-microfix.md.
  bug-p-a-nested-type-of-the-enclosing-template-is-minted-as-a-concrete-generic-argument

  Why it cannot come from Templates[]: the sweep for template ti runs the moment
  ti is DECLARED, and a use of ti inside a LATER template's body carries that
  later template's parameters and nested types. `TCmp<TKey>` written in `TDict<TKey, TValue>`'s
  body is swept while TDict does not exist yet, so TKey is nobody's registered
  parameter, the group reads as concrete, and `TCmp$TKey` is minted -- a class
  whose streamed body says `Val: TKey` and reports `unknown type: TKey` from
  TCmp's own line, which the user did not ask to be specialized.
  bug-p-a-generic-argument-that-is-another-templates-parameter-is-minted-as-a-concrete-type

  The enabling fact is the one wall 6 used: LexAll fills Tokens[] COMPLETELY
  before the parser starts, so the later template's header is already there as
  tokens. It is unparsed, not unavailable.

  A header is `Name < ... > =` -- the `=` is what separates it from a USE, which
  is followed by `;`, `)`, `.` or a type opener, never by `=`. (`a < b >= c`
  lexes `>=` as tkGe, so a comparison cannot spell this shape.) Constraints are
  skipped: in `<T: TObject; U>` only T and U are parameter names.

  A REJECTED alternative, recorded because it looks like the tidier answer: flip
  the test to a whitelist -- mint only what is CONCRETE at sweep time (a builtin,
  or a type already declared). It is wrong for the reason this whole ticket is
  about. "Concrete" and "already parsed" are not the same property, and a
  whitelist conflates them: a perfectly concrete top-level type declared AFTER
  the template would fail the test and be deferred, with nothing to re-trigger
  the sweep. That is the parse-order dependence this collector exists to remove,
  reintroduced from the other side.

  Deliberately UNSCOPED -- it is every such name in the file, not just the ones
  in scope at the use. That over-approximates toward "defer to the nested
  path", which yields an honest error rather than a wrong class, and is the
  opposite of the direction wall 6's ticket warns about
  (`do not weaken the prerequisite scan`). The cost is a real type that happens
  to share a name with somebody's type parameter; the benefit is that the check
  does not depend on parse order, which is the whole defect. }
const MAX_SPEC_BOUND_NAMES = 512;
var
  SpecBoundNameOff : array[0..MAX_SPEC_BOUND_NAMES-1] of Integer;
  SpecBoundNameLen : array[0..MAX_SPEC_BOUND_NAMES-1] of Integer;
  SpecBoundNameCount : Integer;

{ Harvest the type names declared INSIDE one template's body, and report where
  that body ends so the caller can resume past it. `afterEq` is the token just
  after the header's `=`.

  Body extent by depth, not by a second parser: `class` / `record` / `object` /
  `interface` / `case` open, `end` closes. `class` opens only when it is not
  `class function|procedure|var|operator|of` -- the modifier spelling, which is
  everywhere in a real class body. A header with no body at all (`= class;` or
  an alias `= TBar<T>;`) simply runs to its `;`.

  Inside the extent, a name is declared when a `type` section is open and an
  identifier is followed by `=`. The section state is what keeps
  `procedure P(a: Integer = 0)` from registering `Integer` as a nested type --
  the `procedure` closes the section before the default value is reached, and
  registering `Integer` would have deferred every `TBox<Integer>` in the file.
  `public type PT = ^T;` works because the visibility keyword precedes `type`.

  Not shared with GenericMethodBodyEnd: that one matches begin/case/end over a
  STATEMENT body, which is a different grammar with a different opener set. }
{ A `class` token met while COUNTING BODY DEPTH: does it open a body that an
  `end` will close?

  Three answers, and the two hand-rolled copies of this decision each got a
  DIFFERENT two of them right, which is why it is one function now
  (devdocs/dev/normalise-dont-special-case.md):

    Result = True                   -- a real body; the caller counts it.
    Result = False, bodilessEnd < 0 -- a MEMBER PREFIX: `class function`,
                                       `class procedure`, `class var`,
                                       `class const`, `class property`,
                                       `class of`, and the soft-keyword
                                       `class constructor/destructor/operator`.
                                       Nothing to skip.
    Result = False, bodilessEnd >= 0 -- a BODILESS DECLARATION that closes on
                                       its own semicolon, whose index this is.
                                       All four spellings: `class;`,
                                       `class(TBase);`, `class abstract(TBase);`,
                                       `class sealed(TBase);`.

  A THIRD copy of the question sits just above the template capture's depth loop
  and is deliberately NOT routed here: it asks whether the WHOLE declaration is
  bodyless starting from the `=`, and it answers for `interface` and for
  `class of T;` as well, which are not this function's subject.

  Getting the bodiless arm wrong at a NESTED level is what walled the
  rtl-generics corpus. `TEnumerator = class(TCustomListEnumerator<T>);` inside
  TList's own `type` section left depth one too high, so TList's `end` closed
  the wrong level and the capture ran on for 10,914 tokens (every other template
  in that corpus captures at most 1,677). It swallowed TCustomDictionary, whose
  `FEqualityComparer: IEqualityComparer<TKey>` was then registered as a nested
  prerequisite OF TList, under TList's substitution set -- where `TKey` is not a
  parameter, so it stayed literal and was minted as the alias
  `IEqualityComparer$TKey`, and `unknown type: TKey` was raised inside the
  specialized body in generics.defaults.pas.
  bug-p-the-rtl-generics-corpus-stops-on-tkey-in-a-tlist-body }
function ClassTokOpensBody(at: Integer; var bodilessEnd: Integer): Boolean;
var k, pdepth: Integer;
begin
  bodilessEnd := -1;
  ClassTokOpensBody := True;
  if at + 1 >= TokCount then Exit;
  if (Tokens[at + 1].Kind = tkFunction) or (Tokens[at + 1].Kind = tkProcedure) or
     (Tokens[at + 1].Kind = tkVar) or (Tokens[at + 1].Kind = tkConst) or
     (Tokens[at + 1].Kind = tkProperty) or (Tokens[at + 1].Kind = tkOf) then
  begin
    ClassTokOpensBody := False;
    Exit;
  end;
  if (Tokens[at + 1].Kind = tkIdent) and
     (CaseEqual(GetTokenStr(at + 1), 'operator') or
      CaseEqual(GetTokenStr(at + 1), 'constructor') or
      CaseEqual(GetTokenStr(at + 1), 'destructor')) then
  begin
    ClassTokOpensBody := False;
    Exit;
  end;
  k := at + 1;
  while (k < TokCount) and (Tokens[k].Kind = tkIdent) and
        (CaseEqual(GetTokenStr(k), 'abstract') or
         CaseEqual(GetTokenStr(k), 'sealed')) do Inc(k);
  if (k < TokCount) and (Tokens[k].Kind = tkLParen) then
  begin
    pdepth := 0;
    while k < TokCount do
    begin
      if Tokens[k].Kind = tkLParen then Inc(pdepth)
      else if Tokens[k].Kind = tkRParen then
      begin
        Dec(pdepth);
        if pdepth <= 0 then begin Inc(k); Break; end;
      end;
      Inc(k);
    end;
  end;
  if (k < TokCount) and (Tokens[k].Kind = tkSemicolon) then
  begin
    bodilessEnd := k;
    ClassTokOpensBody := False;
  end;
end;

procedure CollectNestedTypeNames(afterEq: Integer; var resumeAt: Integer);
var j, depth, bEnd: Integer;
    inTypeSec: Boolean;
begin
  j := afterEq;
  { `packed record`, `bitpacked record` }
  while (j < TokCount) and (Tokens[j].Kind = tkIdent) and
        (CaseEqual(GetTokenStr(j), 'packed') or CaseEqual(GetTokenStr(j), 'bitpacked')) do
    Inc(j);
  if j >= TokCount then begin resumeAt := TokCount; Exit; end;

  if (Tokens[j].Kind = tkClass) or (Tokens[j].Kind = tkRecord) or
     ((Tokens[j].Kind = tkIdent) and
      (CaseEqual(GetTokenStr(j), 'interface') or CaseEqual(GetTokenStr(j), 'object'))) then
  begin
    depth := 0;
    inTypeSec := False;
    while j < TokCount do
    begin
      if Tokens[j].Kind = tkEnd then
      begin
        Dec(depth);
        if depth <= 0 then begin resumeAt := j; Exit; end;
      end
      else if (Tokens[j].Kind = tkRecord) or (Tokens[j].Kind = tkCase) then
        Inc(depth)
      else if (Tokens[j].Kind = tkIdent) and
              (CaseEqual(GetTokenStr(j), 'interface') or CaseEqual(GetTokenStr(j), 'object')) then
        Inc(depth)
      else if Tokens[j].Kind = tkClass then
      begin
        { `= class;` / `= class(TBase);` / `= class abstract(TBase);` opens NO
          body, so it must not touch depth -- at ANY nesting level. Handling
          only the outermost one was one arm of this bug: rtl-generics nests
          `TEnumerator = class(TCustomListEnumerator<T>);` inside TList's own
          `type` section, which inflated depth by one and made TList's `end`
          close the wrong level. The decision itself now lives in exactly one
          place; see ClassTokOpensBody, and the bug it cost:
          bug-p-a-bodiless-class-with-a-parent-swallows-the-rest-of-the-type-section }
        if ClassTokOpensBody(j, bEnd) then
          Inc(depth)
        else if bEnd >= 0 then
        begin
          if depth = 0 then begin resumeAt := bEnd; Exit; end;
          j := bEnd;
        end;
      end
      else if Tokens[j].Kind = tkType then inTypeSec := True
      else if (Tokens[j].Kind = tkVar) or (Tokens[j].Kind = tkConst) or
              (Tokens[j].Kind = tkProcedure) or (Tokens[j].Kind = tkFunction) or
              (Tokens[j].Kind = tkProperty) then inTypeSec := False
      else if (Tokens[j].Kind = tkIdent) and
              (CaseEqual(GetTokenStr(j), 'constructor') or
               CaseEqual(GetTokenStr(j), 'destructor')) then inTypeSec := False
      else if inTypeSec and (Tokens[j].Kind = tkIdent) and
              (j + 1 < TokCount) and (Tokens[j + 1].Kind = tkEq) then
      begin
        if SpecBoundNameCount < MAX_SPEC_BOUND_NAMES then
        begin
          SpecBoundNameOff[SpecBoundNameCount] := Tokens[j].SOffset;
          SpecBoundNameLen[SpecBoundNameCount] := Tokens[j].SLen;
          Inc(SpecBoundNameCount);
        end;
      end;
      Inc(j);
    end;
    { Ran off the end without depth returning to 0. resumeAt := TokCount makes
      the CALLER's scan jump to the end of the stream, silently abandoning every
      declaration after this one. }
    if PxxDbgEnabled('p.specbound') then
      writeln('PXXDBG p.specbound RUNAWAY from tok=', afterEq,
              ' depth=', depth, ' -- rest of stream (', TokCount - afterEq,
              ' tokens) NOT scanned');
    resumeAt := TokCount;
  end
  else
  begin
    { an alias header -- no body, nothing nested to declare }
    while (j < TokCount) and (Tokens[j].Kind <> tkSemicolon) do Inc(j);
    resumeAt := j;
  end;
end;

procedure CollectSpecializationBoundNamesFromTokens;
var i, j, savedCount: Integer;
    ok, wantName: Boolean;
    dbgI: Integer;
    dbgArg: AnsiString;
begin
  SpecBoundNameCount := 0;
  i := 0;
  while i + 2 < TokCount do
  begin
    if (Tokens[i].Kind = tkIdent) and (Tokens[i + 1].Kind = tkLt) then
    begin
      { walk the group, collecting the names that start each entry. Collected
        speculatively and rolled back below if the group turns out to be a USE
        -- which is why savedCount exists rather than a two-pass scan. }
      savedCount := SpecBoundNameCount;
      j := i + 2;
      ok := True;
      wantName := True;
      while ok and (j < TokCount) and (Tokens[j].Kind <> tkGt) do
      begin
        if Tokens[j].Kind = tkIdent then
        begin
          if wantName then
          begin
            if SpecBoundNameCount < MAX_SPEC_BOUND_NAMES then
            begin
              SpecBoundNameOff[SpecBoundNameCount] := Tokens[j].SOffset;
              SpecBoundNameLen[SpecBoundNameCount] := Tokens[j].SLen;
              Inc(SpecBoundNameCount);
            end;
            wantName := False;
          end;
          Inc(j);
        end
        else if Tokens[j].Kind = tkComma then begin wantName := True; Inc(j); end
        else if Tokens[j].Kind = tkSemicolon then begin wantName := True; Inc(j); end
        else if Tokens[j].Kind = tkColon then
        begin
          { a constraint list runs to the next `;` or `>` and names no parameter }
          Inc(j);
          while (j < TokCount) and (Tokens[j].Kind <> tkSemicolon) and
                (Tokens[j].Kind <> tkGt) do Inc(j);
        end
        else ok := False;
      end;
      { A HEADER is followed by `=` -- but so are several USES, so the `=` alone
        is not enough and treating it as enough is
        regression-test-pascal-conformance-shard0-6-2:

            const P: ^specialize TTest<LongInt> = Nil;

        is `Ident < Ident > =`, so `LongInt` was harvested as though it were a
        template PARAMETER name. Every later specialization spelled with that
        name then looked like a param form and was left un-rewritten. It bit
        only the type names that lex as tkIdent -- longint, cardinal, int64,
        qword, smallint, word, shortint and every user alias -- because the walk
        below only records tkIdent. Exactly ten spellings get a dedicated kind
        in lexer.inc (boolean byte char double extended integer longword real
        single string -- ten spellings over nine kinds, `byte` shares
        tkInteger_T), and those can never be harvested. That is why the failure
        looked like it cared which type it was: the failing set and the passing
        set are two disjoint lists of NAMES.

        A declaration's left-hand side can only follow the `type` keyword, the
        `;` that ended the previous declaration, or -- in objfpc mode -- the
        `generic` keyword that introduces it. Test for those, rather than trying
        to enumerate the ways a use can be spelled.

        THE `generic` ARM IS NOT OPTIONAL AND ITS ABSENCE WAS A REGRESSION.
        The first version of this whitelist listed only `type` and `;`, in a
        comment that asserted those were the only two. That is true of the
        Delphi surface (`TDict<TKey, TValue> = class`) and false of objfpc
        (`generic TDict<TKey, TValue> = class`), where the name is preceded by
        `generic` and nothing else. Every objfpc header therefore failed the
        test, its parameters were never harvested, and a use of one of them as
        an argument -- `C: specialize TCmp<TKey>` -- was minted as a CONCRETE
        specialization instead of being deferred, so the template's own `Val: T`
        came back as `unknown type: TKey`.
        regression-test-core-test-generic-arg-is-enclosing-template-param-objfpc.
        `generic` carries no dedicated token kind; it lexes as tkIdent. }
      if ok and (j + 1 < TokCount) and (Tokens[j].Kind = tkGt) and
         (Tokens[j + 1].Kind = tkEq) and
         ((i = 0) or (Tokens[i-1].Kind = tkType) or
          (Tokens[i-1].Kind = tkSemicolon) or
          ((Tokens[i-1].Kind = tkIdent) and
           CaseEqual(GetTokenStr(i-1), 'generic'))) then
      begin
        { a header -- keep the parameter names, then harvest the names its BODY
          declares, and resume past the whole declaration }
        savedCount := i;
        CollectNestedTypeNames(j + 2, i);
        if PxxDbgEnabled('p.specbound') and (i > savedCount + 1) then
          writeln('PXXDBG p.specbound JUMP ', savedCount, ' -> ', i,
                  ' (skipped ', i - savedCount, ' tokens) header=', GetTokenStr(savedCount));
      end
      else
        SpecBoundNameCount := savedCount;   { a use, or malformed -- forget them }
    end;
    Inc(i);
  end;
  { The cap is silent: past MAX_SPEC_BOUND_NAMES a real type-parameter name is
    simply not recorded, and the only symptom is a specialization later taking
    the alias path instead of the deferred one -- i.e. an alias minted into the
    TEMPLATE's unit naming a parameter that does not exist there. Report the
    occupancy so a near-miss is visible before it becomes a wall. }
  if PxxDbgEnabled('p.specbound') then
  begin
    writeln('PXXDBG p.specbound names=', SpecBoundNameCount,
            ' cap=', MAX_SPEC_BOUND_NAMES,
            ' overflow=', Ord(SpecBoundNameCount >= MAX_SPEC_BOUND_NAMES),
            ' tokcount=', TokCount);
  end;
  { ...and WHICH names, because the count answers the wrong half of the question.
    An occupancy of 294/512 says the table did not overflow; it does not say the
    name you care about is IN it, and a name that was never collected and a name
    that was collected but not consulted produce the identical symptom -- a
    specialization taking the alias path instead of the deferred one. Two
    mechanisms, one wall, and the count cannot separate them.
    `PXXDBG=p.specbound:names` to list, `:<Name>` to ask about one. }
  if PxxDbgArg('p.specbound') <> '' then
  begin
    dbgArg := PxxDbgArg('p.specbound');
    for dbgI := 0 to SpecBoundNameCount - 1 do
      if (dbgArg = 'names') or
         CaseEqual(dbgArg, GetTokenStrFromRaw(SpecBoundNameOff[dbgI],
                                              SpecBoundNameLen[dbgI])) then
        writeln('PXXDBG p.specbound   [', dbgI, '] ',
                GetTokenStrFromRaw(SpecBoundNameOff[dbgI], SpecBoundNameLen[dbgI]));
  end;
end;

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
  ok, isParamForm, specB, dgDbg: Boolean;
  mintFlt: AnsiString;   { PXXDBG p.mint filter, see DbgMintTrace }
  si: Integer;
  { qualified arguments minted by THIS rewrite, emitted at insertAt below.
    Local, not the QNeed* set ParseSpecialization uses: this runs at rewrite
    time and that runs later, and sharing one pending list would let whichever
    ran second clear the other's. }
  dgQName: array[0..MAX_DGEN_TUPLES-1] of AnsiString;
  dgQPath: array[0..MAX_DGEN_TUPLES-1] of AnsiString;
  dgQCount: Integer;
  qPath, qMint: AnsiString;
begin
  dgQCount := 0;
  tname := Templates[ti].Name;
  np := TemplateNParams[ti];
  seenCnt := 0;
  i := insertAt;
  { `PXXDBG=p.dgen:<TemplateName>` — one template's whole sweep. The sweep is
    FORWARD-ONLY from insertAt, so a use of this template that sits EARLIER in
    the token stream than the sweep start is never seen at all, and the symptom
    of that is identical to the symptom of a use that was seen and classified as
    concrete: an alias minted with a name that is really a parameter. Printing
    the sweep window is the only way to tell the two apart, so print it. }
  dgDbg := CaseEqual(PxxDbgArg('p.dgen'), tname);
  mintFlt := PxxDbgArg('p.mint');
  if dgDbg then
    writeln('PXXDBG p.dgen sweep ', tname, ' ti=', ti, ' from=', insertAt,
            ' tokcount=', TokCount, ' delphiPattern=', Ord(delphiPattern),
            ' np=', np);
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
          { A QUALIFIED argument -- `TBox<TOuter.TPair>` -- is normalised to the
            same minted single identifier the objfpc arm uses, and its alias
            declaration is emitted at insertAt below, ahead of the tuple
            declarations that name it. Without this the group simply failed to
            match, the rewrite left it alone, and the parser reported `unknown
            type: TBox`.
            bug-p-a-qualified-type-name-cannot-be-a-generic-argument }
          if (Tokens[j].Kind = tkIdent) and (j + 1 < TokCount) and
             (Tokens[j + 1].Kind = tkDot) then
          begin
            qPath := GetTokenStr(j);
            while (j + 2 < TokCount) and (Tokens[j + 1].Kind = tkDot) and
                  (Tokens[j + 2].Kind = tkIdent) do
            begin
              qPath := qPath + '.' + GetTokenStr(j + 2);
              j := j + 2;
            end;
            qMint := QualArgAliasName(qPath);
            argTok[na].Kind := tkIdent;
            argTok[na].IVal := 0;
            argTok[na].Line := Tokens[j].Line;
            argTok[na].SOffset := TokCharsAppend(qMint);
            argTok[na].SLen := Length(qMint);
            if dgQCount < MAX_DGEN_TUPLES then
            begin
              dgQName[dgQCount] := qMint;
              dgQPath[dgQCount] := qPath;
              Inc(dgQCount);
            end;
          end
          else
            argTok[na] := Tokens[j];
          Inc(na); Inc(j);
          if (j < TokCount) and (Tokens[j].Kind = tkComma) then Inc(j)
          else Break;
        end
        else ok := False;
      end;
      if ok and ((j >= TokCount) or (Tokens[j].Kind <> tkGt)) then ok := False;
      if ok and (na <> np) then ok := False;
      { A DECLARATION, not a use: `TFoo<T> = record ...`. `j` is the closing
        `>`, so a following `=` means this group is the LEFT-HAND SIDE of a type
        declaration that happens to reuse a name already registered as a
        template -- a unit shadowing a generic it imported (legal, and FPC
        compiles it), or a redeclaration in one unit. Rewriting it injects
        `specialize` in FRONT of a declaration and the parse dies with
        `Expected: =, but got: <name>`.
        The preceding token is a WHITELIST, not a blacklist, and that is the
        whole point: several genuine USES are also followed by `=`. A typed
        constant `x: TFoo<Integer> = (V: 1)` is one; `const P: ^specialize
        TTest<LongInt> = Nil` is another, and it is preceded by `specialize`,
        not by `:`. An earlier version of this guard excluded only `:` and so
        suppressed the rewrite for the `^specialize` spelling, widening
        regression-test-pascal-conformance-shard0-6-2 from the handful of type
        names that lex as tkIdent to EVERY type name. A declaration's left-hand
        side can only follow the `type` keyword or the `;` that ended the
        previous declaration, so test for those instead of trying to enumerate
        the ways a use can be spelled.
        bug-p-the-delphi-generic-rewrite-rewrites-a-shadowing-declaration-as-a-use }
      if ok and ((j + 1) < TokCount) and (Tokens[j+1].Kind = tkEq) and
         (i > 0) and
         ((Tokens[i-1].Kind = tkType) or (Tokens[i-1].Kind = tkSemicolon)) then
        ok := False;
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
        { ...and any OTHER template's parameter name, read from the token stream
          rather than from Templates[] -- the enclosing template that gives the
          name its meaning is usually not parsed yet when this runs. See
          CollectSpecializationBoundNamesFromTokens. }
        for k := 0 to na - 1 do
          for kk := 0 to SpecBoundNameCount - 1 do
            if (argTok[k].Kind = tkIdent) and
               CaseEqual(GetTokenStrFromRaw(argTok[k].SOffset, argTok[k].SLen),
                         GetTokenStrFromRaw(SpecBoundNameOff[kk], SpecBoundNameLen[kk])) then
              isParamForm := True;
        if DebugTrace then writeln('DGEN match at ', i, ' na=', na, ' paramform=', isParamForm);
        if dgDbg then
        begin
          write('PXXDBG p.dgen   group at=', i, ' line=', Tokens[i].Line,
                ' na=', na, ' paramform=', Ord(isParamForm), ' args=');
          for k := 0 to na - 1 do
            write(GetTokenStrFromRaw(argTok[k].SOffset, argTok[k].SLen), ' ');
          writeln;
        end;
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
              { The rewrite's only observable is the token stream it edits, so a
                test that merely compiles cannot tell a correct rewrite from one
                that injects in the wrong place. Print every in-place injection.
                bug-p-the-delphi-generic-rewrite-rewrites-a-shadowing-declaration-as-a-use }
              if PxxDbgEnabled('p.dgen') then
                writeln('PXXDBG p.dgen inject specialize before ', tname,
                        ' tok=', i, ' line=', Tokens[i].Line);
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

  { qualified-argument aliases FIRST -- a tuple declaration below names one }
  if dgQCount > 0 then
  begin
    NSpecInsCnt := 0;
    for k := 0 to dgQCount - 1 do
      EmitQualAliasDecl(dgQName[k], dgQPath[k]);
    if NSpecInsCnt > 0 then
    begin
      InsertTokens(insertAt, NSpecIns, NSpecInsCnt);
      insertAt := insertAt + NSpecInsCnt;
    end;
  end;

  { one alias declaration per distinct tuple, inserted in first-seen order }
  for si := 0 to seenCnt - 1 do
  begin
    if dgDbg or (mintFlt = '*') or CaseEqual(mintFlt, tname) or
       ((mintFlt <> '') and
        (Pos(mintFlt, GetTokenStrFromRaw(seenOff[si], seenLen[si])) > 0)) then
    begin
      write('PXXDBG p.mint dgen alias=',
            GetTokenStrFromRaw(seenOff[si], seenLen[si]), ' tmpl=', tname, ' args=');
      for k := 0 to np - 1 do
        write(GetTokenStrFromRaw(seenArg[si * MAX_TEMPLATE_PARAMS + k].SOffset,
                                 seenArg[si * MAX_TEMPLATE_PARAMS + k].SLen), ' ');
      writeln;
    end;
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

{ Desugar Delphi-surface uses of templates that came in through a USES clause.
  Called once per uses clause, immediately after it is consumed.

  Tokens[] is ONE array shared by every unit, and the main program is lexed
  FIRST -- units are appended after it. So a template declared in a used unit
  sits at a token index ABOVE every use of it in the program, and the sweep
  ParseGenericTemplateNamed runs (anchored at the template's own declaration,
  rewriting only what follows) can never reach those uses. The name then falls
  through to ParseTypeKind's recovery arm as `unknown type: TOne`.
  bug-p-a-delphi-mode-generic-from-a-used-unit-cannot-be-specialized

  The obvious repair -- start that sweep at 0 -- is wrong, and measurably so:
  every enclosing ParseUsesUnitBody frame has a savedTokPos into a region lexed
  EARLIER, and neither InsertTokens nor RemoveTokens adjusts it. A unit that
  itself uses another unit then resumes several tokens off (measured: `program
  nest / uses ua / ua uses ub` reported "unexpected token in a unit interface
  section" from ua, three tokens past where it stopped).

  So sweep from HERE instead. Every edit then lands strictly above the live
  cursor and above every saved one, because a use of an imported template cannot
  precede the `uses` that imports it. The same procedure does the work with the
  same minting -- this is a second CALL SITE, not a second implementation.

  The aliases land in the file that uses them, which is also where they belong:
  DelphiRewriteGenericUses splices bare `X = specialize T<Args>;` and relies on
  an open type section, and after a uses clause there is none -- hence the `type`
  token in front, added only when a round actually emitted something. }
procedure DesugarImportedDelphiGenericUses;
var
  at, rounds, before, atBefore, t, resume: Integer;
  ins: array[0..0] of TRawToken;
begin
  if (TemplateCount = 0) or (CurTok.Kind = tkEOF) or (TokPos < 1) then Exit;
  { CurTok holds Tokens[TokPos-1] -- step back so the splice lands in FRONT of
    the token already read, and the Next at the end reads the first spliced one.
    Same idiom as SpecializeInlineGenericFuncUses. }
  Dec(TokPos);
  at := TokPos;
  resume := TokPos;
  rounds := 0;
  repeat
    before := TokCount;
    atBefore := at;
    CollectSpecializationBoundNamesFromTokens;
    for t := 0 to TemplateCount - 1 do
      DelphiRewriteGenericUses(t, at, TemplateIsDelphi[t]);
    Inc(rounds);
    if rounds > 16 then
      Error('generic specialization nested deeper than 16 levels (or a rewrite loop)');
  { An unchanged TokCount is NOT "nothing happened": a round both inserts alias
    declarations and removes the `<Args>` groups it rewrote, and the two cancel
    exactly when one tuple is used twice. `at` advances only on an alias, so the
    pair of them is what "this round was idle" actually means. }
  until (TokCount = before) and (at = atBefore);
  { `at` advances by exactly the alias tokens each round emits, so `at > resume`
    is "something was declared" -- TokCount is NOT, because the same round also
    REMOVES each rewritten `<Args>` group and the two cancel: one tuple used
    twice removes 8 tokens and inserts 8, and the type section went missing. }
  if at > resume then
  begin
    ins[0].Kind := tkType; ins[0].IVal := 0; ins[0].Line := Tokens[TokPos].Line;
    ins[0].SOffset := 0; ins[0].SLen := 0;
    InsertTokens(TokPos, ins, 1);
  end;
  Next;
end;

{ ===== Generic type-parameter CONSTRAINTS =====

  `TFoo<T: class>` / `<T: record>` / `<T: constructor>` / `<T: TBase>` /
  `<T: IThing>`, combinable per parameter (`<T: class, IThing, constructor>`)
  and shared across a comma group -- `<T1, T2: IThing>` constrains BOTH.

  These used to be parsed and thrown away: a `while ... do Next` consumed the
  list to keep the parse moving and recorded nothing, so there was nothing for
  a specialization to be checked against and every constraint in the language
  meant exactly nothing. All 35 FAIL-marked fpc-testsuite tgenconstraint tests
  were wrongly ACCEPTED
  (bug-p-generic-type-constraints-are-parsed-and-discarded).

  Stored per (template, parameter) as a flag word plus a short list of named
  type constraints, keyed on the same flat ti*MAX_TEMPLATE_PARAMS+k layout as
  TemplateParamNames. Names go through TokChars rather than AnsiString slots,
  following SpecBoundName* above: the table is MAX_TEMPLATES*MAX_TEMPLATE_PARAMS
  wide and defs.inc keeps these integer-only for fixedpoint safety.

  CHECKED at specialization, not at template declaration, because pxx generics
  are token substitution: the template body has no concrete types to check, and
  the argument only exists once ParseSpecialization holds it. That is also the
  single choke point for BOTH spellings -- DelphiRewriteGenericUses rewrites a
  mode-Delphi `TFoo<TBar>` into a `specialize` alias declaration that lands
  right back here, so mode-objfpc and mode-delphi share one check. }
const
  TPC_CLASS  = 1;   { T: class       -- must be a class type }
  TPC_RECORD = 2;   { T: record      -- must be a value type }
  TPC_CTOR   = 4;   { T: constructor -- must be a class; see CheckTemplateConstraint }
  TPC_OPAQUE = 8;   { a constraint FORM this parser does not model: check nothing
                      for that parameter rather than enforce a partial reading }
  MAX_TPC_TYPES = 4;  { named class/interface constraints per parameter --
                        tgenconstraint27's TTest15 uses three plus `constructor` }
var
  TPConFlags   : array[0..MAX_TEMPLATES*MAX_TEMPLATE_PARAMS-1] of Integer;
  TPConNTypes  : array[0..MAX_TEMPLATES*MAX_TEMPLATE_PARAMS-1] of Integer;
  TPConTypeOff : array[0..MAX_TEMPLATES*MAX_TEMPLATE_PARAMS*MAX_TPC_TYPES-1] of Integer;
  TPConTypeLen : array[0..MAX_TEMPLATES*MAX_TEMPLATE_PARAMS*MAX_TPC_TYPES-1] of Integer;

function GCIsDescOrSelf(c, target: Integer): Boolean;
{ `c` is `target` or descends from it. Local rather than ir.inc's
  IsClassDescOrSelf, which is included AFTER this file. }
var guard: Integer;
begin
  Result := False;
  guard := 0;
  while (c >= 0) and (guard < MAX_UCLASS) do
  begin
    if c = target then
    begin
      Result := True;
      Exit;
    end;
    c := UClsParent[c];
    Inc(guard);
  end;
end;

function GCIntfDescends(dsc, anc: Integer): Boolean;
{ Interface `dsc` is `anc` or descends from it, walking UClsParent. }
var c, guard: Integer;
begin
  Result := False;
  c := dsc;
  guard := 0;
  while (c >= 0) and (guard < MAX_UCLASS) do
  begin
    if c = anc then
    begin
      Result := True;
      Exit;
    end;
    c := UClsParent[c];
    Inc(guard);
  end;
end;

function GCSupportsIntf(ci, intfCi: Integer): Boolean;
{ Does class `ci`, or an ancestor CLASS of it, DECLARE intfCi?

  "Declare" is the whole difficulty. The (class, interface) pairs live in the
  IMT rows, but pasparser_decl.inc does not store the declared list as written:
  having collected it, it appends every ANCESTOR of each declared interface so
  that `is`/`as`/`Supports` and base-interface assignment work
  (pasparser_decl.inc, "A class implementing a derived interface also
  implements every ancestor interface"). The IMT is therefore the CLOSURE, and
  the constraint rule needs the generating set: a class listing only ITest2
  (= interface(ITest1)) does NOT satisfy `T: ITest1`. The corpus pins that from
  three sides -- tgenconstraint18, 23 and 25 are all FAIL-marked and all accept
  under the closure.

  The generating set is recoverable without touching pasparser_decl.inc,
  because that flattening appends: `implOrig` freezes the declared count before
  the ancestor walk runs, and IMT rows are emitted in implIntf order. So the
  declared interfaces are a PREFIX, and a row is flattened-in exactly when some
  EARLIER row of the same class descends from it. That reconstruction is exact
  for every shape here; its one blind spot is a class that redundantly lists
  both a derived interface and its ancestor in that order
  (`class(TFoo, ITest2, ITest1)`), where the second is read as flattened. No
  test in the corpus writes that, and the effect is a refusal rather than a
  wrong acceptance. Recording implOrig in defs.inc would make it exact -- see
  the note filed with the ticket.

  ANCESTOR CLASSES are walked: a descendant really does implement what its base
  declares, and tgenconstraint1's TTest15<TTestClass8> needs it (TTestClass8
  declares only ITest2; its ITest1 comes from the base class TTestClass7). }
var c, i, j, guard: Integer;
    flattened: Boolean;
begin
  Result := False;
  c := ci;
  guard := 0;
  while (c >= 0) and (guard < MAX_UCLASS) do
  begin
    for i := 0 to IMTCount - 1 do
      if (IMTClass[i] = c) and (IMTIntf[i] = intfCi) then
      begin
        flattened := False;
        for j := 0 to i - 1 do
          if (IMTClass[j] = c) and (IMTIntf[j] <> intfCi) and
             GCIntfDescends(IMTIntf[j], intfCi) then
            flattened := True;
        if not flattened then
        begin
          Result := True;
          Exit;
        end;
      end;
    c := UClsParent[c];
    Inc(guard);
  end;
end;

procedure CheckTemplateConstraint(ti, k: Integer; const specArg: AnsiString;
                                  specArgKind: TTokenKind);
{ Check one specialization argument against the constraint recorded for
  parameter k of template ti. Errors name the constraint that was violated --
  the point of the exercise is a diagnostic about the CONSTRAINT, not about
  whatever the argument later fails to do. }
var
  base, flags, nT, j, argCi, conCi: Integer;
  isClass, isIntf, conOk: Boolean;
  conName, pfx, what: AnsiString;
begin
  base := ti * MAX_TEMPLATE_PARAMS + k;
  flags := TPConFlags[base];
  nT := TPConNTypes[base];
  { Unconstrained, or a form this parser chose not to model: nothing to check.
    Every generic in lib/, examples/ and the compiler's own source takes this
    exit -- not one of them constrains a parameter -- so everything below is
    reachable only from code that actually wrote a constraint. }
  if ((flags and TPC_OPAQUE) <> 0) or ((flags = 0) and (nT = 0)) then Exit;

  argCi := -1;
  if specArgKind = tkIdent then argCi := FindUClass(specArg);
  isClass := (argCi >= 0) and (not UClsIsRecord[argCi]) and (not UClsIsInterface[argCi]);
  isIntf := (argCi >= 0) and UClsIsInterface[argCi];

  { ONLY a fully declared class type is judged here. Everything else -- a name
    not in the class table, or a forward stub whose real declaration is still
    ahead -- is left alone, because at THIS point in the parse "not a class" and
    "not declared yet" are the same observation, and refusing on it rejects
    ordinary code:

      type TInner<T: class> = class end;
           TC = class end;              { declared BEFORE the use, and still
           TA = TInner<TC>;               unknown when the check runs }

    DelphiRewriteGenericUses desugars `TInner<TC>` by inserting an alias
    declaration at insertAt -- immediately after the TEMPLATE -- so the
    specialization is parsed AHEAD of TC, and TC is not in the table yet. The
    objfpc spelling has the same hazard through a forward `TC = class;`, whose
    stub carries no parent link, so a `T: TObject` constraint sees no ancestor
    chain to walk. Both were measured as false rejections before this guard.

    The cost is that a constraint is not enforced against an argument the parse
    has not reached: tgenconstraint4 (`LongInt`) and 5 (`TClass`) name types
    that are not classes and never will be, and both are still accepted. Fixing
    those means checking constraints AFTER the type section closes rather than
    mid-parse, which is where this check belongs -- see the ticket. It is a
    missed rejection, never a wrong one, which is the right way round. }
  pfx := 'generic constraint violated: ' + Templates[ti].Name + '<' +
         TemplateParamNames[base] + '> ';

  { NOT in the class table. The bail above is right for a name the parse has
    not REACHED yet, but two kinds of name are not "not yet" -- they are
    settled now and stay settled, so a constraint that requires a class can be
    refused on them without waiting for anything:

      * a builtin scalar (`LongInt`, `Double`, ...). BuiltinTypeNameTk answers
        from a fixed table, not from the symbol table, so its answer cannot
        change later in the parse. A user type may SHADOW the name, but then
        FindUClass above already found it and we never get here.
      * `TClass`, the metaclass. ParseTypeKind (pasparser_decl.inc:729) lowers
        a bare `TClass` to a class REFERENCE -- tyPointer with a tyClass
        element -- and a class reference is not a class instance type, which is
        what `T: class` asks for. A user-declared TClass wins there too, and
        would likewise have been found above.

    Only the constraints that REQUIRE a class or interface are enforced here
    (`class`, `constructor`, and any named-type constraint): none of those can
    ever be satisfied by a scalar or a metaclass. `record` is deliberately left
    alone -- whether a builtin scalar satisfies a value-type constraint is a
    separate question this ticket did not measure, and the failure mode stays
    laxness, which is the right way round.
    Fixes tgenconstraint4 (`TTest1<LongInt>`) and 5 (`TTest1<TClass>`), both
    `T: class`, both previously accepted. }
  if argCi < 0 then
  begin
    if BuiltinTypeNameTk(specArg) <> tyUnknown then
      what := 'a value type'
    else if CaseEqual(specArg, 'tclass') then
      what := 'a class reference'
    else
      Exit;   { merely not declared YET -- see the note above }

    if (flags and TPC_CLASS) <> 0 then
      Error(pfx + 'is constrained to `class`, but ' + specArg + ' is ' + what);
    if (flags and TPC_CTOR) <> 0 then
      Error(pfx + 'is constrained to `constructor`, but ' + specArg + ' is ' +
            what + ' and only a class can have one');
    if nT > 0 then
      Error(pfx + 'is constrained to ' +
            GetTokenStrFromRaw(TPConTypeOff[base * MAX_TPC_TYPES],
                               TPConTypeLen[base * MAX_TPC_TYPES]) +
            ', but ' + specArg + ' is ' + what);
    Exit;
  end;
  if UClsForward[argCi] then Exit;

  { argCi >= 0 past the guard above, so these three are the whole space:
    `object` and `record` both arrive as UClsIsRecord and read as a value type. }
  if isClass then what := 'a class type'
  else if isIntf then what := 'an interface type'
  else what := 'a value type';

  if ((flags and TPC_CLASS) <> 0) and (not isClass) then
    Error(pfx + 'is constrained to `class`, but ' + specArg + ' is ' + what);

  { `record` is the VALUE-type constraint: a class or an interface fails it and
    everything else passes. `object` reaches here as UClsIsRecord (it lowers as
    an advanced record since d23f52948), which is the right answer for it. }
  if ((flags and TPC_RECORD) <> 0) and (isClass or isIntf) then
    Error(pfx + 'is constrained to `record`, but ' + specArg + ' is ' + what);

  { `constructor` is enforced only as far as "must be a class". The corpus
    pins exactly that much -- tgenconstraint13/34/35/36 all pass a non-class --
    and no test anywhere requires a CLASS to be refused for lacking a
    parameterless constructor, so the second half would be an unverified
    rejection path over real code. Left deliberately, and noted in the ticket. }
  if ((flags and TPC_CTOR) <> 0) and (not isClass) then
    Error(pfx + 'is constrained to `constructor`, but ' + specArg + ' is ' +
          what + ' and only a class can have one');

  for j := 0 to nT - 1 do
  begin
    conName := GetTokenStrFromRaw(TPConTypeOff[base * MAX_TPC_TYPES + j],
                                  TPConTypeLen[base * MAX_TPC_TYPES + j]);
    conCi := FindUClass(conName);
    { The constraint names a type we cannot resolve here -- unchecked, for the
      same reason an unresolved argument is. }
    if conCi < 0 then Continue;
    if UClsIsInterface[conCi] then
    begin
      { Satisfied by a CLASS that declares the interface, or by an INTERFACE
        that is it or descends from it -- tgenconstraint1 accepts
        TTest5<IInterface>, TTest5<ITest1> and TTest5<ITest2> against
        `T: IInterface`, while tgenconstraint17 rejects TTest7<IInterface>
        against `T: ITest1` because IInterface is the ancestor, not a
        descendant. The direction is the whole distinction. }
      if isIntf then
        conOk := GCIntfDescends(argCi, conCi)
      else
        conOk := isClass and GCSupportsIntf(argCi, conCi);
      if not conOk then
        Error(pfx + 'is constrained to `' + conName + '`, but ' + specArg +
              ' does not implement or descend from it');
    end
    else
    begin
      { `T: TObject` is the ROOT constraint, and it cannot be answered by
        walking UClsParent: pasparser_decl.inc:4594-4606 deliberately leaves
        parentCi = -1 for `class(TObject)` AND for a plain `class`, because a
        real parent link would relocate every `class(TObject)` VMT and break the
        implicit-root model. TObject is nonetheless a registered builtin class
        ROW, so FindUClass finds it here and the walk below then looks for a row
        the chain structurally never reaches -- terminating at -1 for every user
        class. `TBox<TObject>` passed only because argCi = conCi matched on the
        first iteration; every descendant, implicit or explicit, was rejected.

        Two representations of "descends from TObject" that were never
        reconciled -- the parent chain says -1, the class table says a row --
        and the check asked in the coordinate system where the answer is
        unreachable. Answer it in the other one: in Pascal EVERY class descends
        from TObject, so this constraint means exactly `isClass`, which is
        already computed. Not a loosening -- a non-class still fails, so the
        FAIL-marked tgenconstraint tests stay rejected.
        regression-p-generic-constraint-check-rejects-a-class-declared-in-the-same-type-section }
      if CaseEqual(conName, 'TObject') then
        conOk := isClass
      else
        conOk := isClass and GCIsDescOrSelf(argCi, conCi);
      if not conOk then
        Error(pfx + 'is constrained to `' + conName + '`, but ' + specArg +
              ' is not ' + conName + ' or a descendant of it');
    end;
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
  templateName: AnsiString;
  depth, startTok, cur, finalCur, np, gi, scan, bEnd: Integer;
  dgenAt, dgenRounds, dgenBefore, dgenAtBefore, dgenT: Integer;   { the nested-specialize fixed point }
  pnames: array[0..MAX_TEMPLATE_PARAMS-1] of AnsiString;
  doneParams, bodyless: Boolean;
  { per-parameter constraints, flushed into TPCon* with the names below }
  pconFlags   : array[0..MAX_TEMPLATE_PARAMS-1] of Integer;
  pconNTypes  : array[0..MAX_TEMPLATE_PARAMS-1] of Integer;
  pconTypeOff : array[0..MAX_TEMPLATE_PARAMS*MAX_TPC_TYPES-1] of Integer;
  pconTypeLen : array[0..MAX_TEMPLATE_PARAMS*MAX_TPC_TYPES-1] of Integer;
  cFlags, cNTypes, groupStart, cgi, cj: Integer;
  cTypeOff, cTypeLen: array[0..MAX_TPC_TYPES-1] of Integer;
begin
  { Copy BEFORE Next: callers pass CurTok.SVal, and a const AnsiString param
    aliases it by reference — Next would mutate the name out from under us. }
  templateName := templateNameIn;
  Next; { consume the template name (caller verified it) }

  { <T> / <TKey, TData> / <T: TObject> / <TKey; TData: TObject> — groups of
    comma-separated names, each group with an optional `: constraint` (the
    constraint list runs to the next `;` or `>`), groups separated by `;`.
    Constraints are RECORDED here and checked at each specialization: pxx
    generics are token substitution, so the template body has nothing concrete
    to check against and the argument is the only place the question can be
    asked. They used to be skipped outright, which meant no constraint was ever
    enforced at all -- see the TPCon* block above. }
  Expect(tkLt, '<');
  np := 0;
  doneParams := False;
  for cj := 0 to MAX_TEMPLATE_PARAMS - 1 do
  begin
    pconFlags[cj] := 0;
    pconNTypes[cj] := 0;
  end;
  repeat
    groupStart := np;
    repeat
      if CurTok.Kind <> tkIdent then Error('expected generic parameter name');
      if np >= MAX_TEMPLATE_PARAMS then Error('too many generic parameters (MAX_TEMPLATE_PARAMS)');
      pnames[np] := CurTok.SVal; Inc(np); Next;
    until not Eat(tkComma);
    if Eat(tkColon) then
    begin
      { The constraint list belongs to the whole comma group just parsed:
        `<T1, T2: ITest1>` constrains BOTH parameters (tgenconstraint31-33). }
      cFlags := 0;
      cNTypes := 0;
      repeat
        if CurTok.Kind = tkClass then cFlags := cFlags or TPC_CLASS
        else if CurTok.Kind = tkRecord then cFlags := cFlags or TPC_RECORD
        else if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'constructor') then
          cFlags := cFlags or TPC_CTOR
        else if CurTok.Kind = tkIdent then
        begin
          { a named class or interface constraint }
          if cNTypes >= MAX_TPC_TYPES then cFlags := cFlags or TPC_OPAQUE
          else
          begin
            cTypeOff[cNTypes] := TokCharsAppend(CurTok.SVal);
            cTypeLen[cNTypes] := Length(CurTok.SVal);
            Inc(cNTypes);
          end;
        end
        else
          { a form this parser does not model (a qualified name, a nested
            specialization): enforce NOTHING for these parameters rather than
            act on half a reading }
          cFlags := cFlags or TPC_OPAQUE;
        Next;
      until not Eat(tkComma);
      { Anything still standing before the `;`/`>` is a shape we did not model
        either -- skip it exactly as this loop always did, and mark it opaque so
        the partial reading above is never enforced. }
      if (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkGt) then
      begin
        cFlags := cFlags or TPC_OPAQUE;
        while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkGt) and
              (CurTok.Kind <> tkEOF) do
          Next;
      end;
      for cgi := groupStart to np - 1 do
      begin
        pconFlags[cgi] := cFlags;
        pconNTypes[cgi] := cNTypes;
        for cj := 0 to cNTypes - 1 do
        begin
          pconTypeOff[cgi * MAX_TPC_TYPES + cj] := cTypeOff[cj];
          pconTypeLen[cgi * MAX_TPC_TYPES + cj] := cTypeLen[cj];
        end;
      end;
    end;
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
          ((CurTok.Kind = tkIdent) and
           (CaseEqual(CurTok.SVal, 'interface') or CaseEqual(CurTok.SVal, 'object')))) then
    Error('generic templates must be class, record, object, interface, array or procedure declarations');

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
      { `class abstract;` / `class sealed(TBase);` -- the Delphi modifiers sit
        between `class` and the heritage list or the `;`. Unskipped, the
        bodyless test below looks at `abstract` rather than at the `;`, decides
        the declaration HAS a body, and hands it to the depth loop -- which has
        no `end` to count down to and swallows every following declaration
        until it finds one. That is what walled rtl-generics at
        `TCustomPointersEnumerator<T, PT> = class abstract(TEnumerator<PT>);`
        and reported the damage 24 lines EARLIER, on a line that was fine.
        Needs all three of generic + modifier + bodyless: the non-generic path
        consumes the modifiers itself (pasparser_decl.inc ~4449) and a real
        body ends at its own `end`.
        This is the sibling of the same omission in CollectNestedTypeNames
        above -- one decision, two hand-rolled copies. }
      while (scan < TokCount) and (Tokens[scan].Kind = tkIdent) and
            (CaseEqual(GetTokenStr(scan), 'abstract') or
             CaseEqual(GetTokenStr(scan), 'sealed')) do Inc(scan);
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
      { Three cases, one decision, one implementation -- ClassTokOpensBody.
        A member prefix (`class function/var/property/of`, soft
        `class constructor`) opens no body; so does a BODILESS declaration
        (`TEnumerator = class(TCustomListEnumerator<T>);`, nested inside
        TList's own `type` section in rtl-generics), and counting either as an
        opener leaves depth one too high, so this template's `end` closes the
        wrong level and the capture swallows every declaration up to the next
        stray `end`. Measured: TList captured 10,914 tokens against a corpus
        maximum of 1,677 everywhere else.
        bug-p-the-rtl-generics-corpus-stops-on-tkey-in-a-tlist-body }
      if ClassTokOpensBody(cur, bEnd) then
        Inc(depth)
      else if bEnd >= 0 then
        cur := bEnd;   { the Inc(cur) below steps past the ';' }
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
  begin
    TemplateParamNames[TemplateCount * MAX_TEMPLATE_PARAMS + gi] := pnames[gi];
    TPConFlags[TemplateCount * MAX_TEMPLATE_PARAMS + gi] := pconFlags[gi];
    TPConNTypes[TemplateCount * MAX_TEMPLATE_PARAMS + gi] := pconNTypes[gi];
    for cj := 0 to pconNTypes[gi] - 1 do
    begin
      TPConTypeOff[(TemplateCount * MAX_TEMPLATE_PARAMS + gi) * MAX_TPC_TYPES + cj] :=
        pconTypeOff[gi * MAX_TPC_TYPES + cj];
      TPConTypeLen[(TemplateCount * MAX_TEMPLATE_PARAMS + gi) * MAX_TPC_TYPES + cj] :=
        pconTypeLen[gi * MAX_TPC_TYPES + cj];
    end;
  end;
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

    A round is idle when it neither changed TokCount nor advanced dgenAt -- both,
    because an alias insertion and the removal of the group it replaced cancel
    exactly when one tuple is used twice, and TokCount alone then reads "idle" on
    a round that did work. The cap is a runaway guard,
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
    dgenAtBefore := dgenAt;
    CollectSpecializationBoundNamesFromTokens;
    for dgenT := 0 to TemplateCount - 1 do
      DelphiRewriteGenericUses(dgenT, dgenAt, TemplateIsDelphi[dgenT]);
    Inc(dgenRounds);
    if dgenRounds > 16 then
      Error('generic specialization nested deeper than 16 levels (or a rewrite loop)');
  { …and dgenAt, for the reason spelled out in DesugarImportedDelphiGenericUses:
    inserted aliases and removed `<Args>` groups cancel in TokCount, so TokCount
    alone can read "idle" on a round that did work. }
  until (TokCount = dgenBefore) and (dgenAt = dgenAtBefore);

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

{ ---- QUALIFIED generic arguments, normalised to one token ------------------

  `specialize TEnum<TOuter.TPair>` is legal Pascal and FPC compiles it. Every
  mechanism here reads an argument as exactly ONE TOKEN -- five
  IsConcreteTypeArgKind tests, NestedSpecAlias, NestedSpecArg, the SpecSub*
  substitution set, and the storage type NSpecArg: array of TRawToken. A
  qualified name is three tokens and fits none of them.

  So it is NORMALISED, not special-cased: the dotted form is rewritten at the
  one place it is read into a single minted identifier naming an ordinary type
  alias, and the alias declaration is emitted through the prerequisite path that
  already exists for nested specializations. Nothing downstream ever sees a dot.
  The alternative -- teach all five tests and the storage type about token
  RANGES -- adds a second argument shape to six places, and per
  devdocs/dev/normalise-dont-special-case.md the second path is the one that
  stays broken.

  The target form is measured, not assumed: `TAlias = TOuter.TPair;` followed by
  `specialize TEnum<TAlias>` compiles and runs identically on pxx and FPC.

  NAME SPELLING, and why it carries a leading `$`. The specialization minter
  produces `Name$Arg1$Arg2`, so a plain `TOuter$TPair` here would be exactly what
  `TOuter<TPair>` mints -- a real collision between two different types under
  arity overloading, which is the failure that is silent. A leading `$` cannot be
  produced by that minter and cannot be written in source, so `$qual$TOuter$TPair`
  collides with nothing by construction. It is a synthetic tkIdent and is only
  ever compared as a string, so the character never has to be lexable.

  DECLARED ONCE PER COMPILATION. Two specializations naming the same qualified
  type would otherwise emit the alias twice and get a duplicate-type error, so a
  mint is recorded in QualAliasName the moment its declaration is emitted and is
  never emitted again. }

const MAX_QUAL_ARG_ALIASES = 128;
var
  QualAliasName : array[0..MAX_QUAL_ARG_ALIASES-1] of AnsiString;
  QualAliasCount: Integer;
  { pending for the specialization currently being parsed }
  QNeedName : array[0..MAX_TEMPLATE_PARAMS-1] of AnsiString;
  QNeedPath : array[0..MAX_TEMPLATE_PARAMS-1] of AnsiString;
  QNeedCount: Integer;

{ The mint for one dotted path: `TOuter.TPair` -> `$qual$TOuter$TPair`. }
function QualArgAliasName(const path: AnsiString): AnsiString;
var i: Integer; r: AnsiString;
begin
  r := '$qual$';
  for i := 1 to Length(path) do
    if path[i] = '.' then r := r + '$' else r := r + path[i];
  QualArgAliasName := r;
end;

{ Record that this specialization needs `aliasNm = path;` declared ahead of it.
  Silent no-op when the alias already exists -- that is the common case once a
  program names the same qualified type twice. }
procedure NoteQualArgNeed(const aliasNm, path: AnsiString);
var k: Integer;
begin
  for k := 0 to QualAliasCount - 1 do
    if CaseEqual(QualAliasName[k], aliasNm) then Exit;
  for k := 0 to QNeedCount - 1 do
    if CaseEqual(QNeedName[k], aliasNm) then Exit;
  if QNeedCount >= MAX_TEMPLATE_PARAMS then Exit;
  QNeedName[QNeedCount] := aliasNm;
  QNeedPath[QNeedCount] := path;
  Inc(QNeedCount);
end;

{ One token into NSpecIns. Flat, not nested inside EmitQualAliasDecl: nested
  routines appear nowhere else in this file. }
procedure QualPush(k: TTokenKind; const txt: AnsiString; ln: Integer);
begin
  if NSpecInsCnt >= MAX_NESTED_SPECS * (8 + 2 * MAX_TEMPLATE_PARAMS) then
    Error('nested specialization token buffer overflow');
  NSpecIns[NSpecInsCnt].Kind := k;
  NSpecIns[NSpecInsCnt].IVal := 0;
  NSpecIns[NSpecInsCnt].Line := ln;
  if txt = '' then
  begin
    NSpecIns[NSpecInsCnt].SOffset := 0;
    NSpecIns[NSpecInsCnt].SLen := 0;
  end
  else
  begin
    NSpecIns[NSpecInsCnt].SOffset := TokCharsAppend(txt);
    NSpecIns[NSpecInsCnt].SLen := Length(txt);
  end;
  Inc(NSpecInsCnt);
end;

{ Emit `HoistFull = <the RHS, substituted>;` into NSpecIns for every candidate a
  generic argument actually named. Runs with HoistActive False so the RHS is not
  collapsed into a reference to the declaration being written. }
procedure EmitHoistedDecls(const specName: AnsiString);
var k, n, q, ln: Integer;
begin
  ln := 0;
  if TokPos > 0 then ln := Tokens[TokPos - 1].Line;
  for k := 0 to HoistCount - 1 do
    if HoistUsed[k] and not HoistAlreadyEmitted(HoistFull[k]) then
    begin
      HoistActive := False;
      n := SpecializeToBuffer(HoistStart[k], HoistEnd[k] - HoistStart[k] + 1, specName);
      HoistActive := False;
      if HoistEmittedCount < MAX_HOISTED_NESTED * 8 then
      begin
        HoistEmitted[HoistEmittedCount] := HoistFull[k];
        Inc(HoistEmittedCount);
      end;
      if NSpecInsCnt + n + 4 > MAX_NESTED_SPECS * (8 + 2 * MAX_TEMPLATE_PARAMS) then
        Error('hoisted nested type is too large for the prerequisite buffer ' +
              '(raise MAX_NESTED_SPECS): ' + HoistFull[k]);
      QualPush(tkIdent, HoistFull[k], ln);
      QualPush(tkEq, '', ln);
      for q := 0 to n - 1 do
      begin
        NSpecIns[NSpecInsCnt] := SpecializeTokens[q];
        Inc(NSpecInsCnt);
      end;
      QualPush(tkSemicolon, '', ln);
    end;
end;

{ Emit `alias = A.B.C;` into NSpecIns, and mark the alias as declared so no
  later specialization emits it a second time. }
procedure EmitQualAliasDecl(const aliasNm, path: AnsiString);
var ln, i, start: Integer;
begin
  { Declared once per compilation, and the check lives HERE rather than in each
    caller: the Delphi rewrite reaches this with duplicates by construction (one
    entry per OCCURRENCE of the group, and it runs to a fixed point), while the
    objfpc path filters in NoteQualArgNeed. Two filters for one rule is how the
    second one goes stale, so there is one, and it is the one nothing can skip. }
  for i := 0 to QualAliasCount - 1 do
    if CaseEqual(QualAliasName[i], aliasNm) then Exit;
  ln := 0;
  if TokPos > 0 then ln := Tokens[TokPos - 1].Line;
  QualPush(tkIdent, aliasNm, ln);
  QualPush(tkEq, '', ln);
  start := 1;
  for i := 1 to Length(path) + 1 do
    if (i > Length(path)) or (path[i] = '.') then
    begin
      if start > 1 then QualPush(tkDot, '', ln);
      QualPush(tkIdent, Copy(path, start, i - start), ln);
      start := i + 1;
    end;
  QualPush(tkSemicolon, '', ln);
  if QualAliasCount < MAX_QUAL_ARG_ALIASES then
  begin
    QualAliasName[QualAliasCount] := aliasNm;
    Inc(QualAliasCount);
  end;
end;

{ PROBE (p.mint): every nested-specialization alias declaration this compiler
  mints, tagged with the SITE that minted it and printed with the ARGUMENT
  TOKENS exactly as they will be emitted. The defect shape it exists to catch is
  an argument that is still a template PARAMETER name -- `IEqualityComparer$TKey`
  -- which means the mapping through SpecSub* in NestedSpecArg did not happen or
  ran under the wrong substitution set. PXXDBG=p.mint:* prints all;
  p.mint:<text> prints only aliases containing <text> or minted from that
  template. bug-p-the-rtl-generics-corpus-stops-on-tkey-in-a-tlist-body }
procedure DbgMintTrace(const site, aliasNm, tmplNm: AnsiString; base, nArgs: Integer);
var k: Integer; flt: AnsiString;
begin
  flt := PxxDbgArg('p.mint');
  if flt = '' then Exit;
  if (flt <> '*') and (Pos(flt, aliasNm) = 0) and (not CaseEqual(flt, tmplNm)) then Exit;
  write('PXXDBG p.mint ', site, ' alias=', aliasNm, ' tmpl=', tmplNm, ' args=');
  for k := 0 to nArgs - 1 do
    write(GetTokenStrFromRaw(NSpecArg[base + k].SOffset, NSpecArg[base + k].SLen), ' ');
  writeln;
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
    begin
      DbgMintTrace('late', NSpecName[k], NSpecTmpl[k], k * MAX_TEMPLATE_PARAMS, NSpecNArg[k]);
      EmitSpecDecl(NSpecName[k], NSpecTmpl[k], k * MAX_TEMPLATE_PARAMS, NSpecNArg[k]);
    end;
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

{ The arena index of the `;` that ends the declaration whose RHS starts at d,
  stepping over any nested record/class/case body. -1 when it never closes.
  Flat, not nested inside CollectHoistCandidates: nested routines appear nowhere
  else in this file. }
function HoistDeclEndAt(d, limit: Integer): Integer;
var q, dep: Integer;
begin
  q := d; dep := 0;
  while q < limit do
  begin
    if (TemplateTokens[q].Kind = tkRecord) or (TemplateTokens[q].Kind = tkCase) or
       (TemplateTokens[q].Kind = tkClass) then
      Inc(dep)
    else if TemplateTokens[q].Kind = tkEnd then
    begin
      Dec(dep);
      if dep < 0 then Break;
    end
    else if (TemplateTokens[q].Kind = tkSemicolon) and (dep <= 0) then
    begin
      HoistDeclEndAt := q;
      Exit;
    end;
    Inc(q);
  end;
  HoistDeclEndAt := -1;
end;

{ Find the nested TYPE declarations of one template's class body and record each
  one's name and RHS extent. Nothing is hoisted here -- this only builds the
  candidate set; HoistUsed decides. }
procedure CollectHoistCandidates(ti: Integer; const specName: AnsiString);
var ts, tc, j, depth, k, pdepth: Integer;
    inTypeSec, isModifier: Boolean;
    nm: AnsiString;

begin
  HoistCount := 0;
  ts := Templates[ti].TokStart;
  tc := Templates[ti].TokCount;
  depth := 0;
  inTypeSec := False;
  j := ts;
  while j < ts + tc do
  begin
    if TemplateTokens[j].Kind = tkEnd then
    begin
      Dec(depth);
      if depth <= 0 then Break;
      inTypeSec := False;
    end
    else if (TemplateTokens[j].Kind = tkRecord) or (TemplateTokens[j].Kind = tkCase) then
      Inc(depth)
    else if TemplateTokens[j].Kind = tkClass then
    begin
      { `class function` / `class var` / `class of` etc. is a MODIFIER and opens
        no body -- the same distinction CollectNestedTypeNames documents. }
      isModifier := (j + 1 < ts + tc) and
                    ((TemplateTokens[j + 1].Kind = tkFunction) or
                     (TemplateTokens[j + 1].Kind = tkProcedure) or
                     (TemplateTokens[j + 1].Kind = tkVar) or
                     (TemplateTokens[j + 1].Kind = tkConst) or
                     (TemplateTokens[j + 1].Kind = tkOf) or
                     ((TemplateTokens[j + 1].Kind = tkIdent) and
                      (CaseEqual(GetTokenStrFromRaw(TemplateTokens[j + 1].SOffset,
                                                    TemplateTokens[j + 1].SLen), 'operator') or
                       CaseEqual(GetTokenStrFromRaw(TemplateTokens[j + 1].SOffset,
                                                    TemplateTokens[j + 1].SLen), 'constructor') or
                       CaseEqual(GetTokenStrFromRaw(TemplateTokens[j + 1].SOffset,
                                                    TemplateTokens[j + 1].SLen), 'destructor'))));
      if not isModifier then
      begin
        { a BODILESS class opens nothing -- see the same case in
          CollectNestedTypeNames, and the bug it cost:
          bug-p-a-bodiless-class-with-a-parent-swallows-the-rest-of-the-type-section }
        k := j + 1;
        while (k < ts + tc) and (TemplateTokens[k].Kind = tkIdent) and
              (CaseEqual(GetTokenStrFromRaw(TemplateTokens[k].SOffset,
                                            TemplateTokens[k].SLen), 'abstract') or
               CaseEqual(GetTokenStrFromRaw(TemplateTokens[k].SOffset,
                                            TemplateTokens[k].SLen), 'sealed')) do Inc(k);
        if (k < ts + tc) and (TemplateTokens[k].Kind = tkLParen) then
        begin
          pdepth := 0;
          while k < ts + tc do
          begin
            if TemplateTokens[k].Kind = tkLParen then Inc(pdepth)
            else if TemplateTokens[k].Kind = tkRParen then
            begin
              Dec(pdepth);
              if pdepth <= 0 then begin Inc(k); Break; end;
            end;
            Inc(k);
          end;
        end;
        if (k >= ts + tc) or (TemplateTokens[k].Kind <> tkSemicolon) then
          Inc(depth);
      end;
    end
    else if TemplateTokens[j].Kind = tkType then
      inTypeSec := (depth = 1)
    else if (TemplateTokens[j].Kind = tkVar) or (TemplateTokens[j].Kind = tkConst) or
            (TemplateTokens[j].Kind = tkProcedure) or (TemplateTokens[j].Kind = tkFunction) or
            (TemplateTokens[j].Kind = tkProperty) then
      inTypeSec := False
    else if inTypeSec and (depth = 1) and (TemplateTokens[j].Kind = tkIdent) and
            (j + 2 < ts + tc) and (TemplateTokens[j + 1].Kind = tkEq) then
    begin
      k := HoistDeclEndAt(j + 2, ts + tc);
      if (k > j + 2) and (HoistCount < MAX_HOISTED_NESTED) then
      begin
        nm := GetTokenStrFromRaw(TemplateTokens[j].SOffset, TemplateTokens[j].SLen);
        HoistName[HoistCount]  := nm;
        HoistFull[HoistCount]  := specName + '$' + nm;
        HoistStart[HoistCount] := j + 2;
        HoistEnd[HoistCount]   := k - 1;
        HoistUsed[HoistCount]  := False;
        Inc(HoistCount);
        j := k;
      end;
    end;
    Inc(j);
  end;
end;


{ Record every `specialize NAME<args>` in one template-arena range as a nested
  prerequisite, skipping this declaration itself and anything already known or
  already queued. One body, three callers (the class body, each buffered method,
  and each not-yet-buffered mode-Delphi method impl) -- a second copy per source
  is how the method-body arm came to be missing in the first place. }
procedure ScanRangeForNestedSpecs(ts, tc: Integer; const specName: AnsiString);
var i, j, k, na, gEnd: Integer; aliasNm, nsDbg: AnsiString; dup: Boolean;
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
          { PROBE (p.nspec): the SUBSTITUTION SET in force at the moment a
            prerequisite is registered, printed beside the alias it minted. An
            argument that comes out as a template PARAMETER name means the name
            was not in SpecSubNames here -- and this line says which names were.
            bug-p-the-rtl-generics-corpus-stops-on-tkey-in-a-tlist-body }
          nsDbg := PxxDbgArg('p.nspec');
          if (nsDbg = '*') or ((nsDbg <> '') and (Pos(nsDbg, aliasNm) > 0)) then
          begin
            write('PXXDBG p.nspec reg alias=', aliasNm,
                  ' under=', specName, ' tmplName=', SpecializeTemplateName,
                  ' nsub=', SpecSubCount, ' subs=');
            for k := 0 to SpecSubCount - 1 do
              write(SpecSubNames[k], '->', SpecSubValues[k], ' ');
            { WHICH RANGE the group was found in -- the caller passes ts/tc and
              nothing else identifies it, so print the range and its first
              tokens. A range whose head is a different template's declaration
              is the defect. }
            write(' ts=', ts, ' tc=', tc, ' head=');
            for k := 0 to 7 do
              if k < tc then
                write(GetTokenStrFromRaw(TemplateTokens[ts + k].SOffset,
                                         TemplateTokens[ts + k].SLen), ' ');
            write(' at=');
            for k := -2 to 4 do
              if (i + k >= 0) and (i + k < tc) then
                write(GetTokenStrFromRaw(TemplateTokens[ts + i + k].SOffset,
                                         TemplateTokens[ts + i + k].SLen), ' ');
            writeln;
          end;
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
  qPath: AnsiString;     { non-empty while the current argument is a dotted name }
  hoistPending: Boolean; { some nested type of this template must be lifted out }
begin
  Result := False;
  Next; { consume 'specialize' }
  if CurTok.Kind <> tkIdent then Error('expected generic template name');
  templateName := CurTok.SVal; Next;

  Expect(tkLt, '<');
  nc := 0;
  NSpecCount := 0;
  QNeedCount := 0;
  repeat
    if not IsConcreteTypeArgKind(CurTok.Kind) then
      Error('expected concrete type name');
    if nc >= MAX_TEMPLATE_PARAMS then Error('too many specialization arguments (MAX_TEMPLATE_PARAMS)');
    { A QUALIFIED argument -- `specialize TEnum<TOuter.TPair>` -- is consumed
      whole here and replaced by the single minted identifier of an ordinary
      alias, so every mechanism below this loop keeps seeing one token per
      argument. See the QualArgAliasName block above for why it is normalised
      here rather than taught to the six places that read an argument. }
    qPath := '';
    if (CurTok.Kind = tkIdent) and (TokPos < TokCount) and
       (Tokens[TokPos].Kind = tkDot) then
    begin
      qPath := GetTokenStr(TokPos - 1);
      while (TokPos < TokCount) and (Tokens[TokPos].Kind = tkDot) do
      begin
        Next;   { the '.' }
        Next;   { the name after it }
        if CurTok.Kind <> tkIdent then
          Error('expected a type name after "." in a generic argument');
        qPath := qPath + '.' + GetTokenStr(TokPos - 1);
      end;
    end;
    if qPath <> '' then
    begin
      cNames[nc] := QualArgAliasName(qPath);
      cKinds[nc] := tkIdent;
      NSpecArg[(MAX_NESTED_SPECS - 1) * MAX_TEMPLATE_PARAMS + nc].Kind := tkIdent;
      NSpecArg[(MAX_NESTED_SPECS - 1) * MAX_TEMPLATE_PARAMS + nc].IVal := 0;
      NSpecArg[(MAX_NESTED_SPECS - 1) * MAX_TEMPLATE_PARAMS + nc].Line := Tokens[TokPos - 1].Line;
      NSpecArg[(MAX_NESTED_SPECS - 1) * MAX_TEMPLATE_PARAMS + nc].SOffset := TokCharsAppend(cNames[nc]);
      NSpecArg[(MAX_NESTED_SPECS - 1) * MAX_TEMPLATE_PARAMS + nc].SLen := Length(cNames[nc]);
      NoteQualArgNeed(cNames[nc], qPath);
    end
    else
    begin
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
    end;
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

  { Every constraint the template declared, against the arguments it actually
    got. Here because this is the one point both spellings reach: mode-delphi
    `TFoo<TBar>` is rewritten into a `specialize` alias by
    DelphiRewriteGenericUses and arrives back through this function. }
  for i := 0 to nc - 1 do
    CheckTemplateConstraint(ti, i, cNames[i], cKinds[i]);

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

  { The template's OWN nested type declarations, as hoist CANDIDATES only --
    nothing is hoisted unless a generic argument in the body names one, which
    NestedSpecArg decides while the prerequisite scan runs below. A template with
    nested types and no such use is untouched. See the hoisting note. }
  CollectHoistCandidates(ti, specName);

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
      QNeedCount := 0;
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
  { "still to emit", NOT "used" -- see HoistEmitted. On the re-parse behind its
    own hoists this is False, which is what ends the deferral. }
  hoistPending := False;
  for k := 0 to HoistCount - 1 do
    if HoistUsed[k] and not HoistAlreadyEmitted(HoistFull[k]) then hoistPending := True;

  if (NSpecCount > 0) and (nDeclEdges = 0) and (QNeedCount = 0) and (not hoistPending) then
  begin
    NSpecInsCnt := 0;
    for k := 0 to NSpecCount - 1 do
    begin
      DbgMintTrace('immediate', NSpecName[k], NSpecTmpl[k], k * MAX_TEMPLATE_PARAMS, NSpecNArg[k]);
      EmitSpecDecl(NSpecName[k], NSpecTmpl[k], k * MAX_TEMPLATE_PARAMS, NSpecNArg[k]);
    end;
    InsertTokens(TokPos, NSpecIns, NSpecInsCnt);
    NSpecCount := 0;
  end;

  { A pending qualified-argument alias forces the DEFERRAL path and cannot use
    the fast one above. The fast path leaves this declaration registered and puts
    the prerequisites AFTER it, which is right for a materialisation-time nested
    spec and wrong here: the alias is a DECLARATION-time dependency -- the
    argument is substituted into the class body that gets streamed immediately,
    so the alias has to be a type before this declaration is parsed at all, not
    after. Deferring re-emits the declaration behind the alias, and the re-parse
    sees the minted identifier and takes the ordinary single-token path. }
  if (NSpecCount > 0) or (QNeedCount > 0) or hoistPending then
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
      if NSpecCount > 0 then
        Error('circular generic specialization: ' + specName + ' requires ' +
              NSpecName[0] + ', which requires ' + specName + ' back')
      else
        Error('circular generic specialization: ' + specName);
    NSpecInsCnt := 0;
    { HOISTED nested types first of all -- the nested prerequisite emitted below
      names one as its argument, and the re-emitted declaration's own class body
      aliases to it. }
    if hoistPending then EmitHoistedDecls(specName);
    { qualified-argument aliases next: a nested prerequisite emitted below may
      name one of them as its own argument. }
    for k := 0 to QNeedCount - 1 do
      EmitQualAliasDecl(QNeedName[k], QNeedPath[k]);
    QNeedCount := 0;
    for k := 0 to NSpecCount - 1 do
    begin
      DbgMintTrace('deferred', NSpecName[k], NSpecTmpl[k], k * MAX_TEMPLATE_PARAMS, NSpecNArg[k]);
      EmitSpecDecl(NSpecName[k], NSpecTmpl[k], k * MAX_TEMPLATE_PARAMS, NSpecNArg[k]);
    end;
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
  { The collapse of a hoisted declaration's RHS applies to the CLASS BODY and
    nowhere else, so the gate is opened around this one call rather than left on.
    HoistStart/HoistEnd are absolute arena indices belonging to ONE template, and
    SpecializeToBuffer has other callers (generic functions, the pending-method
    flush) whose ranges are in the same arena — a stale candidate set could
    otherwise collide with an unrelated range at the same index. Method bodies
    need no collapse: they refer to the nested type by NAME, and the name is
    still declared in the class, now as an alias. }
  HoistActive := True;
  SpecializeStream(Templates[ti].TokStart, Templates[ti].TokCount, specName);
  HoistActive := False;
  Next;
end;

{ Materialise the methods of every class specialization buffered during the
  type section just parsed. Called once the section's token loop exits, so the
  streamed `procedure`/`function` bodies land after the whole `type` block and
  are parsed as ordinary top-level subroutines. Inserting at TokPos prepends
  before the section-terminating token, which was un-read by the caller. }
function UnitImplAnchor: Integer;
{ Where a method body must land when the specialization that needs it was
  written in a unit's INTERFACE: just inside the implementation section, past
  its `uses` clause if it has one. -1 when there is no implementation ahead.

  `implementation` is a plain tkIdent here, not a keyword token -- ParseUnit
  scans for it exactly this way (pasparser_proc.inc: `(CurTok.SVal =
  'implementation') or (CurTok.SVal = 'Implementation')`), and this must agree
  with that scan or the two disagree about where the section starts.

  Skipping a leading `uses` is not a detail: `implementation uses ugm;` is the
  ordinary spelling for an impl-private import, and a method body spliced in
  front of it produces a `uses` that is no longer the first thing in the
  section. }
var i, guard: Integer;
begin
  Result := -1;
  i := TokPos;
  while i < TokCount do
  begin
    if (Tokens[i].Kind = tkIdent) and
       CaseEqual(GetTokenStrFromRaw(Tokens[i].SOffset, Tokens[i].SLen), 'implementation') then
    begin
      Inc(i);   { past `implementation` }
      if (i < TokCount) and (Tokens[i].Kind = tkUses) then
      begin
        guard := 0;
        while (i < TokCount) and (Tokens[i].Kind <> tkSemicolon) and (guard < TokCount) do
        begin
          Inc(i);
          Inc(guard);
        end;
        if i < TokCount then Inc(i);   { past the `;` }
      end;
      Result := i;
      Exit;
    end;
    Inc(i);
  end;
end;

procedure FlushPendingClassSpecializations;
var p, gm, ti, si, anchor: Integer;
begin
  { A specialization written in a unit's INTERFACE cannot have its method bodies
    materialised where it stands: an interface section holds signatures, and a
    `procedure TFoo$LongInt.M; begin ... end;` spliced into one is
    `unexpected token in a unit interface section` -- reported against the
    TEMPLATE's file, because the streamed tokens carry the template's source
    offsets, so the diagnostic names a file whose text is fine.

    Only the CROSS-UNIT case reaches here in an interface, and the reason is the
    `GenericMethodCount > 0` gate on the pend above. When the template is in
    THIS unit its method bodies are still unparsed while the interface is being
    read, so nothing is pended and BufferGenericMethod materialises them later,
    from the implementation, once it has both halves. When the template came
    from a USED unit its methods are already buffered, the pend fires, and this
    flush runs inside the interface. Same-unit worked and cross-unit did not for
    exactly that reason -- and a fields-only template worked cross-unit too,
    because with no methods there is nothing to splice.
    bug-p-a-cross-unit-specialization-streams-method-bodies-into-the-interface }
  anchor := -1;
  if InInterface then anchor := UnitImplAnchor;
  for p := 0 to PendingSpecCount - 1 do
  begin
    ti := PendingSpecTi[p];
    si := PendingSpecIdx[p];
    SpecializeTemplateName := Templates[ti].Name;
    SetSpecSubs(ti, si);
    for gm := 0 to GenericMethodCount - 1 do
      if GenericMethods[gm].TemplateIdx = ti then
        if anchor >= 0 then
          { Advance the anchor by what each splice inserted, so several bodies
            keep their order instead of each landing in front of the last. }
          anchor := anchor + SpecializeStreamAt(GenericMethods[gm].TokStart,
                      GenericMethods[gm].TokCount, Specializations[si].Name, anchor)
        else
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
    { `try` and `asm` each close with an `end`, so a counter that knows only
      begin/case runs out of depth one `end` EARLY and hands back a SHORT body.
      The routine's own closing `end` is then left in the token stream, the unit
      loop's silent tkEnd arm eats it, and the unit terminates in the wrong
      place -- reported at EOF, for a defect anywhere above it.

      Both arms are MEASURED against the pinned binary, separately: a generic
      method containing `try`, and one containing `asm`, each alone.

      This set is deliberately NOT identical to PreScanSkipRoutineBody's
      (pasparser_proc.inc:324), which also counts tkRecord. That one scans from
      the routine HEADER and so walks the local declaration part; this one skips
      to the first `begin` (see the loop above) and starts counting after it, and
      Pascal has no record inside a statement part. tkRecord here would be a
      token that can never fire -- measured: a generic method with a local
      `type R = record ... end` compiles correctly on the PRE-FIX binary.
      bug-p-a-generic-method-body-with-try-loses-its-closing-end }
    if Tokens[cur].Kind in [tkBegin, tkCase, tkTry, tkAsm] then
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
    { Same opener set as GenericMethodBodyEnd -- see the note there. A generic
      FUNCTION's body has the same shapes as a method's.

      UNVERIFIED, and the reason is worth recording: no program reaches this
      miscount today. pxx rejects a `generic function` in a unit INTERFACE and
      in a unit IMPLEMENTATION alike, and those are the only places a short body
      could be mis-terminated; at program level the pre-fix binary is already
      correct. Corrected for consistency, with no positive control available.
      bug-p-a-generic-function-cannot-be-declared-in-a-unit }
    if Tokens[cur].Kind in [tkBegin, tkCase, tkTry, tkAsm] then Inc(depth)
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
