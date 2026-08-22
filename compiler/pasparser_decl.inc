{ ===== pasparser_decl.inc — Pascal frontend: declaration parsing ==============

  Carved out of pasparser_*.inc, byte-for-byte, by
  refactor-a-carve-out-plexer-pparser-so-p-owns-its-own-files.

  Owned by Track P (Pascal frontend). Included from compiler.pas at exactly the
  point it used to occupy, so include ORDER is unchanged — that is what makes
  the carve-out provable by the self-host fixedpoint rather than by reading it.

  Contents: type / const / var / label declarations, the type-name resolver, and
  the nested-routine (lambda-lifting) machinery that closes over their scopes.

  DO NOT factor anything here into a shared helper with pyparser.inc/cparser.inc.
  What is shared between frontends is the AST and the IR, never the parser:
  devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md }

{ ===== Declaration parsing ===== }

{ Parse the element spec of `set of <X>` — CurTok is the token after `of`.
  Records BOTH halves of the element identity in the LastTypeSet* globals:
  the enum id (or -1) and the element TTypeKind ordinal. Shared by the inline
  `var s: set of X` path and the named-alias `TS = set of X` path, which used
  to keep its own reduced copy that recorded ONLY the enum id — so a named
  `set of Char` or `set of 0..7` lost its element kind and `for c in cs` was
  refused with an error naming the very kinds it refused.
  bug-a-for-in-over-a-set-variable-refuses-the-kinds-its-error-message-claims }
procedure ParseSetElemSpec;
var elemTk: TTypeKind;
begin
  LastTypeEnumId := -1;
  if CurTok.Kind = tkInteger then
  begin
    { `set of <subrange>` e.g. `set of 1..10` — consume lo..hi (the element
      is an integer subrange). Without this the `..hi` leaked and the
      type-skip loop in ParseVarSection corrupted the variable's type away
      from tySet, so set ops/membership read garbage. }
    ConstEval;
    Expect(tkDotDot, '..');
    ConstEval;
    elemTk := tyInteger;
  end
  else
    elemTk := ParseTypeKind();
  { the element parse records the enum identity in LastTypeEnumId; carry it
    as the set's element enum for RTTI. }
  LastTypeSetEnumId := LastTypeEnumId;
  LastTypeSetElemTk := Ord(elemTk);
end;

procedure ParseEnumMembers(etid: Integer);
{ The member list of an enum type: CurTok is on '(' at entry, past ')' at exit.
  Lifted out of ParseTypeSection so the ANONYMOUS form (`var c: (red, green)`,
  legal wherever a type is expected) parses through the same code as the named
  one -- an enum with explicit ordinals, holes and scoping is not a grammar to
  keep two copies of.
  EnumTypeScoped[etid] must already be set by the caller: it is read from the
  token position of the '(' and an anonymous enum has no name to scope under. }
var ordinal, hiVal, enumNOff, enumNLen: Integer;
    enumNm: AnsiString;
    done: Boolean;
begin
  Next; ordinal := 0;
  done := False;
  while (CurTok.Kind = tkIdent) and not done do
  begin
    { Optional explicit ordinal: `(a = 1, b = 5, c)` -- a value sets the
      member's ordinal; the next valueless member continues from value+1
      (FPC semantics). }
    enumNOff := Tokens[TokPos-1].SOffset; enumNLen := Tokens[TokPos-1].SLen;
    enumNm := CurTok.SVal;
    Next;
    if CurTok.Kind = tkEq then
    begin
      Next;                 { consume '=' }
      hiVal := ordinal;     { the implicit next ordinal }
      ordinal := ConstEval; { explicit ordinal value }
      { A jump off the implicit 0..n-1 sequence makes the enum non-contiguous --
        for-in over the TYPE is then invalid (FPC, tforin20) and
        ordinal<->position no longer coincide. }
      if ordinal <> hiVal then EnumTypeHasHoles[etid] := True;
    end;
    AddEnumVal(enumNOff, enumNLen, ordinal);
    if not EnumTypeScoped[etid] then
      { An unscoped member is reachable as a bare name, and it used to become a
        plain Integer const -- so it arrived at an assignment carrying nothing but
        its ordinal, and `aColor := banana` silently stored TFruit's 1 as green
        (tenum4). Tag the const with its enum so the identity survives the lookup. }
      SymEnumId[AddConst(enumNm, tyInteger, ordinal)] := etid;
    Inc(ordinal);
    if not Eat(tkComma) then done := True;
  end;
  Expect(tkRParen, ')');
  EnumTypeValCount[etid] := EnumValCount - EnumTypeValBase[etid];
end;

function ParseTypeKind: TTypeKind;
var lo: AnsiString; elemTk: TTypeKind; aliasIdx, ci, tkQUnit: Integer;
    qtOuter, qtNested: Integer;   { `TOuter.TInner` — the nested-type lookup }
    tnHasAlias: Boolean;   { a source/RTL alias of this name beats every builtin name }
    childDepth, childBaseTk, childBaseRec: Integer;
    wasPacked: Boolean;
begin
  LastTypeRecId := REC_NONE;
  LastTypePointerElemTk := tyUnknown;
  LastTypePointerElemRec := REC_NONE;
  LastTypePointerAlias := -1;
  LastTypePointerDepth := 0;
  LastTypePointerBaseTk := Ord(tyUnknown);
  LastTypePointerBaseRec := REC_NONE;
  LastTypeProcSig := -1;
  LastTypeEnumId := -1;
  LastTypeStrCap := 0;
  LastTypeDynElemRowLen := 0; LastTypeDynElemRowLo := 0;
  LastTypeIsSub := False; LastTypeSubLo := 0; LastTypeSubHi := 0;
  case CurTok.Kind of
    tkLParen:
    begin
      { ANONYMOUS enum type -- `var c: (red, green, blue);`, a record field, an
        array element. Ordinary Pascal (ISO and FPC both take it); pxx rejected
        it with "unknown type" because the member-list grammar lived only in
        ParseTypeSection's naming path. Same shape as the anonymous record and
        anonymous procedural arms below: mint the unnamed backing and hand back
        the SAME TTypeKind + LastType* the named form produces, so AllocVar,
        the record-field walker and every consumer see no difference.
        Scoping is off by definition -- {$SCOPEDENUMS} makes members reachable
        only as `TName.member`, and there is no TName here. }
      LastTypeEnumId := RegisterEnumType(0, 0);
      EnumTypeScoped[LastTypeEnumId] := False;
      ParseEnumMembers(LastTypeEnumId);
      Result := tyInteger;   { enums are ordinal/integer-sized at codegen }
      Exit;
    end;
    tkInteger, tkMinus, tkString:
    begin
      { ANONYMOUS ordinal subrange -- `var n: 1..5;`, `array[0..2] of 1..5`,
        `record f: 'a'..'z'; end`. Modelled exactly like the NAMED form in
        ParseTypeSection: an alias to the base ordinal (tyChar for a
        char-literal bound, else tyInteger) with the bounds RETAINED, so {$R+}
        checks stores against them and Low/High answer the subrange rather
        than the base type. The named path's own comment claimed this was
        "the same treatment as an inline `var x: lo..hi` subrange" -- it was
        aspirational, there was no inline form. }
      if CurTok.Kind = tkString then Result := tyChar else Result := tyInteger;
      LastTypeSubLo := ConstEval;      { low bound }
      Expect(tkDotDot, '..');
      LastTypeSubHi := ConstEval;      { high bound }
      LastTypeIsSub := True;
      Exit;
    end;
    tkRecord, tkPacked:
    begin
      { Anonymous inline record type literal — `var x: record ... end;`,
        legal ISO/FPC anywhere a type is expected
        (feature-anonymous-record-type). Mint an unnamed UCls row
        (AddUClass(0,0), the EnsureMethodPtrRec precedent) and parse the
        fields with the shared named-record field parser. `packed` reaching
        here must introduce a record (`packed array` never routed through
        ParseTypeKind before either). }
      wasPacked := CurTok.Kind = tkPacked;
      if wasPacked then
      begin
        Next;
        Expect(tkRecord, 'record');
      end
      else
        Next;
      ci := AddUClass(0, 0);
      UClsParent[ci] := -1;
      UClsIsRecord[ci] := True;
      ParseRecordFields(ci, wasPacked);
      LastTypeRecId := REC_UCLASS_BASE + ci;
      Result := tyRecord;
      Exit;
    end;
    tkProcedure, tkFunction:
    begin
      { ANONYMOUS procedural type — `cb: procedure(l: LongInt)` written inline,
        as a record field, a var, a parameter or an array element, with no named
        alias. Ordinary Pascal, and FPC takes it; pxx rejected it outright
        because the grammar lived only in ParseTypeSection's naming path.
        Same shape as the anonymous inline record arm above: parse it here, mint
        the unnamed backing (a body-less Procs[] signature, the AddUClass(0,0)
        analogue), and hand back the same TTypeKind + LastType* the named alias
        would have produced — so every consumer (AllocVar, the record-field
        walker, the call sites gating on SymProcSig) sees no difference between
        the inline form and the aliased one.
        bug-a-an-anonymous-procedural-type-is-not-accepted }
      aliasIdx := ParseProcTypeSignature;
      if CurTok.Kind = tkOf then
      begin
        { `of object` — a method pointer: a 16-byte {Code,Data} value, so the
          type kind is the shared method-pointer RECORD, exactly as
          RegisterMethodPtrTypeAlias sets it for the named form. }
        Next;
        if CurTok.Kind = tkIdent then Next;   { consume `object` }
        EatProcTypeCdecl(aliasIdx);
        LastTypeRecId := EnsureMethodPtrRec;
        LastTypeProcSig := aliasIdx;
        Result := tyRecord;
      end
      else
      begin
        { a plain procedural value is a code address — the pointer alias shape
          RegisterProcTypeAlias uses (tyPointer, depth 1, unknown pointee). }
        EatProcTypeCdecl(aliasIdx);
        LastTypePointerDepth := 1;
        LastTypeProcSig := aliasIdx;
        Result := tyPointer;
      end;
      Exit;
    end;
    tkCaret:
    begin
      Next;
      Inc(PtrElemDepth);          { a forward element name is legal here — see PtrElemDepth }
      elemTk := ParseTypeKind();
      Dec(PtrElemDepth);
      childDepth := LastTypePointerDepth;
      childBaseTk := LastTypePointerBaseTk;
      childBaseRec := LastTypePointerBaseRec;
      LastTypePointerElemTk := elemTk;
      LastTypePointerElemRec := LastTypeRecId;
      if (elemTk = tyPointer) and (childDepth > 0) then
      begin
        LastTypePointerDepth := childDepth + 1;
        LastTypePointerBaseTk := childBaseTk;
        LastTypePointerBaseRec := childBaseRec;
      end
      else
      begin
        LastTypePointerDepth := 1;
        LastTypePointerBaseTk := Ord(elemTk);
        LastTypePointerBaseRec := LastTypeRecId;
      end;
      Result := tyPointer;
      Exit;
    end;
    tkInteger_T:
    begin
      lo := CurTok.SVal;
      if CaseEqual(lo, 'shortint') then Result := tyInt8
      else if CaseEqual(lo, 'byte') then Result := tyUInt8
      else if CaseEqual(lo, 'smallint') then Result := tyInt16
      else if CaseEqual(lo, 'word') then Result := tyUInt16
      else if CaseEqual(lo, 'longint') then Result := tyInt32
      else if CaseEqual(lo, 'cardinal') then Result := tyUInt32
      else Result := tyInteger; { Integer }
    end;
    tkLongWord_T: Result := tyUInt32;
    tkBoolean_T: Result := tyBoolean;
    tkChar_T:    Result := tyChar;
    tkString_T:
      { Bare `string`: per-use promotion to managed AnsiString for AGGREGATE
        ELEMENTS only (the token right before `string` is `of`, as in `array of
        string` / `array[..] of string`), in managed-string mode (the default).
        A frozen `string` element is huge inline and can't be a dynarray element,
        so promoting it to a managed handle is what makes `array of string` work
        (bug-string-type-size-mismatch / the PCL list controls). SCALAR `string`
        stays frozen so Str/Val and other frozen-buffer builtins keep working
        (the full string-model arc / tyFixedString handles the rest). `string[N]`
        stays a frozen fixed-length string. }
      if (Tokens[TokPos].Kind = tkLBrack) then
      begin
        { `string[N]` -> frozen fixed-length string (tyFixedString: NativeInt
          length word + N chars, capacity N). We consume our own `[N]` here, so
          Exit before the trailing Next that the simple cases rely on. }
        Next;                          { consume `string` }
        Expect(tkLBrack, '[');
        LastTypeStrCap := ConstEval;
        Expect(tkRBrack, ']');
        Result := tyFixedString;
        Exit;
      end
      else if PasDefineExists('PXX_MANAGED_STRING') then
        { Scalar bare `string` -> managed AnsiString (slice 4p2: managed is the
          default string model). `string[N]`/`shortstring` stay frozen
          tyFixedString; `-uPXX_MANAGED_STRING` keeps everything frozen tyString. }
        Result := tyAnsiString
      else
        Result := tyString;
    tkReal_T:     if (TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32) then Result := tySingle else Result := tyDouble;
    tkSingle_T:   Result := tySingle;
    tkDouble_T:   Result := tyDouble;
    tkExtended_T: Result := tyDouble;   { Extended aliases Double — see below }
    else
    begin
      lo := CurTok.SVal;
      { Unit-qualified type reference — `sockets.Tin6_addr` (Synapse's
        `TInAddr6 = sockets.Tin6_addr`). Strip the qualifier and resolve the
        member name like a bare type; ConsumeUnitQualifier consumes nothing
        when the prefix is not a compiled unit. Types live in one global
        table, so the qualifier only disambiguates the parse, not the lookup. }
      tkQUnit := -1;
      if (CurTok.Kind = tkIdent) then tkQUnit := ConsumeUnitQualifier(lo);
      if PxxDbgEnabled('a.qual') then WriteLn('PXXDBG a.qual TYPEARM lo=', lo, ' qunit=', tkQUnit,
        ' foa_su=', FindUnitOrAlias('sysutils'), ' foa_py=', FindUnitOrAlias('pylib'),
        ' inunit=', FindUClassInUnit(lo, tkQUnit), ' flat=', FindUClass(lo));
      { lo is now the member name; CurTok sits on it. The unit index is KEPT —
        it used to be dropped on the floor because "types live in one global
        table, so the qualifier only disambiguates the parse, not the lookup".
        That invariant holds only while no two units declare a class of the same
        name, which stops being true the moment sysutils and pylib each declare
        their own `Exception`. Kept and threaded to the class lookup below so
        `var e: sysutils.Exception` means what it says. }

      { CLASS-qualified type reference — `TTest.TRecord`, a type nested inside a class
        body (`TTest = class public type TRecord = record ... end; end;`). A nested type
        section is already parsed and its members registered, but as GLOBAL aliases under
        their BARE name (pxx does not scope class-local types — see the class-body `type`
        branch), so `TRecord` resolved and the qualified spelling did not. Strip the class
        qualifier and resolve the member name, exactly as the unit-qualified path above
        does: the qualifier disambiguates the parse, not the lookup. (tdefault8) }
      if (CurTok.Kind = tkIdent) and (FindUClass(lo) >= 0) and
         (TokPos < TokCount) and (Tokens[TokPos].Kind = tkDot) and
         (TokPos + 1 < TokCount) and (Tokens[TokPos + 1].Kind = tkIdent) then
      begin
        qtOuter := FindUClass(lo);
        Next;                 { past the class name — CurTok is now '.' }
        Next;                 { past '.'            — CurTok is now the nested type name }
        lo := CurTok.SVal;
        { …and when THAT class declares a nested type of this name, the qualifier
          does not merely disambiguate the parse — it picks which type is meant.
          Two classes may each declare `TInner`, and only the first keeps the bare
          name, so stripping the qualifier and looking the bare name up bound
          `tother.tinner` to touter's — silently, since both are classes and the
          wrong one simply lacks the fields.
          bug-a-duplicate-class-name-check-is-scope-blind }
        qtNested := FindNestedType(qtOuter, lo);
        if qtNested >= 0 then
          lo := GetTokenStrFromRaw(UClsNOff[qtNested], UClsNLen[qtNested]);
        { `tthree.tmid.tleaf` — nesting goes deeper than one level, and this
          consumed exactly one qualifier, so a doubly-nested type could be
          declared and implemented but never NAMED ("unknown type"). Keep
          descending while the next qualifier is itself a nested type of the one
          just resolved; a non-nested member stops the walk and is left to the
          paths below, so an ordinary `TClass.TMember` is unaffected.
          bug-p-a-nested-class-method-implementation-takes-only-one-qualifier }
        while (qtNested >= 0) and
              (TokPos < TokCount) and (Tokens[TokPos].Kind = tkDot) and
              (TokPos + 1 < TokCount) and (Tokens[TokPos + 1].Kind = tkIdent) and
              (FindNestedType(qtNested, GetTokenStr(TokPos + 1)) >= 0) do
        begin
          qtOuter := qtNested;
          Next;               { past the nested type name — CurTok is now '.' }
          Next;               { past '.' — CurTok is the next nested type name }
          lo := CurTok.SVal;
          qtNested := FindNestedType(qtOuter, lo);
          lo := GetTokenStrFromRaw(UClsNOff[qtNested], UClsNLen[qtNested]);
        end;
      end;
      if CaseEqual(lo, 'set') then
      begin
        Next;
        Expect(tkOf, 'of');
        ParseSetElemSpec;
        Result := tySet;
        Exit;
      end;
      { EVERY builtin type NAME below is skipped when a source/RTL alias of that name exists. The
        chain used to run BEFORE the alias table (which is only reached in its final else), so a
        builtin silently WON over a source declaration -- latent for widechar/tdatetime because nobody
        redeclares them, and fatal for PWord, which this compiler declares as ^NativeInt. Guarding each
        branch (rather than reordering) can only ever make an alias WIN, never the reverse: the class,
        record and alias handling in the final else stays reachable exactly as before. See b303/b304. }
      tnHasAlias := FindTypeAlias(lo) >= 0;
      if (not tnHasAlias) and (CaseEqual(lo, 'textfile') and (IsRecordType('text') <> REC_NONE)) then
      begin
        { FPC: TextFile = Text. Resolve to the RTL `text` record — previously
          the unknown name fell through to a 4-byte integer slot. }
        LastTypeRecId := IsRecordType('text');
        Result := tyRecord;
      end
      else if (not tnHasAlias) and (CaseEqual(lo, 'file')) then
        { untyped `file` / `file of T`: no file-variable model in pxx (the
          textfile RTL covers Text I/O). Reject at the type reference instead
          of silently minting an integer-sized slot
          (bug-pascal-missing-diagnostics-fail-tests / tdefault4). }
        Error('file types are not supported (use TextFile for text I/O)')
      else if (not tnHasAlias) and (CaseEqual(lo, 'ansistring') or
         CaseEqual(lo, 'unicodestring') or CaseEqual(lo, 'widestring')) then
      begin
        { unicodestring/widestring: pragmatic alias to the native string type
          (byte semantics). FPC's UTF-16 payload model is a later slice; the
          alias gives literals/writeln/compare/case-of/indexing string
          behavior instead of a bare machine word
          (bug-pascal-unicodestring-widestring-type-missing). }
        if PasDefineExists('PXX_MANAGED_STRING') then
          Result := tyAnsiString
        else
          Result := tyString;
      end
      else if (not tnHasAlias) and (CaseEqual(lo, 'shortstring')) then
      begin
        { Interim: `shortstring` maps to a 255-cap tyFixedString (word-prefix
          layout, so sizing matches the reused frozen codegen). The true
          byte-length-prefix tyShortString (FPC ABI) is a later codegen slice. }
        LastTypeStrCap := 255;
        Result := tyFixedString;
      end
      else if (not tnHasAlias) and (CaseEqual(lo, 'real')) then
      begin
        if (TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32) then
          Result := tySingle  { Real = native float depth; ESP has no HW double }
        else
          Result := tyDouble;
      end
      else if (not tnHasAlias) and (CaseEqual(lo, 'single')) then Result := tySingle
      else if (not tnHasAlias) and (CaseEqual(lo, 'double')) then Result := tyDouble
      else if (not tnHasAlias) and (CaseEqual(lo, 'extended')) then Result := tyDouble
        { Extended aliases Double (feature-extended-alias-or-reject, option a):
          arithmetic already ran in SSE2 double; the 10-byte x87 tyExtended
          storage gave no extra precision, so `Extended` is now plain Double on
          every target. The tyExtended enum + its x87 load/store paths remain but
          are no longer produced by the front end. }
      { The Int8/16/32 spellings were MISSING while UInt8/16/32 were present, so they
        fell through to the unknown-name default and silently became a 4-byte Integer —
        harmless for Int32 by luck, wrong for Int8/Int16 (4 bytes instead of 1/2, which
        also mislays any record they sit in). The compiler's own source uses Int32. }
      { `Char` is a lexer TOKEN, so its FPC synonym `AnsiChar` never resolved as an
        identifier and fell through to the unknown-name default — a 4-byte Integer where a
        1-byte char belongs, which also mislays any record or array it sits in. }
      else if (not tnHasAlias) and (CaseEqual(lo, 'ansichar')) then Result := tyChar
      { FPC's sized booleans, used by real bindings (Synapse). These are C-ABI booleans —
        a fixed-width integer where nonzero means true — so they must keep their WIDTH:
        LongBool is 4 bytes, WordBool 2, ByteBool 1. Mapping them onto tyBoolean would
        silently change their size and corrupt any struct or call that crosses to C. }
      else if (not tnHasAlias) and (CaseEqual(lo, 'longbool')) then Result := tyInteger
      else if (not tnHasAlias) and (CaseEqual(lo, 'wordbool')) then Result := tyUInt16
      else if (not tnHasAlias) and (CaseEqual(lo, 'bytebool')) then Result := tyUInt8
      { More System names that were never recognised. Until the unknown-name fallback was
        closed they were all silently 4-byte Integers, which for TDateTime (a Double!) and
        for the string aliases was badly wrong, not merely mis-sized. A user or RTL
        declaration still wins — FindTypeAlias is consulted before this. TDateTime and
        Currency deliberately match what lib/rtl/sysutils already declares them as. }
      else if (not tnHasAlias) and (CaseEqual(lo, 'widechar')) then Result := tyWideChar  { 2 bytes, not 4 }
      { UCS4Char — FPC's own name for a CODE POINT (system unit: UCS4Char = type
        LongWord). Distinct from WideChar above it, which is a UTF-16 code UNIT
        and cannot hold a character past the BMP without a surrogate pair. Its
        own kind because it converts to a string as UTF-8; see defs.inc. }
      else if (not tnHasAlias) and (CaseEqual(lo, 'ucs4char') or CaseEqual(lo, 'unicodechar')) then Result := tyUCS4Char
      else if (not tnHasAlias) and (CaseEqual(lo, 'comp')) then Result := tyInt64
      { ValReal — FPC's "widest available real". pxx's widest is Double. }
      else if (not tnHasAlias) and (CaseEqual(lo, 'valreal')) then Result := tyDouble
      else if (not tnHasAlias) and (CaseEqual(lo, 'tdatetime')) then Result := tyDouble
      else if (not tnHasAlias) and (CaseEqual(lo, 'currency')) then Result := tyDouble
      else if (not tnHasAlias) and (CaseEqual(lo, 'sizeint')) then Result := tyNativeInt
      else if (not tnHasAlias) and (CaseEqual(lo, 'sizeuint')) then Result := tyNativeUInt
      else if (not tnHasAlias) and (CaseEqual(lo, 'utf8string') or CaseEqual(lo, 'rawbytestring')) then Result := tyAnsiString
      else if (not tnHasAlias) and (CaseEqual(lo, 'olevariant')) then Result := tyVariant
      else if (not tnHasAlias) and (CaseEqual(lo, 'pwidechar')) then
      begin
        { tyWideChar, not tyUInt16 — the element of a PWideChar IS a WideChar,
          and `WriteLn(p^)` printed the ordinal for exactly as long as this said
          otherwise. Found by grepping for the sibling arm of
          bug-a-writeln-of-a-widechar-prints-its-ordinal, per
          normalise-dont-special-case. Width is unchanged (TypeSize 31 = 2), so
          pointer arithmetic still steps by two bytes. }
        LastTypePointerElemTk := tyWideChar;
        Result := tyPointer;
      end
      { The built-in pointer names — PInteger, PByte, PDouble, ...

        The FindTypeAlias test is EXPLICIT and load-bearing. The comment above claims the alias
        table is consulted before this chain; it is NOT — the chain runs first, and every name in
        it therefore shadows a source declaration of the same name. For `widechar`/`tdatetime`
        that is latent (nobody redeclares them). For the P-names it is fatal: this compiler
        declares `PWord = ^NativeInt` (the machine word), and a builtin `PWord = ^UInt16`
        silently re-types it — `pw^` then reads two bytes instead of eight. Caught here by a test
        that declared its own PWord; the self-host gate did NOT catch it, so do not rely on that
        alone.

        (The chain's ordering is wrong in general and should be fixed at the top rather than
        per-name — filed as bug-pascal-builtin-typename-shadows-source-alias.) }
      else if (not tnHasAlias) and (BuiltinPtrNameElemTk(lo) <> tyUnknown) then
      begin
        LastTypePointerElemTk := BuiltinPtrNameElemTk(lo);
        LastTypePointerElemRec := REC_NONE;
        Result := tyPointer;
      end
      { The keyword-token builtins by NAME: the real lexer always tokenizes
        these as tkBoolean_T/tkInteger_T/…, so this arm is only reached by a
        SYNTHETIC token stream that spells them as plain identifiers — the
        parallel-for capture accessor (`capj: ^Boolean` built via NestStrOff)
        being the one in-tree producer. Without the mapping the caret element
        type silently defaulted, so a captured Boolean deref re-typed as
        Integer and overload resolution rejected `Sink(i, lflag)`
        (bug-parallel-for-captured-boolean-loses-type). }
      else if (not tnHasAlias) and (CaseEqual(lo, 'boolean')) then Result := tyBoolean
      else if (not tnHasAlias) and (CaseEqual(lo, 'integer')) then Result := tyInteger
      else if (not tnHasAlias) and (CaseEqual(lo, 'char')) then Result := tyChar
      else if (not tnHasAlias) and (CaseEqual(lo, 'single')) then Result := tySingle
      else if (not tnHasAlias) and (CaseEqual(lo, 'double')) then Result := tyDouble
      else if (not tnHasAlias) and (CaseEqual(lo, 'shortint') or CaseEqual(lo, 'int8')) then Result := tyInt8
      else if (not tnHasAlias) and (CaseEqual(lo, 'byte') or CaseEqual(lo, 'uint8')) then Result := tyUInt8
      else if (not tnHasAlias) and (CaseEqual(lo, 'smallint') or CaseEqual(lo, 'int16')) then Result := tyInt16
      else if (not tnHasAlias) and (CaseEqual(lo, 'word') or CaseEqual(lo, 'uint16')) then Result := tyUInt16
      else if (not tnHasAlias) and (CaseEqual(lo, 'longint') or CaseEqual(lo, 'int32')) then Result := tyInt32
      else if (not tnHasAlias) and (CaseEqual(lo, 'cardinal') or CaseEqual(lo, 'longword') or CaseEqual(lo, 'uint32') or CaseEqual(lo, 'dword')) then Result := tyUInt32
      else if (not tnHasAlias) and (CaseEqual(lo, 'int64')) then Result := tyInt64
      else if (not tnHasAlias) and (CaseEqual(lo, 'qword') or CaseEqual(lo, 'uint64')) then Result := tyUInt64
      else if (not tnHasAlias) and (CaseEqual(lo, 'nativeint') or CaseEqual(lo, 'ptrint')) then Result := tyNativeInt
      else if (not tnHasAlias) and (CaseEqual(lo, 'nativeuint') or CaseEqual(lo, 'ptruint')) then Result := tyNativeUInt
      else if (not tnHasAlias) and
              (CaseEqual(lo, 'pointer') or CaseEqual(lo, 'codepointer')) then Result := tyPointer
      else if (not tnHasAlias) and (CaseEqual(lo, 'object')) then
      begin
        { `object`: a rooted object reference — holds ANY class instance
          (pointer-sized, VMT at offset 0), no specific class bound. Modelled
          like the metaclass aliases: a tyPointer whose element is tyClass with
          no class id (PtrElemRec stays REC_NONE — "some object"). Assignable
          from any class reference; member access needs an explicit cast to a
          concrete class (`TFoo(o).M`), which errors naturally on the bare
          pointer. The tyClass element tag is what RTTI/tools key off to tell
          it from a raw Pointer. NOT legacy Object Pascal's value-`object`
          (record-with-methods); that syntax was never supported here.
          See feature-object-reference-type. }
        LastTypePointerElemTk := tyClass;
        Result := tyPointer;
      end
      else if (not tnHasAlias) and (CaseEqual(lo, 'pchar') or CaseEqual(lo, 'pansichar')) then
      begin
        LastTypePointerElemTk := tyChar;
        Result := tyPointer;
      end
      else if (not tnHasAlias) and (CaseEqual(lo, 'variant')) then Result := tyVariant
      { PROMOTABLE INT (feature-a-promotable-int). Opt-in and explicitly typed,
        so no existing Pascal program changes behaviour by naming nothing.
        `PromoInt` picks the target's default storage class; the numbered names
        pin a class explicitly, and the number IS the usable inline width. }
      else if (not tnHasAlias) and (CaseEqual(lo, 'promoint') or CaseEqual(lo, 'promoint32')
                                    or CaseEqual(lo, 'promoint64')) then
      begin
        { PromoInt32 is reserved but not yet declarable: its arithmetic would
          have to trap in 32-bit width, and the backend's overflow check only
          covers 64-bit ops today (bug-a-qplus-misses-32bit-overflow). Shipping
          it now would mean a promotable int that silently wraps at 2^31 — the
          precise defect this type removes. Blocked, not faked. }
        if CaseEqual(lo, 'promoint32') then Result := tyPromoInt32
        else if CaseEqual(lo, 'promoint64') then Result := tyPromoInt64
        else Result := PromoIntDefaultKind;
        { The numbered spellings ASSERT the target's native width rather than
          offering a narrower class on a wider host: the slot is two machine
          words by definition, so PromoInt32 on a 64-bit target is not a thing
          that exists. PromoInt is the portable spelling. }
        if Result <> PromoIntDefaultKind then
          Error('this target''s promotable int is native-word sized; the other '
                + 'numbered spelling does not exist here — write PromoInt');

      end
      else if (not tnHasAlias) and (EnableAutoVar and CaseEqual(lo, 'auto')) then Result := tyAuto
      else
      begin
        { `Text`/`TextFile` resolve here as the record from the implicitly-loaded
          textfile unit (loaded up front in ParseProgram when a Text token is
          present), so no special-case is needed at this point. }
        ci := -1;
        if tkQUnit >= 0 then ci := FindUClassInUnit(lo, tkQUnit);
        if ci < 0 then ci := FindUClass(lo);
        if (ci >= 0) and UClsIsInterface[ci] then
        begin
          { Interface-typed variable: a 16-byte fat pointer {IMT, instance}.
            Modelled as a tyRecord whose rec id is the interface's UCls entry. }
          LastTypeRecId := REC_UCLASS_BASE + ci;
          Result := tyRecord;
        end
        else if IsClassType(lo) then
        begin
          ci := -1;
          if tkQUnit >= 0 then ci := FindUClassInUnit(lo, tkQUnit);
          if ci < 0 then ci := FindUClass(lo);
          if ci >= 0 then
            LastTypeRecId := REC_UCLASS_BASE + ci
          else
            LastTypeRecId := REC_NONE;
          Result := tyClass;
        end
        else
        begin
          LastTypeRecId := IsRecordType(lo);
          { A user `type X = ...` alias SHADOWS a same-named builtin record. The
            compiler exposes internal descriptor records (TProc, TParam, ...) under
            common names; a user program defining e.g. `type TProc = procedure(...)`
            must get its own type, not the builtin (FPC does not reserve these).
            Only triggers when both a record-name match and a user alias exist —
            which in valid source is exactly the user-alias-vs-builtin case. }
          if (LastTypeRecId <> REC_NONE) and (FindTypeAlias(lo) < 0) then
            Result := tyRecord
          else
          begin
            aliasIdx := FindTypeAlias(lo);
            if aliasIdx >= 0 then
            begin
              if AliasTk[aliasIdx] = Ord(tySet) then
              begin
                { Named set type: element enum kept in AliasElemTk but not
                  exposed as LastTypeEnumId, so the property kind stays SET.
                  Expose it as LastTypeSetEnumId for RTTI typeRef. }
                LastTypeSetEnumId := AliasElemTk[aliasIdx];
                LastTypeSetElemTk := AliasSetElemTk[aliasIdx];
                Result := tySet;
              end
              else if AliasTk[aliasIdx] = Ord(tyPointer) then
              begin
                LastTypePointerElemTk := IntToTypeKind(AliasElemTk[aliasIdx]);
                LastTypePointerElemRec := AliasElemRec[aliasIdx];
                { The alias may still be an unresolved FORWARD (`PNode = ^TNode` ahead
                  of TNode): its element is REC_NONE right now and only
                  ResolvePendingPointerAliases fills it in. Record which alias this was
                  so a field declared here can be re-read then. }
                LastTypePointerAlias := aliasIdx;
                LastTypePointerDepth := AliasPtrDepth[aliasIdx];
                LastTypePointerBaseTk := AliasPtrBaseTk[aliasIdx];
                LastTypePointerBaseRec := AliasPtrBaseRec[aliasIdx];
                LastTypeProcSig := AliasProcSig[aliasIdx];
                Result := tyPointer;
              end
              else
              begin
                LastTypeRecId := AliasElemRec[aliasIdx];
                LastTypeProcSig := AliasProcSig[aliasIdx];  { method-pointer record carries a call signature }
                { …and a frozen-string alias hands back its capacity, so Alloc*
                  stamps SymStrCap and the store clamps at N }
                if AliasStrCap[aliasIdx] > 0 then
                  LastTypeStrCap := AliasStrCap[aliasIdx];
                if AliasIsSub[aliasIdx] then
                begin
                  { named subrange: hand the retained bounds to Alloc* for
                    {$R+} store checks (feature-pascal-range-checks-r-plus). }
                  LastTypeIsSub := True;
                  LastTypeSubLo := AliasSubLo[aliasIdx];
                  LastTypeSubHi := AliasSubHi[aliasIdx];
                end;
                Result := IntToTypeKind(AliasTk[aliasIdx]);
              end;
            end
            else
            begin
              LastTypeEnumId := FindEnumType(lo);
              if (LastTypeEnumId < 0) and CaseEqual(lo, 'tclass') then
              begin
                { TClass — a class REFERENCE (metaclass). It was never recognised, so it
                  fell through to tyInteger: `var c: TClass` was a 4-byte int and a class
                  reference stored in it TRUNCATED. In pxx a class reference is the
                  address of the class RTTI blob, so it is pointer-sized with a tyClass
                  element, exactly like the TObject row below. A user-declared TClass
                  still wins (IsClassType / FindTypeAlias are checked before here). }
                LastTypePointerElemTk := tyClass;
                Result := tyPointer;
              end
              else if (LastTypeEnumId < 0) and CaseEqual(lo, 'tobject') then
              begin
                { Builtin root class with no user TObject row (a user-declared
                  TObject won via IsClassType above): same rooted object
                  reference as `object` — pointer-sized, elem tyClass. It used
                  to fall through to tyInteger, silently TRUNCATING every
                  `Sender: TObject` param to 32 bits
                  (bug-tobject-param-truncated-32bit). }
                LastTypePointerElemTk := tyClass;
                Result := tyPointer;
              end
              else if LastTypeEnumId >= 0 then
                Result := tyInteger   { enums are ordinal/integer-sized at codegen }
              else if PtrElemDepth > 0 then
                { A `^` ELEMENT may name a type that does not exist yet — `PNode = ^TNode;`
                  before TNode is the classic forward reference, and
                  ResolvePendingPointerAliases fixes the element up afterwards, BY NAME.
                  This is the one case the old catch-all fallback ever legitimately served. }
                Result := tyInteger
              else if FindCTypedef(lo) >= 0 then
                { A C-imported typedef (`typedef void* PGtkWidget;`) lives in the C
                  typedef table, which the Pascal type lookups above do not consult. The
                  NAME is known, so this is not the silent-typo hazard — but note the
                  result is still tyInteger, which for a POINTER typedef is the very
                  truncation this fallback is famous for. Giving C typedefs their real
                  Pascal type is a separate fix (bug-c-typedef-not-a-pascal-type); this
                  only stops the strict check from rejecting a name that IS declared. }
                Result := tyInteger
              else if FindArrayType(lo) >= 0 then
                { A named ARRAY type (`TByteArray = array of Byte`) lives in its own table,
                  not the alias table, so it does not resolve above. Callers that can take
                  an array (var/field/return type) look it up themselves; ParseTypeKind
                  only has to not reject it. The NAME is known, so this is not the
                  silent-typo hazard the catch-all was. }
                Result := tyInteger
              else
                { Everywhere else an unknown name used to land on tyInteger too, silently
                  becoming a 4-byte Integer. That was a trap, not a tolerance: `var x:
                  Integr;` (a typo) compiled; a pointer type the source never declared
                  became a 32-bit int and TRUNCATED every address stored through it; and
                  `absolute` was swallowed whole, its target name parsed as a "type". It is
                  the hole bug-tobject-param-truncated-32bit came through — that fix patched
                  the one symptom (TObject, just above), and the hole went on to produce
                  TClass, Int8/Int16 and `absolute`. Closed here. }
                Error('unknown type: ' + lo);
            end;
          end;
        end;
      end;
    end;
  end;
  Next;
end;

{ ---------------------------------------------------------------------------
  DECLARATION TYPE DESCRIPTOR — parse a type once, allocate N symbols from it.

  `var x, y: T` and `class var x, y: T` need the same two steps, in this order:
  read a type, then reserve storage per name. Before this they each had their
  own copy, and the class-var copy was the two-liner `ParseTypeKind + AllocVar`,
  which cannot express an array at all: an inline `array[0..3] of Integer` died
  as `unknown type: array`, and a NAMED array type reached AllocVar as a scalar,
  so it indexed correctly but `Length()` answered garbage with NO diagnostic
  (bug-p-a-class-var-takes-no-array-type-and-a-named-one-is-silently-a-scalar).

  Copying a slice of ParseVarSection into the class-var branch would have made a
  fifth copy of array-declaration parsing in this file — and wall 18 of the
  generics corpus was exactly that disease one level down: four inline copies of
  the array-BOUND parser, one of which stayed broken after the other three were
  fixed. So the split is by RESPONSIBILITY instead:

    ParseDeclTypeDesc      consumes the type tokens, fills the VD* descriptor,
                           and makes no storage decision whatsoever;
    AllocFromDeclTypeDesc  turns that descriptor into exactly one symbol and
                           reads no tokens.

  Neither knows who is asking. Record fields and class fields are the next two
  callers to fold in — add a THIRD caller, never a third copy
  (devdocs/dev/normalise-dont-special-case.md).

  The LastType* globals stay the side channel they already were (record id,
  pointer element, proc signature, enum id, set element). They are live from the
  parse to the alloc, so a caller must keep that window free of any other type
  parsing — which is what every caller already did, since the alloc immediately
  follows. The VD* descriptor is a global for the same reason and with the same
  rule: fill it, consume it, do not nest. }
procedure ParseDeclTypeDesc;
var ai, di, dLo, dHi, flatLen: Integer;
    moreDims, elemResolved: Boolean;
begin
    VDIsArr := False; VDIsDyn := False; VDArrLo := 0; VDArrHi := 0; VDElemTk := tyInteger;
    elemResolved := False; VDElemDynDepth := 0;
    VDElemRowLen := 0; VDElemRowLo := 0;
    VDElemProcSig := -1;
    VDIsArrND := False; VDNdCnt := 0;
    ai := -1;
    if CurTok.Kind = tkIdent then ai := FindArrayType(CurTok.SVal);
    if ai >= 0 then
    begin
      { Variable of a named array type. }
      VDIsArr := True;
      VDElemTk := IntToTypeKind(ArrTypeElemTk[ai]); VDTk := VDElemTk;
      LastTypeRecId := ArrTypeElemRec[ai];
      LastTypePointerElemRec := ArrTypePtrElemRec[ai];
      { The alias records its frozen-string element width; LastTypeStrCap here
        is whatever the last unrelated `string[N]` anywhere left behind. }
      if (VDElemTk = tyFixedString) or (VDElemTk = tyShortString) then
        LastTypeStrCap := ArrTypeElemStrCap[ai];
      if ArrTypeIsDyn[ai] then
      begin
        { dynamic-array alias -> AllocDynArray below }
        VDIsDyn := True; VDDynDepth := ArrTypeDynDepth[ai];
        { alias whose element is a named FIXED array: thread the row shape to
          AllocDynArray below (via LastTypeDynElemRowLen at the call). }
        VDElemRowLen := ArrTypeElemRowLen[ai];
        VDElemRowLo  := ArrTypeElemRowLo[ai];
      end
      else
      begin
        VDArrLo := ArrTypeLo[ai]; VDArrHi := ArrTypeHi[ai];
        if ArrTypeNDims[ai] >= 2 then
        begin
          VDIsArrND := True; VDNdCnt := ArrTypeNDims[ai];
          for di := 0 to VDNdCnt - 1 do
          begin
            VDNdDimLo[di]   := ArrTypeDimLo[ai * MAX_ARR_DIMS + di];
            VDNdDimSpan[di] := ArrTypeDimSpan[ai * MAX_ARR_DIMS + di];
          end;
        end;
      end;
      Next; { consume the type name }
    end
    else if (CurTok.Kind = tkArray) or
            ((CurTok.Kind = tkPacked) and (TokPos < TokCount) and
             (Tokens[TokPos].Kind = tkArray)) then
    begin
      { `packed` on an array only affects ELEMENT padding, and pxx already lays
        elements out contiguously — so accept it and parse the array as usual
        (same rule as the record-field path). }
      if CurTok.Kind = tkPacked then Next;
      VDIsArr := True; Next;
      if CurTok.Kind = tkLBrack then
      begin
        { One or more comma-separated dimensions: `array[a..b, c..d, ...] of T`.
          An anonymous nested fixed array (`array[a] of array[b] of T`) has the
          SAME layout as `array[a,b] of T` in FPC, so merge the inner dims into
          the outer list. 1 dimension is an ordinary array; >=2 flattens to 1-D
          (N-D indexing via BuildFlatNDIndex). }
        VDNdCnt := 0;
        moreDims := True;
        while moreDims do
        begin
          Next;   { consume '[' }
          repeat
            ParseArrayDimBounds(dLo, dHi);
            if VDNdCnt >= MAX_ARR_DIMS then Error('too many array dimensions');
            VDNdDimLo[VDNdCnt] := dLo; VDNdDimSpan[VDNdCnt] := dHi - dLo + 1; Inc(VDNdCnt);
          until not Eat(tkComma);
          Expect(tkRBrack, ']');
          Expect(tkOf, 'of');
          { Continue only for a FIXED nested array (`array [`), not a dynamic
            `array of` element or a scalar/record element type. }
          moreDims := (CurTok.Kind = tkArray) and (Tokens[TokPos].Kind = tkLBrack);
          if moreDims then Next;   { consume 'array'; loop head consumes '[' }
        end;
        if VDNdCnt = 1 then
        begin VDArrLo := VDNdDimLo[0]; VDArrHi := VDNdDimLo[0] + VDNdDimSpan[0] - 1; end
        else
        begin
          VDIsArrND := True;
          flatLen := 1;
          for di := 0 to VDNdCnt - 1 do flatLen := flatLen * VDNdDimSpan[di];
          VDArrLo := 0; VDArrHi := flatLen - 1;
        end;
      end
      else
      begin
        VDIsDyn := True;   { 'array of T' without bounds is a dynamic array }
        VDDynDepth := 1;
        Expect(tkOf, 'of');
        { Nested dynamic arrays: array of array of ... of BaseType. }
        while CurTok.Kind = tkArray do
        begin
          Next;
          if CurTok.Kind = tkLBrack then
            Error('mixed static/dynamic nested arrays not supported');
          Inc(VDDynDepth);
          Expect(tkOf, 'of');
        end;
        { A named dynamic-array alias as the element (`array of TA` where
          `TA = array of Integer`) composes its depth: the result is
          `array of (dyn TA)`, i.e. our VDDynDepth plus the alias's depth, with the
          alias's BASE element type. ParseTypeKind cannot do this — array-type
          aliases live in the ArrType table, not the scalar alias table, so it
          would resolve `TA` to a bare base type and drop the dynamic dimension. }
        if CurTok.Kind = tkIdent then
        begin
          ai := FindArrayType(CurTok.SVal);
          if (ai >= 0) and ArrTypeIsDyn[ai] then
          begin
            VDElemTk := IntToTypeKind(ArrTypeElemTk[ai]);
            LastTypeRecId := ArrTypeElemRec[ai];
            LastTypePointerElemRec := ArrTypePtrElemRec[ai];
            VDDynDepth := VDDynDepth + ArrTypeDynDepth[ai];
            Next;                 { consume the alias name }
            VDTk := VDElemTk;
            elemResolved := True;
          end
          else if (ai >= 0) and (not ArrTypeIsDyn[ai]) then
          begin
            { `array of T` where T is a named FIXED array: the element is a whole
              ROW of ArrTypeHi-ArrTypeLo+1 base elements (flattened for N-D T).
              Without this, ParseTypeKind resolves T to its bare base scalar and
              the element stride collapses to the base type's size — d[i] lands on
              the wrong row and r := d[i] copies one scalar
              (bug-pascal-openarray-of-array-param-marshal). Row semantics are
              modelled for depth 1 only; deeper nesting stays unsupported. }
            if VDDynDepth > 1 then
              Error('array of array of <fixed array type> not supported');
            VDElemTk := IntToTypeKind(ArrTypeElemTk[ai]);
            LastTypeRecId := ArrTypeElemRec[ai];
            LastTypePointerElemRec := ArrTypePtrElemRec[ai];
            if (VDElemTk = tyAnsiString) or (VDElemTk = tyString) or
               (VDElemTk = tyFixedString) or (VDElemTk = tyShortString) or
               ((VDElemTk = tyRecord) and RecordHasManagedFields(LastTypeRecId)) then
              Error('array of <fixed array of managed elements> not supported');
            VDElemRowLen := ArrTypeHi[ai] - ArrTypeLo[ai] + 1;
            VDElemRowLo  := ArrTypeLo[ai];
            Next;                 { consume the alias name }
            VDTk := VDElemTk;
            elemResolved := True;
          end;
        end;
      end;
      { A FIXED array whose element is a dynamic-array alias
        (`array[0..3] of TA`, TA = `array of T`): each element slot holds a
        pointer-sized dyn-array handle. Record the element's dyn depth in
        VDElemDynDepth (threaded into SymElemDynDepth via LastTypeElemDynDepth at
        AllocArray); base element type/rec come from the alias. The dynamic-outer
        case above already handled its own alias element. }
      if VDIsArr and (not VDIsDyn) and (not elemResolved) and (CurTok.Kind = tkIdent) then
      begin
        ai := FindArrayType(CurTok.SVal);
        if (ai >= 0) and ArrTypeIsDyn[ai] then
        begin
          VDElemTk := IntToTypeKind(ArrTypeElemTk[ai]);
          LastTypeRecId := ArrTypeElemRec[ai];
          LastTypePointerElemRec := ArrTypePtrElemRec[ai];
          VDElemDynDepth := ArrTypeDynDepth[ai];
          Next;                 { consume the alias name }
          VDTk := VDElemTk;
          elemResolved := True;
        end
        else if (ai >= 0) and (not ArrTypeIsDyn[ai]) then
        begin
          { A FIXED array whose element is a FIXED named-array type
            (`array[0..2] of TG`, `TG = array[0..3] of T`): same flat layout as
            `array[0..2,0..3] of T` — merge TG's dims into the outer list, like
            the anonymous-nested form. Without this ParseTypeKind drops TG's
            dimension and the element stride collapses to the base type's size. }
          if ArrTypeNDims[ai] >= 2 then
          begin
            for di := 0 to ArrTypeNDims[ai] - 1 do
            begin
              if VDNdCnt >= MAX_ARR_DIMS then Error('too many array dimensions');
              VDNdDimLo[VDNdCnt]   := ArrTypeDimLo[ai * MAX_ARR_DIMS + di];
              VDNdDimSpan[VDNdCnt] := ArrTypeDimSpan[ai * MAX_ARR_DIMS + di];
              Inc(VDNdCnt);
            end;
          end
          else
          begin
            if VDNdCnt >= MAX_ARR_DIMS then Error('too many array dimensions');
            VDNdDimLo[VDNdCnt]   := ArrTypeLo[ai];
            VDNdDimSpan[VDNdCnt] := ArrTypeHi[ai] - ArrTypeLo[ai] + 1;
            Inc(VDNdCnt);
          end;
          VDIsArrND := True;
          flatLen := 1;
          for di := 0 to VDNdCnt - 1 do flatLen := flatLen * VDNdDimSpan[di];
          VDArrLo := 0; VDArrHi := flatLen - 1;
          VDElemTk := IntToTypeKind(ArrTypeElemTk[ai]);
          LastTypeRecId := ArrTypeElemRec[ai];
          LastTypePointerElemRec := ArrTypePtrElemRec[ai];
          VDTk := VDElemTk;
          elemResolved := True;
          Next;                 { consume the named array type }
        end;
      end;
      if not elemResolved then
      begin
        VDElemTk := ParseTypeKind;
        VDTk := VDElemTk;
        { array of <proctype>: element carries a call signature (plain proc =>
          tyPointer, method pointer => tyRecord). Captured for indexed indirect
          calls `arr[i](args)`. }
        if (VDElemTk = tyPointer) or (VDElemTk = tyRecord) then
          VDElemProcSig := LastTypeProcSig;
      end;
    end
    else
    begin
      { Skip qualifiers like pointer, ^, etc. Stop at `=` so a scalar
        initializer (`var x: Integer = 5`) is left for the init handler below.
        Stop at `absolute` too: it is a plain identifier, so this loop used to hand it
        (and the target name after it) to ParseTypeKind, where they fell through the
        unknown-name default and quietly became Integers. That is how `absolute` came to
        be silently IGNORED — the overlay never happened and the variable got its own
        storage. Handled properly just below. }
      if CurTok.Kind in [tkProcedure, tkFunction] then
        { `var cb: procedure(l: LongInt);` — an ANONYMOUS procedural type. The
          loop below treats these two tokens as the var section's terminator,
          which is right at a DECLARATION position (a routine follows) and wrong
          here: nothing but a type can follow the colon, so a routine
          declaration is not one of the readings. Take the type and skip the
          loop; ParseTypeKind's tkProcedure/tkFunction arm (and, for `of
          object`, the method-pointer record it hands back) does the rest.
          bug-a-an-anonymous-procedural-type-is-not-accepted }
        VDTk := ParseTypeKind
      else
      while not (CurTok.Kind in [tkSemicolon, tkEq, tkBegin, tkVar, tkConst, tkType,
                 tkProcedure, tkFunction, tkEnd, tkEOF]) and
            not ((CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'absolute')) do
      begin
        VDTk := ParseTypeKind;
      end;
    end;
end;

{ One symbol from the descriptor ParseDeclTypeDesc just filled. Reads no tokens.
  The caller owns everything that is about the DECLARATION rather than the type:
  the declared-type name span, `absolute` overlays, initializers, and (for a
  class var) the ClassVar registry row. }
function AllocFromDeclTypeDesc(const nm: AnsiString): Integer;
var idx, di: Integer;
begin
  if VDIsArr then
  begin
    if VDIsDyn then
    begin
      LastTypeDynElemRowLen := VDElemRowLen;  { fixed-array row element (consumed + reset by AllocDynArray) }
      LastTypeDynElemRowLo := VDElemRowLo;
      idx := AllocDynArray(nm, VDElemTk, VDDynDepth);
    end
    else
    begin
      LastTypeElemDynDepth := VDElemDynDepth;  { fixed array of a dyn-array element (consumed + reset by AllocArray) }
      idx := AllocArray(nm, VDElemTk, VDArrLo, VDArrHi);
      if VDElemTk = tyRecord then
      begin
        Syms[idx].ElemRecName := LastTypeRecId;
        SymSyncTypeRef(idx);
      end;
      if VDIsArrND then
      begin
        SymArrNDims[idx] := VDNdCnt;
        for di := 0 to VDNdCnt - 1 do
        begin
          SymArrDimLo[idx * MAX_ARR_DIMS + di]   := VDNdDimLo[di];
          SymArrDimSpan[idx * MAX_ARR_DIMS + di] := VDNdDimSpan[di];
        end;
      end;
    end;
    if VDElemProcSig >= 0 then SymElemProcSig[idx] := VDElemProcSig;  { array of proc-type: indexed indirect call arr[i](args) }
  end
  else
  begin
    idx := AllocVar(nm, VDTk);
    if (VDTk = tyInteger) and (LastTypeEnumId >= 0) then SymEnumId[idx] := LastTypeEnumId;
    if (VDTk = tyRecord) or (VDTk = tyClass) then
    begin
      Syms[idx].RecName := LastTypeRecId;
      SymProcSig[idx] := LastTypeProcSig;   { method-pointer record: callable }
      SymSyncTypeRef(idx);
    end
    else if VDTk = tyPointer then
    begin
      Syms[idx].PtrElemTk := LastTypePointerElemTk;
      Syms[idx].PtrElemRec := LastTypePointerElemRec;
      SymProcSig[idx] := LastTypeProcSig;
      SymSyncTypeRef(idx);
    end
    else if VDTk = tySet then
    begin
      SymSetEnumId[idx] := LastTypeSetEnumId;
      SymSetElemTk[idx] := LastTypeSetElemTk;
    end;
  end;
  Result := idx;
end;

procedure ParseVarSection;
var names: array[0..MAX_DECL_NAMES-1] of AnsiString; n, i, idx: Integer; tk: TTypeKind;
    isArr, isDyn: Boolean; arrLo, arrHi: Integer; elemTk: TTypeKind;
    initElem: Integer; initVal: Int64;
    absTarget: Integer;   { `x: T absolute y` — y's symbol, or -1 }
    initDepth, scOff, scLen: Integer;
    declTypeNOff, declTypeNLen: Integer;   { single-named-type span, for `parallel for` capture }
begin
  Next;
  { Stop at section / declaration-introducer keywords: these are plain
    identifiers in this dialect, so a `var` block would otherwise consume the
    next one as a variable name. Besides the section words (implementation/
    initialization/finalization), this includes the decl-introducers that may
    follow a var section — `constructor`/`destructor` (method-impl bodies),
    `generic`/`specialize`/`operator`, and `label` — matching the top-level
    decl loop's soft-ident set. Without this, `var g: Integer; destructor
    TFoo.Destroy;` mis-reads `destructor` as a var name (real tokens like
    tkProcedure/tkFunction/tkBegin already stop the loop; the soft ones did
    not). See bug-var-section-eats-constructor-destructor. }
  while (CurTok.Kind = tkIdent) and
        not CaseEqual(CurTok.SVal, 'implementation') and
        not CaseEqual(CurTok.SVal, 'initialization') and
        not CaseEqual(CurTok.SVal, 'finalization') and
        not CaseEqual(CurTok.SVal, 'constructor') and
        not CaseEqual(CurTok.SVal, 'destructor') and
        not CaseEqual(CurTok.SVal, 'generic') and
        not CaseEqual(CurTok.SVal, 'specialize') and
        not CaseEqual(CurTok.SVal, 'operator') and
        not CaseEqual(CurTok.SVal, 'label') do
  begin
    n := 0;
    repeat
      if n >= MAX_DECL_NAMES then Error('too many comma-separated names in one var declaration');
      names[n] := CurTok.SVal; Inc(n); Next;
    until not Eat(tkComma);
    Expect(tkColon, ':');
    { Record a SINGLE named type's span (`x: TGrid;`) for `parallel for` capture —
      the worker names its accessor `^TGrid`. Anonymous types (`array[..] of T`,
      `^P`, `set of ...`) leave it 0 (Phase B-2 synthesizes a name). }
    declTypeNOff := 0; declTypeNLen := 0;
    if (CurTok.Kind = tkIdent) and (TokPos < TokCount) and
       ((Tokens[TokPos].Kind = tkSemicolon) or (Tokens[TokPos].Kind = tkBegin) or
        (Tokens[TokPos].Kind = tkEnd)) then
    begin
      declTypeNOff := Tokens[TokPos-1].SOffset;
      declTypeNLen := Tokens[TokPos-1].SLen;
    end;
    ParseDeclTypeDesc;
    { Mirror the descriptor into the locals the initializer handling below reads.
      That code is about the `= value` clause, not about types, so it keeps the
      names it always had. }
    isArr := VDIsArr; isDyn := VDIsDyn; arrLo := VDArrLo; arrHi := VDArrHi;
    elemTk := VDElemTk; tk := VDTk;

    { `b: Integer absolute a;` — b SHARES a's storage (a classic Pascal overlay).
      `absolute` was not recognised at all and was silently swallowed, so b became an
      INDEPENDENT variable: reading it gave 0 and writing it never touched a. Wrong
      values, no diagnostic.

      Aliasing is exactly "same storage": give the new symbol the target's offset and
      scope instead of allocating its own. Only a plain named variable may be the
      target, and it must live in the same scope class (both global, or both local to
      this routine) — anything else is rejected loudly rather than half-supported. }
    absTarget := -1;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'absolute') then
    begin
      Next;
      if CurTok.Kind <> tkIdent then Error('absolute: expected a variable name');
      absTarget := FindSym(CurTok.SVal);
      if absTarget < 0 then Error('absolute: unknown variable ' + CurTok.SVal);
      if Syms[absTarget].Kind = skConst then
        Error('absolute: target must be a variable, not a constant');
      if Syms[absTarget].IsRef then
        { a by-ref param's slot holds an ADDRESS, so overlaying it would alias the
          pointer word, not the pointee — reject rather than half-support }
        Error('absolute: target must not be a by-reference parameter');
      { A local overlaying a global (or the reverse) would alias a FRAME offset onto a
        DATA offset — two different address spaces. Reject rather than half-support. }
      if (CurProc >= 0) and (Syms[absTarget].Kind = skGlobal) then
        Error('absolute: a local cannot overlay a global');
      if (CurProc < 0) and (Syms[absTarget].Kind <> skGlobal) then
        Error('absolute: a global can only overlay a global');
      if VDIsDyn then
        Error('absolute: a dynamic array cannot overlay a variable');
      Next;
    end;

	    for i := 0 to n-1 do
	    begin
	      idx := AllocFromDeclTypeDesc(names[i]);
	      if declTypeNOff <> 0 then begin SymDeclTypeNOff[idx] := declTypeNOff; SymDeclTypeNLen[idx] := declTypeNLen; end;
	      { `absolute` overlay: take the target's storage instead of our own. The alloc
	        already reserved a slot; we simply never use it, which costs a few bytes and
	        keeps every other invariant (scope, rollback, slot recycling) intact.
	        A FIXED array overlays exactly the same way — its Offset is the base of
	        its contiguous storage — and `b: array[0..3] of Byte absolute i` is the
	        canonical byte-view idiom, so it is included. It used to be excluded and
	        the exclusion was SILENT: the array kept its own slot, read 0 and swallowed
	        writes. A DYNAMIC array is refused instead, loudly: its slot holds a heap
	        handle, so overlaying it would reinterpret the target's bytes as a pointer
	        and free them.
	        bug-a-an-absolute-array-overlay-is-silently-ignored }
	      if (absTarget >= 0) and (not isDyn) then Syms[idx].Offset := Syms[absTarget].Offset;
	    end;
	    if Eat(tkEq) then
	    begin
	      { Constant initializer `= v` / `= (e0,e1,...)`. Recorded as pending
	        assignments compiled into the program entry just before `main begin`
	        (was silently discarded → globals read 0). Constants only; globals
	        only — a local section initializer should use inline `var x := v`. }
	      if n <> 1 then Error('initializer requires a single variable');
	      if CurProc >= 0 then
	      begin
	        { LOCAL var-section initializer `var a: UInt32 = 1;` — FPC-legal (an
	          assignment on entry, every call). Reuse the routine-local
	          typed-const machinery (flushed into the prologue): scalar
	          ordinal/float consts and string literals. Aggregates keep the
	          error. (rtl-generics' Adler32 declares two of these.) }
	        if isArr or isDyn then
	          Error('local var-section ARRAY initializer not supported; assign in statements');
	        if LocalInitCount >= MAX_LOCAL_INITS then Error('too many local initializers');
	        LocalInitSym[LocalInitCount]  := idx;
	        LocalInitElem[LocalInitCount] := PI_ELEM_NONE;
	        LocalInitFOff[LocalInitCount] := -1;
	        if CurTok.Kind = tkString then
	        begin
	          LocalInitKind[LocalInitCount] := 1;
	          LocalInitVal[LocalInitCount]  := Tokens[TokPos - 1].SOffset;
	          LocalInitFLen[LocalInitCount] := Tokens[TokPos - 1].SLen;
	          Next;
	        end
	        else
	        begin
	          LocalInitKind[LocalInitCount] := 0;
	          LocalInitVal[LocalInitCount]  := ParseInitValTk(tk);
	          LocalInitTk[LocalInitCount]   := Ord(tk);
	        end;
	        Inc(LocalInitCount);
	        Eat(tkSemicolon);
	        Continue;
	      end;
	      if isDyn then Error('dynamic array initializer not supported');
	      if CurTok.Kind = tkLParen then
	      begin
	        if not isArr then Error('parenthesised initializer requires an array variable');
	        Next;
	        initElem := 0;
	        { N-D array initializers nest one paren level per dimension
	          (`array[0..1,0..2] of T = ((a,b,c),(d,e,f))`); the flat store
	          fills in row-major order regardless of nesting depth, same as
	          ParseConstSection's array-constant loop. This used to be a flat
	          comma list (1-D only, no paren-depth tracking at all), so any
	          2+ dimensional var initializer broke structurally -- see
	          bug-array-const-too-many-elements-synapse. }
	        initDepth := 1;
	        while initDepth > 0 do
	        begin
	          if CurTok.Kind = tkLParen then begin Next; Inc(initDepth); end
	          else if CurTok.Kind = tkRParen then begin Next; Dec(initDepth); end
	          else if CurTok.Kind = tkComma then Next
	          else
	          begin
	            EnsurePendingInitCapacity(PendingInitCount);
	            if initElem > (arrHi - arrLo) then Error('too many array initializer elements');
	            if elemTk in [tyString, tyAnsiString, tyFixedString, tyShortString] then
	            begin
	              { String/AnsiString elements can't go through ParseInitVal/
	                ConstEval -- ConstEvalFactor only special-cases single-char
	                literals as an ordinal; a multi-char literal falls through
	                without consuming the token, desyncing initElem from the
	                real token stream (same underlying bug as
	                bug-const-array-of-ansistring-literal-too-many-elements,
	                fixed there for ParseConstSection but never mirrored here
	                for ParseVarSection). Capture the literal's span directly
	                and record it as a Kind=1 (string literal) init, same as
	                ParseConstSection's array-constant string handling. }
	              if CurTok.Kind <> tkString then
	                Error('array constant: expected a string or char literal');
	              scOff := Tokens[TokPos-1].SOffset;
	              scLen := Tokens[TokPos-1].SLen;
	              Next;
	              PendingInitSym[PendingInitCount]    := idx;
	              PendingInitElem[PendingInitCount]   := arrLo + initElem;
	              PendingInitFOff[PendingInitCount]   := -1;
	              PendingInitKind[PendingInitCount]   := 1;
	              PendingInitVal[PendingInitCount]     := scOff;
	              PendingInitValAux[PendingInitCount] := scLen;
	              PendingInitTk[PendingInitCount]     := Ord(elemTk);
	            end
	            else if (elemTk = tyPointer) and (CurTok.Kind = tkIdent) and
	                    (FindUClass(CurTok.SVal) >= 0) then
	            begin
	              { CLASS-REFERENCE element (an initialised VAR array of metaclasses) --
	                the same shape the const path handles; see there. fpjson declares
	                DefaultJSONInstanceTypes as a Var, and MinJSONInstanceTypes as a Const. }
	              PendingInitSym[PendingInitCount]  := idx;
	              PendingInitElem[PendingInitCount] := arrLo + initElem;
	              PendingInitFOff[PendingInitCount] := -1;
	              PendingInitKind[PendingInitCount] := 8;
	              PendingInitVal[PendingInitCount]  := FindUClass(CurTok.SVal);
	              PendingInitTk[PendingInitCount]   := Ord(tyPointer);
	              Next;
	            end
	            else
	            begin
	              initVal := ParseInitValTk(tk);
	              PendingInitSym[PendingInitCount]  := idx;
	              PendingInitElem[PendingInitCount] := arrLo + initElem;
	              PendingInitFOff[PendingInitCount] := -1;
	              PendingInitKind[PendingInitCount] := 0;
	              PendingInitVal[PendingInitCount]  := initVal;
	              PendingInitTk[PendingInitCount]   := Ord(elemTk);
	            end;
	            Inc(PendingInitCount);
	            Inc(initElem);
	          end;
	        end;
	      end
	      else
	      begin
	        if isArr then Error('array initializer must be parenthesised');
	        EnsurePendingInitCapacity(PendingInitCount);
	        if (CurTok.Kind = tkIdent) and IsClassType(CurTok.SVal) and
	           (FindSym(CurTok.SVal) < 0) then
	        begin
	          { initialized metaclass var: `SSLImplementation: TSSLClass = TSSLNone;`
	            (blcksock) — init kind 5, an AN_CLASSREF (VMT address) assignment;
	            same shape as ParseConstSection's typed metaclass const. }
	          initVal := FindUClass(CurTok.SVal);
	          if initVal < 0 then Error('unknown class in initializer');
	          Next;
	          PendingInitKind[PendingInitCount] := 5;
	          PendingInitTk[PendingInitCount]   := Ord(tyPointer);
	        end
	        else if CurTok.Kind = tkString then
	        begin
	          { initialised STRING var `s: String = 'seeded';` (b335) — the
	            LOCAL twin landed with b329; the global path lacked the case.
	            Kind 1 = string literal; Val/ValAux carry the token span,
	            exactly what the pending-init flush already reads. }
	          initVal := Tokens[TokPos - 1].SOffset;
	          PendingInitValAux[PendingInitCount] := Tokens[TokPos - 1].SLen;
	          PendingInitKind[PendingInitCount] := 1;
	          PendingInitTk[PendingInitCount]   := Ord(tk);
	          Next;
	        end
	        else
	        begin
	          initVal := ParseInitValTk(tk);
	          PendingInitKind[PendingInitCount] := 0;
	          PendingInitTk[PendingInitCount]   := Ord(tk);
	        end;
	        PendingInitSym[PendingInitCount]  := idx;
	        PendingInitElem[PendingInitCount] := PI_ELEM_NONE;
        PendingInitFOff[PendingInitCount] := -1;
	        PendingInitVal[PendingInitCount]  := initVal;
	        Inc(PendingInitCount);
	      end;
	    end;
	    Eat(tkSemicolon);
	  end;
	end;

{ One array DIMENSION bound pair: `lo..hi`, or an ordinal TYPE naming its whole range.

  FPC lets an array be indexed by an ordinal type rather than a literal range:

      ElementSeps : Array[Boolean] of TJSONStringType = (', ', ',');   { fpjson }
      Counts      : array[TJSONtype] of Integer;
      Table       : array[Char] of Byte;

  which mean [0..1], [0..High(TJSONtype)] and [0..255]. Only `lo..hi` parsed before, so the
  type name went straight into ConstEval and died on the missing `..`.

  A bare identifier is ambiguous -- `array[MaxLen..2]` starts with one too -- so an ident is
  only read as a TYPE when it is not followed by `..` AND it names an enum type. Otherwise
  it falls through to the ordinary constant range. }
procedure ParseArrayDimBounds(var lo, hi: Integer);
var eid: Integer; btk: TTypeKind; blo, bhi: Int64;
begin
  if CurTok.Kind = tkBoolean_T then
  begin
    lo := 0; hi := 1; Next; Exit;
  end;
  if CurTok.Kind = tkChar_T then
  begin
    lo := 0; hi := 255; Next; Exit;
  end;
  { A SMALL ordinal type as the whole index: `array[Byte] of ...`
    (rtl-generics' bucket tables). Only when the type IS the dimension (next
    token ends it) — `array[Byte(x)..2]` keeps the constant-range path. The
    32/64-bit ordinals stay errors: a 4-billion-element static array is a
    mistake, and FPC's own targets reject most of them too. }
  if ((CurTok.Kind = tkInteger_T) or (CurTok.Kind = tkLongWord_T)) and
     (TokPos < TokCount) and
     ((Tokens[TokPos].Kind = tkRBrack) or (Tokens[TokPos].Kind = tkComma)) then
  begin
    btk := ParseTypeKind;
    if OrdinalTypeBound(btk, False, blo) and OrdinalTypeBound(btk, True, bhi) and
       (bhi - blo < 65536) then
    begin
      lo := blo; hi := bhi; Exit;
    end;
    Error('array index type too large (use an explicit small range)');
  end;
  if (CurTok.Kind = tkIdent) and (TokPos < TokCount) and
     (Tokens[TokPos].Kind <> tkDotDot) then
  begin
    eid := FindEnumType(CurTok.SVal);
    if eid >= 0 then
    begin
      EnumTypeOrdRange(eid, lo, hi); Next; Exit;
    end;
  end;
  lo := ConstEval;
  Expect(tkDotDot, '..');
  hi := ConstEval;
end;

{ Accumulate a constant set TERM into mask[0..31]: either a `[...]` literal (elements and
  `lo..hi` ranges, all ConstEval-able) or the NAME of an already-baked set constant, whose
  mask is read straight back out of Data[]. }
procedure ConstSetTerm(var mask: array of Byte);
var lo, hi, vv, i, bit, k, sci, srcOff: Integer;
begin
  if CurTok.Kind = tkIdent then
  begin
    sci := FindSetConst(CurTok.SVal);
    if sci < 0 then
      Error('set constant expected: ' + CurTok.SVal);
    srcOff := SetConstOff[sci];
    for i := 0 to 31 do mask[i] := Data[srcOff + i];
    Next;
    Exit;
  end;

  Expect(tkLBrack, '[');
  for i := 0 to 31 do mask[i] := 0;
  if CurTok.Kind <> tkRBrack then
    repeat
      lo := ConstEval;
      hi := lo;
      if Eat(tkDotDot) then hi := ConstEval;
      if lo < 0 then lo := 0;
      if hi > 255 then hi := 255;
      for vv := lo to hi do
      begin
        { bit := 1 shl (vv mod 8) — built with *2 to avoid `shl` in compiler
          source (Shl8_ lives in ir.inc, included after this file). }
        bit := 1;
        for k := 1 to (vv mod 8) do bit := bit * 2;
        mask[vv div 8] := mask[vv div 8] or bit;
      end;
    until not Eat(tkComma);
  Expect(tkRBrack, ']');
end;

function BakeSetConst: Integer;
{ Evaluate a constant SET EXPRESSION and bake its 32-byte (256-bit) mask into Data[];
  return the Data offset. Same blob shape IR_SET_LIT emits for an all-constant literal, so
  a use resolves to that address.

  A term is a `[...]` literal or the name of an earlier set constant, and terms combine
  with the set operators, left-associative:

      +   union          (FPC also spells it `or` for sets)
      -   difference
      *   intersection   (`and`)

  This is what lets one set constant be defined from another --
  `ActualValueJSONTypes = ValueJSONTypes - [jtNull]` (fpjson) — which is the ordinary way
  FPC code writes these. Previously only a bare literal parsed, and a named set on the
  right-hand side fell into the integer ConstEval and died there.

  CurTok is on the first token of the expression. }
var mask, rhs: array[0..31] of Byte;
    i, idx: Integer;
    op: TTokenKind;
begin
  ConstSetTerm(mask);
  while CurTok.Kind in [tkPlus, tkMinus, tkStar, tkOr, tkAnd] do
  begin
    op := CurTok.Kind;
    Next;
    ConstSetTerm(rhs);
    for i := 0 to 31 do
      case op of
        tkPlus, tkOr:   mask[i] := mask[i] or rhs[i];
        { difference: complement rhs within the byte. Deliberately `255 - rhs[i]` and NOT
          `and not rhs[i]`, even though the latter now works: `not` on an ARRAY ELEMENT was
          lowered as a boolean not (fixed in this same commit), and the compiler is built by
          the PREVIOUS binary -- which still has that bug. Compiler source must not depend
          on a fix it is itself introducing, or stage 1 miscompiles. Same class of trap as
          `shl` (see the Shl8_ note in this file). }
        tkMinus:        mask[i] := mask[i] and (255 - rhs[i]);
        tkStar, tkAnd:  mask[i] := mask[i] and rhs[i];
      end;
  end;

  { emit the folded mask }
  while (DataLen mod 8) <> 0 do
  begin
    if DataLen >= MAX_DATA then Error('data overflow');
    Data[DataLen] := 0; Inc(DataLen);
  end;
  idx := DataLen;
  for i := 0 to 31 do
  begin
    if DataLen >= MAX_DATA then Error('data overflow');
    Data[DataLen] := mask[i]; Inc(DataLen);
  end;
  Result := idx;
end;

{ THE parser for a parameter's declared default value, `= <literal>`. CurTok is
  on the token AFTER the `=`; on return every out-parameter is set and the
  default's tokens are consumed.

  There are four parameter parsers in this file (free routine, class method,
  interface/forward method, record method) and each used to carry its own copy
  of this. The copies drifted exactly as `normalise-dont-special-case` predicts:
  sets were taught to two of them, floats to none, and the record-method copy
  still carries a comment claiming "the same two shapes the other parameter
  parsers take" — which stopped being true when the third shape landed. A FLOAT
  default (`d: Double = 2.5`) therefore matched no arm anywhere, fell through to
  the integer ConstEval, and was returned WITHOUT CONSUMING THE TOKEN — so the
  error surfaced on the NEXT parameter as a bare "unexpected token" and pointed
  at innocent code (bug-p-float-literal-default-in-a-parameter-list-fails-to-parse).

  Shapes, in the order they are recognised:
    string literal  isStr,   soff/slen locate the text
    float literal   isFloat, val holds the IEEE 754 BITS (what tkFloat lexes to,
                             and what ProcParamDefaultIsFloat documents)
    set expression  isSet,   val holds the baked 32-byte mask's Data[] offset
    otherwise       ordinal, val holds the folded Int64 }
{ True for the string kinds a bare ordinal must never be handed to. Deliberately
  NOT tyChar: a Char parameter taking an ordinal is an ordinary Pascal idiom. }
function TypeKindIsStringy(tk: TTypeKind): Boolean;
begin
  TypeKindIsStringy := (tk = tyAnsiString) or (tk = tyString) or
                       (tk = tyShortString) or (tk = tyFixedString);
end;

procedure ParseParamDefaultValue(paramTk: TTypeKind; var val: Int64;
                                 var isStr, isFloat, isSet: Boolean;
                                 var soff, slen: Integer);
begin
  val := 0; isStr := False; isFloat := False; isSet := False; soff := 0; slen := 0;
  if CurTok.Kind = tkString then
  begin
    soff := Tokens[TokPos-1].SOffset;
    slen := Tokens[TokPos-1].SLen;
    isStr := True;
    Next;
  end
  else if CurTok.Kind = tkFloat then
  begin
    val := CurTok.IVal;   { StrToDoubleBits — already the IEEE bits }
    isFloat := True;
    Next;
  end
  else if (CurTok.Kind = tkLBrack) or
          ((CurTok.Kind = tkIdent) and (FindSetConst(CurTok.SVal) >= 0)) then
  begin
    { `Options: TFormatOptions = []` or `= DefaultFormat` (fpjson's FormatJSON is
      both). A set is a 32-byte mask, not an ordinal, so bake it and keep the
      Data[] offset; the call rebuilds an AN_SET_CONST_REF from it. }
    val := BakeSetConst;
    isSet := True;
  end
  else
    val := ConstEval;

  { The shape above comes from the LITERAL's token kind; nothing so far has
    looked at what it is defaulting. `s: AnsiString = 1` therefore compiled
    clean and handed the callee the ordinal 1 as a string pointer — a segfault
    wherever the string was first touched, with no diagnostic anywhere near the
    declaration (bug-p-integer-default-on-a-string-parameter-is-accepted-and-segfaults).
    FPC rejects it outright, so reject it here: a real error at the declaration
    beats a crash three frames away. A tyVariant parameter is exempt — every
    shape is legitimately boxed into it. }
  if paramTk = tyVariant then Exit;
  if TypeKindIsStringy(paramTk) and (not isStr) then
    Error('a string parameter''s default must be a string literal');
  if isStr and (not TypeKindIsStringy(paramTk)) and (paramTk <> tyChar) then
    Error('a string literal cannot be the default for a non-string parameter');
end;

{ FPC hint directives — `deprecated ['msg']`, `platform`, `experimental`,
  `unimplemented`, `library` — may trail a const value, a type declaration, or a
  routine header. They only drive an optional compiler warning, so pxx parses and
  ignores them (no code effect). Soft identifiers in this dialect, so consume a
  run of them here rather than choke. `deprecated` takes an optional string
  message. See feature-hint-directives-deprecated-platform. }
procedure SkipHintDirectives;
begin
  while (CurTok.Kind = tkIdent) and
        (CaseEqual(CurTok.SVal, 'deprecated') or
         CaseEqual(CurTok.SVal, 'platform') or
         CaseEqual(CurTok.SVal, 'experimental') or
         CaseEqual(CurTok.SVal, 'unimplemented') or
         CaseEqual(CurTok.SVal, 'library')) do
  begin
    if CaseEqual(CurTok.SVal, 'deprecated') then
    begin
      Next;
      if CurTok.Kind = tkString then Next;   { optional 'use X instead' message }
    end
    else
      Next;
  end;
end;

procedure ParseConstSection(clsCi, clsVis: Integer);
{ clsCi >= 0 (the owning UClass) when this is a class-body `const` section, else
  -1 for a unit/program/record const section. The class context is held in the
  GLOBAL ParsingClassConstCi (so ConstEvalFactor can resolve a SIBLING class const
  in a value expression) but with STACK discipline: saved on entry, restored on
  exit. This is what keeps a class const section from tainting a UNIT const that
  gets parsed by a NESTED on-demand unit compile fired mid-value — that nested
  ParseConstSection(-1,..) sets the global to -1 for its own duration and restores
  ours after (bug-pascal-class-const-visibility, C-frontend crtl-autopull leak). }
var name: AnsiString; v: Int64;
    cTk, cElemTk: TTypeKind; cLo, cHi, cIdx, cElem, cClassIdx: Integer;
    isLocalConst: Boolean;
    constIsStatic: Boolean;   { routine-local typed const -> static BSS storage }
    cRec, fNameOff, fNameLen: Integer; fName: AnsiString; fTk: TTypeKind;
    fvKind, fvAux: Integer; fvVal: Int64;   { non-ordinal record-field init form }
    cnNDims, cFlatLen, cDi, cDepth: Integer;
    scOff, scLen, si, sci2, cCi, cAi: Integer;
    savedCCi, savedCVis: Integer;
    cnDimLo, cnDimSpan: array[0..MAX_ARR_DIMS-1] of Integer;
    cBssBefore, cBssAfter, cFirstPI: Integer;   { typed-const-array -> .data promotion, see TryBakeConstArrayIntoData }
    cBaked: Boolean;
begin
  savedCCi := ParsingClassConstCi; savedCVis := ParsingClassConstVis;
  ParsingClassConstCi := clsCi; ParsingClassConstVis := clsVis;
  Next;
  { `constructor`/`destructor`/`operator` and the unit section words are plain
    identifiers in this dialect (not keyword tokens like `procedure`/`function`,
    which terminate the loop naturally). Without these guards a const section
    directly followed by a constructor/destructor body — or ending an interface
    before `implementation` — would consume that word as the next const NAME and
    then fail expecting `=`. Mirrors the type-section terminator set. }
  { ...and, for a `const` section inside a CLASS BODY, the visibility markers, which are
    likewise plain identifiers. Without them the section ran straight through
    `strict private` and consumed `strict` as the next const NAME
    (IsClassMemberStartWord covers private/protected/public/published + ctor/dtor). }
  while (CurTok.Kind = tkIdent) and
        (not IsClassMemberStartWord(CurTok.SVal)) and
        (not CaseEqual(CurTok.SVal, 'strict')) and
        (not CaseEqual(CurTok.SVal, 'operator')) and
        (not CaseEqual(CurTok.SVal, 'implementation')) and
        (not CaseEqual(CurTok.SVal, 'initialization')) and
        (not CaseEqual(CurTok.SVal, 'finalization')) do
  begin
    name := CurTok.SVal; Next;
    if CurTok.Kind = tkColon then
    begin
      { Typed constant: `const Name: type = value | (e0,e1,...)`. FPC typed
        constants are writable storage with an initial value, so allocate storage
        and reuse the pending-init machinery (same as a `var = init`).

        A routine-LOCAL one is STATIC: FPC gives it storage that outlives the
        call and initialises it once, which is what makes the `const calls:
        Integer = 0; begin Inc(calls)` counter idiom work. This used to allocate
        a STACK slot and re-run the initialiser from the prologue, so the counter
        printed 1 on every call, `const d: Double = 1.5; d := d * 2` printed 3.00
        forever, and a string-typed one did not compile at all
        (bug-p-a-routine-local-typed-const-is-reinitialised-on-every-call).

        So force BSS storage (AllocStaticLocal, restored below with stack
        discipline -- a nested on-demand unit compile can run inside the value)
        and take the GLOBAL recording path throughout: PendingInit, compiled once
        before `main begin`. The symbol keeps its routine BlockId, so it is still
        only visible inside the routine. }
      { STATIC storage, but the initialiser stays INLINE in the routine, run
        once behind a guard -- the shape the C frontend already uses for
        block-scope `static` (CWrapStaticInitOnce, cparser.inc). Recording it
        into PendingInit instead cannot work: leaving the routine calls
        SymRollbackTo, so by the time main is compiled the record names a
        symbol index past SymCount and IR validation rejects it. }
      constIsStatic := CurProc >= 0;
      isLocalConst := False;
      { A TYPED class-body const gets the same registry row + mangled backing
        name the untyped forms below get. It used to keep its BARE name and
        ordinary global storage — "rare; tracked as a follow-up", said the note
        in the untyped arm — and the consequence was not merely that
        `TFoo.X` could not resolve it: two classes each declaring
        `const TAG: array[1..2] of Integer` shared ONE slot, so TA's method read
        TB's value with no diagnostic, where FPC reads TA's.
        bug-p-two-classes-typed-consts-of-the-same-name-collide

        Registered here, BEFORE the storage is allocated, so AllocVar/AllocArray
        names the mangled key. Access goes through the registry at every site
        (qualified, bare-in-method, const-fold), and because a typed const is
        STORAGE rather than a literal, those sites resolve the mangled key to a
        SYMBOL and re-enter — exactly what a `class var` already does. }
      if ParsingClassConstCi >= 0 then
      begin
        if ClassConstCount >= MAX_TYPEALIAS then Error('too many class constants');
        ClassConstCi[ClassConstCount]   := ParsingClassConstCi;
        ClassConstName[ClassConstCount] := name;
        ClassConstVis[ClassConstCount]  := ParsingClassConstVis;
        Inc(ClassConstCount);
        name := ClassConstMangle(ParsingClassConstCi, name);
      end;
      Next;
      { A NAMED fixed-array type (`Action0: TLogonActions = (...)`, ftpsend)
        takes the same array-constant path as the inline `array[..] of T`
        form: load its dims/element from the ArrType tables. }
      cAi := -1;
      if CurTok.Kind = tkIdent then
      begin
        cAi := FindArrayType(CurTok.SVal);
        if (cAi >= 0) and ArrTypeIsDyn[cAi] then cAi := -1;
      end;
      if (CurTok.Kind = tkArray) or (cAi >= 0) then
      begin
        if cAi >= 0 then
        begin
          Next;   { consume the named array type }
          cnNDims := ArrTypeNDims[cAi];
          if cnNDims >= 2 then
          begin
            for cDi := 0 to cnNDims - 1 do
            begin
              cnDimLo[cDi]   := ArrTypeDimLo[cAi * MAX_ARR_DIMS + cDi];
              cnDimSpan[cDi] := ArrTypeDimSpan[cAi * MAX_ARR_DIMS + cDi];
            end;
          end
          else
          begin
            cnNDims := 1;
            cnDimLo[0]   := ArrTypeLo[cAi];
            cnDimSpan[0] := ArrTypeHi[cAi] - ArrTypeLo[cAi] + 1;
          end;
          cElemTk := IntToTypeKind(ArrTypeElemTk[cAi]);
          LastTypeRecId := ArrTypeElemRec[cAi];
          LastTypePointerElemRec := ArrTypePtrElemRec[cAi];
        end
        else
        begin
        Next;
        Expect(tkLBrack, '[');
        { One or more comma-separated dimensions, mirroring the var-section ND
          path. >=2 dims flatten to a 1-D row-major store indexed as an N-D array
          (SymArrNDims), so `const M: array[0..1,0..1] of T = ((..),(..))` works
          like the var form. }
        cnNDims := 0;
        repeat
          ParseArrayDimBounds(cLo, cHi);
          if cnNDims >= MAX_ARR_DIMS then Error('too many array dimensions');
          cnDimLo[cnNDims] := cLo; cnDimSpan[cnNDims] := cHi - cLo + 1; Inc(cnNDims);
        until not Eat(tkComma);
        Expect(tkRBrack, ']');
        Expect(tkOf, 'of');
        cElemTk := ParseTypeKind;
        end;
        if cnNDims = 1 then
        begin
          cLo := cnDimLo[0]; cFlatLen := cnDimSpan[0];
        end
        else
        begin
          cFlatLen := 1;
          for cDi := 0 to cnNDims - 1 do cFlatLen := cFlatLen * cnDimSpan[cDi];
          cLo := 0;
        end;
        cHi := cLo + cFlatLen - 1;
        AllocStaticLocal := constIsStatic;
        cBssBefore := BSSSize;
        cIdx := AllocArray(name, cElemTk, cLo, cHi);
        cBssAfter := BSSSize;
        AllocStaticLocal := False;
        if cElemTk = tyRecord then
        begin
          Syms[cIdx].ElemRecName := LastTypeRecId;
          SymSyncTypeRef(cIdx);
        end;
        if cnNDims >= 2 then
        begin
          SymArrNDims[cIdx] := cnNDims;
          for cDi := 0 to cnNDims - 1 do
          begin
            SymArrDimLo[cIdx * MAX_ARR_DIMS + cDi]   := cnDimLo[cDi];
            SymArrDimSpan[cIdx * MAX_ARR_DIMS + cDi] := cnDimSpan[cDi];
          end;
        end;
        Expect(tkEq, '=');
        { Nested-paren initializer flattened in row-major encounter order. A 1-D
          array is one paren level; an N-D one nests one level per dimension, but
          the flat store fills in order regardless of nesting depth. }
        Expect(tkLParen, '(');
        cFirstPI := PendingInitCount;
        cDepth := 1; cElem := 0;
        while cDepth > 0 do
        begin
          if (cDepth = 1) and (cElemTk = tyRecord) and (CurTok.Kind = tkLParen) and
             (TokPos + 1 < TokCount) and (Tokens[TokPos].Kind = tkIdent) and
             (Tokens[TokPos+1].Kind = tkColon) then
          begin
            { Array-of-RECORD element with NAMED-field initializers —
              `(name: 'AND'; c: CSTII_and)` (Pascal Script's keyword table).
              Each field becomes a `sym[elem].field := value` init; the
              emitter already combines Elem + FOff. }
            if cElem >= cFlatLen then Error('too many array constant elements');
            Next;   { consume '(' }
            while CurTok.Kind <> tkRParen do
            begin
              if CurTok.Kind <> tkIdent then Error('expected field name in record constant');
              fNameOff := Tokens[TokPos-1].SOffset;
              fNameLen := Tokens[TokPos-1].SLen;
              fName := CurTok.SVal;
              Next;
              Expect(tkColon, ':');
              fTk := RecFieldType(Syms[cIdx].ElemRecName, fName);
              if fTk = tyUnknown then Error('unknown field in record constant: ' + fName);
              if isLocalConst then
              begin
                { local emitter has no field+string combo; strings global-only }
                if TypeIsFrozenString(fTk) or (fTk = tyAnsiString) then
                  Error('array-of-record constant with string fields must be global');
                if LocalInitCount >= MAX_LOCAL_INITS then Error('too many local initializers');
                LocalInitSym[LocalInitCount]  := cIdx;
                LocalInitElem[LocalInitCount] := cLo + cElem;
                LocalInitFOff[LocalInitCount] := fNameOff;
                LocalInitFLen[LocalInitCount] := fNameLen;
                LocalInitKind[LocalInitCount] := 0;
                LocalInitVal[LocalInitCount]  := ParseInitValTk(fTk);
                LocalInitTk[LocalInitCount] := Ord(fTk);
                Inc(LocalInitCount);
              end
              else
              begin
                EnsurePendingInitCapacity(PendingInitCount);
                PendingInitSym[PendingInitCount]  := cIdx;
                PendingInitElem[PendingInitCount] := cLo + cElem;
                PendingInitFOff[PendingInitCount] := fNameOff;
                PendingInitFLen[PendingInitCount] := fNameLen;
                if TypeIsFrozenString(fTk) or (fTk = tyAnsiString) then
                begin
                  if CurTok.Kind <> tkString then Error('record constant: expected a string literal');
                  PendingInitKind[PendingInitCount]   := 1;
                  PendingInitVal[PendingInitCount]    := Tokens[TokPos-1].SOffset;
                  PendingInitValAux[PendingInitCount] := Tokens[TokPos-1].SLen;
                  Next;
                end
                { The scalar record-constant path's @proc / @var / @TClass.Method
                  forms, for an ARRAY-of-record element. This is that path's
                  sibling and the two must know the same value forms:
                  rtl-generics' ComparerInstances is `array[TTypeKind] of
                  TInstance` with `@TComparerService.SelectBinaryComparer` in a
                  field. (The string case is handled just above, so the arm is
                  only reached for non-string fields.) }
                else if TryParseInitValForm(fTk, fvKind, fvVal, fvAux) then
                begin
                  PendingInitKind[PendingInitCount]   := fvKind;
                  PendingInitVal[PendingInitCount]    := fvVal;
                  PendingInitValAux[PendingInitCount] := fvAux;
                end
                else
                begin
                  PendingInitKind[PendingInitCount] := 0;
                  PendingInitVal[PendingInitCount]  := ParseInitValTk(fTk);
                end;
                PendingInitTk[PendingInitCount] := Ord(fTk);
                Inc(PendingInitCount);
              end;
              if not Eat(tkSemicolon) then Eat(tkComma);
            end;
            Expect(tkRParen, ')');
            Eat(tkComma);
            Inc(cElem);
          end
          else if CurTok.Kind = tkLParen then begin Next; Inc(cDepth); end
          else if CurTok.Kind = tkRParen then begin Next; Dec(cDepth); end
          else if CurTok.Kind = tkComma then Next
          else
          begin
            if cElem >= cFlatLen then Error('too many array constant elements');
            if cElemTk in [tyString, tyAnsiString, tyFixedString, tyShortString] then
            begin
              { String/AnsiString array-const elements can't go through
                ParseInitVal/ConstEval (ConstEvalFactor only special-cases
                single-char literals as an ordinal; a multi-char literal falls
                through without consuming the token, desyncing cElem from the
                real token stream -- bug-const-array-of-ansistring-literal-too-
                many-elements). Capture the literal's span directly, exactly
                like the scalar typed-string-const path above, and record it as
                a Kind=1 (string literal) init so the emitter builds an
                AN_STR_LIT assignment -- same managed-string coercion any
                ordinary `s := 'literal'` already gets. }
              if CurTok.Kind <> tkString then
                Error('array constant: expected a string or char literal');
              scOff := Tokens[TokPos-1].SOffset;
              scLen := Tokens[TokPos-1].SLen;
              Next;
              if isLocalConst then
              begin
                if LocalInitCount >= MAX_LOCAL_INITS then Error('too many local initializers');
                LocalInitSym[LocalInitCount]  := cIdx;
                LocalInitElem[LocalInitCount] := cLo + cElem;
                LocalInitFOff[LocalInitCount] := -1;
                LocalInitKind[LocalInitCount] := 1;
                LocalInitVal[LocalInitCount]  := scOff;
                LocalInitFLen[LocalInitCount] := scLen;
                LocalInitTk[LocalInitCount]   := Ord(cElemTk);
                Inc(LocalInitCount);
              end
              else
              begin
                EnsurePendingInitCapacity(PendingInitCount);
                PendingInitSym[PendingInitCount]    := cIdx;
                PendingInitElem[PendingInitCount]   := cLo + cElem;
                PendingInitFOff[PendingInitCount]   := -1;
                PendingInitKind[PendingInitCount]   := 1;
                PendingInitVal[PendingInitCount]    := scOff;
                PendingInitValAux[PendingInitCount] := scLen;
                PendingInitTk[PendingInitCount]     := Ord(cElemTk);
                Inc(PendingInitCount);
              end;
            end
            else if (cElemTk = tyPointer) and (CurTok.Kind = tkIdent) and
                    (FindUClass(CurTok.SVal) >= 0) then
            begin
              { A CLASS REFERENCE element: an array of metaclasses initialised with class
                NAMES —

                  DefaultJSONInstanceTypes : Array[TJSONInstanceType] of TJSONDataClass =
                    (TJSONData, TJSONIntegerNumber, ... );      { fpjson }

                The value is the class's RTTI blob address, which is only known after
                EmitRTTI — so it cannot be a ConstEval ordinal. Record the class INDEX and
                let the initializer emit an AN_CLASSREF, exactly as a class name used as a
                value anywhere else does; the blob address is patched in at link time
                through the same per-class data-ref sentinel. }
              cClassIdx := FindUClass(CurTok.SVal);
              Next;
              if isLocalConst then
              begin
                { A ROUTINE-LOCAL const array of class references. Every other element kind
                  around here already forks on isLocalConst; this branch did not, and
                  registered a PENDING GLOBAL initializer holding the routine-local symbol
                  index. That index is rolled back with the routine's scope
                  (SymRollbackTo), so by the time main ran the pending initializers it
                  pointed past the end of the symbol table -- the strict-IR verifier caught
                  it as "invalid symbol in lea", with a dangling IR_LEA in main.

                  Local inits already carry kind 5 = AN_CLASSREF (the scalar metaclass
                  const), and the flush honours LocalInitElem, so an array ELEMENT needs
                  nothing new. fcl-json's testjsondata.pp does exactly this:
                    Const MyJSONInstanceTypes : Array[TJSONInstanceType] of TJSONDataClass
                            = (TJSONData, TMyInteger, ...); }
                if LocalInitCount >= MAX_LOCAL_INITS then Error('too many local initializers');
                LocalInitSym[LocalInitCount]  := cIdx;
                LocalInitElem[LocalInitCount] := cLo + cElem;
                LocalInitFOff[LocalInitCount] := -1;
                LocalInitKind[LocalInitCount] := 5;      { AN_CLASSREF }
                LocalInitVal[LocalInitCount]  := cClassIdx;
                LocalInitTk[LocalInitCount]   := Ord(tyPointer);
                Inc(LocalInitCount);
              end
              else
              begin
                EnsurePendingInitCapacity(PendingInitCount);
                PendingInitSym[PendingInitCount]  := cIdx;
                PendingInitElem[PendingInitCount] := cLo + cElem;
                PendingInitFOff[PendingInitCount] := -1;
                PendingInitKind[PendingInitCount] := 8;
                PendingInitVal[PendingInitCount]  := cClassIdx;
                PendingInitTk[PendingInitCount]   := Ord(tyPointer);
                Inc(PendingInitCount);
              end;
            end
            else if isLocalConst then
            begin
              if LocalInitCount >= MAX_LOCAL_INITS then Error('too many local initializers');
              LocalInitSym[LocalInitCount]  := cIdx;
              LocalInitElem[LocalInitCount] := cLo + cElem;
              LocalInitFOff[LocalInitCount] := -1;
              LocalInitVal[LocalInitCount]  := ParseInitValTk(cElemTk);
              LocalInitTk[LocalInitCount]   := Ord(cElemTk);
              Inc(LocalInitCount);
            end
            else
            begin
              EnsurePendingInitCapacity(PendingInitCount);
              PendingInitSym[PendingInitCount]  := cIdx;
              PendingInitElem[PendingInitCount] := cLo + cElem;
              PendingInitFOff[PendingInitCount] := -1;
              PendingInitVal[PendingInitCount]  := ParseInitValTk(cElemTk);
              PendingInitTk[PendingInitCount]   := Ord(cElemTk);
              Inc(PendingInitCount);
            end;
            Inc(cElem);
          end;
        end;
        if cElem <> cFlatLen then Error('wrong number of array constant elements');
        { The whole extent is now recorded as one pending store per element. If
          every one of them is a plain ordinal/float literal, bake the bytes
          into .data instead and drop the stores -- see
          TryBakeConstArrayIntoData for the measurement that made this worth
          doing, and for why it fails closed. }
        cBaked := False;
        if not isLocalConst then
          cBaked := TryBakeConstArrayIntoData(cIdx, cFirstPI, cBssBefore, cBssAfter);
        if cBaked and PxxDbgEnabled('a.constdata') then
          writeln('PXXDBG a.constdata baked ', name, ' n=', Syms[cIdx].ArrLen,
                  ' elemsize=', TypeSize(cElemTk), ' dataoff=', Syms[cIdx].Offset - DATA_SYM_BIAS);
      end
      else
      begin
        cTk := ParseTypeKind;
        if cTk = tySet then
        begin
          { Typed set constant `const S: TS = [..]`: bake the 32-byte mask and
            record it in the SetConst table; uses resolve to AN_SET_CONST_REF.
            No runtime var symbol is allocated — the const carries no storage, and
            a phantom var would shadow a same-named variable case-insensitively
            (bug-set-of-char-const-corrupts-char-codegen). }
          Expect(tkEq, '=');
          if SetConstCount >= MAX_TYPEALIAS then Error('too many set constants');
          SetConstName[SetConstCount]   := name;
          SetConstEnumId[SetConstCount] := LastTypeSetEnumId;
          SetConstOff[SetConstCount]    := BakeSetConst;
          SetConstUnitIdx[SetConstCount] := CurrentUnitIdx; Inc(SetConstCount);
        end
        else if cTk in [tyString, tyAnsiString, tyFixedString, tyShortString] then
        begin
          { Typed string constant `const Name: string = 'literal'` (and the
            `'a' + 'b'` / `#65 + #66` concatenation form). Treated as a read-only
            string-literal alias — registered in the StrConst table exactly like
            the untyped `const Name = 'literal'` path, with NO storage var (a
            phantom var would shadow a same-named variable and ParseInitVal has no
            string case). A use of the name expands to AN_STR_LIT over the span,
            which already coerces to a managed string where needed. }
          Expect(tkEq, '=');
          if CurTok.Kind <> tkString then
            Error('typed string constant: expected a string or char literal');
          if (Tokens[TokPos].Kind = tkPlus) then
          begin
            scOff := TokCharLen; scLen := 0;
            for si := 1 to Length(CurTok.SVal) do
            begin
              if TokCharLen >= STRING_CAP then Error('string constant buffer overflow');
              TokChars[TokCharLen] := CurTok.SVal[si]; Inc(TokCharLen); Inc(scLen);
            end;
            Next;
            while CurTok.Kind = tkPlus do
            begin
              Next;
              if CurTok.Kind <> tkString then
                Error('const string concatenation: expected a string or char literal');
              for si := 1 to Length(CurTok.SVal) do
              begin
                if TokCharLen >= STRING_CAP then Error('string constant buffer overflow');
                TokChars[TokCharLen] := CurTok.SVal[si]; Inc(TokCharLen); Inc(scLen);
              end;
              Next;
            end;
            if StrConstCount >= MAX_TYPEALIAS then Error('too many string constants');
            StrConstName[StrConstCount] := name;
            StrConstOwner[StrConstCount] := CurProc;
            StrConstSOff[StrConstCount] := scOff;
            StrConstSLen[StrConstCount] := scLen;
            StrConstUnitIdx[StrConstCount] := CurrentUnitIdx; Inc(StrConstCount);
          end
          else
          begin
            if StrConstCount >= MAX_TYPEALIAS then Error('too many string constants');
            StrConstName[StrConstCount] := name;
            StrConstOwner[StrConstCount] := CurProc;
            StrConstSOff[StrConstCount] := Tokens[TokPos-1].SOffset;
            StrConstSLen[StrConstCount] := Tokens[TokPos-1].SLen;
            StrConstUnitIdx[StrConstCount] := CurrentUnitIdx; Inc(StrConstCount);
            Next;
          end;
        end
        else
        begin
        AllocStaticLocal := constIsStatic;
        cIdx := AllocVar(name, cTk);
        AllocStaticLocal := False;
        if cTk = tyPointer then
        begin
          { metaclass / pointer typed const: keep the pointee info so uses
            (SSLImplementation.Create) dispatch like a var of the type }
          Syms[cIdx].PtrElemTk := LastTypePointerElemTk;
          Syms[cIdx].PtrElemRec := LastTypePointerElemRec;
          { ...INCLUDING the call signature, which is what makes a procedural
            type callable: `const K: TFn = @Sq;` then `K(7)`. The var arm above
            copies it, this one did not, so a procvar CONST could be declared
            and assigned to a variable but never called — the statement and
            expression call sites both gate on SymProcSig >= 0 and saw -1.
            bug-a-a-typed-procvar-constant-cannot-be-called }
          SymProcSig[cIdx] := LastTypeProcSig;
          SymSyncTypeRef(cIdx);
        end;
        Expect(tkEq, '=');
        if (cTk <> tyRecord) and (CurTok.Kind = tkIdent) and
           IsClassType(CurTok.SVal) and (FindSym(CurTok.SVal) < 0) then
        begin
          { Metaclass typed const initialized with a class NAME —
            `SSLImplementation: TSSLClass = TSSLNone;` (blcksock). Init kind 5:
            the emitter builds an AN_CLASSREF (VMT address) assignment. }
          cCi := FindUClass(CurTok.SVal);
          if cCi < 0 then Error('unknown class in constant initializer');
          Next;
          if isLocalConst then
          begin
            if LocalInitCount >= MAX_LOCAL_INITS then Error('too many local initializers');
            LocalInitSym[LocalInitCount]  := cIdx;
            LocalInitElem[LocalInitCount] := PI_ELEM_NONE;
            LocalInitFOff[LocalInitCount] := -1;
            LocalInitKind[LocalInitCount] := 5;
            LocalInitVal[LocalInitCount]  := cCi;
            LocalInitTk[LocalInitCount]   := Ord(tyPointer);
            Inc(LocalInitCount);
          end
          else
          begin
            EnsurePendingInitCapacity(PendingInitCount);
            PendingInitSym[PendingInitCount]  := cIdx;
            PendingInitElem[PendingInitCount] := PI_ELEM_NONE;
            PendingInitFOff[PendingInitCount] := -1;
            PendingInitKind[PendingInitCount] := 5;
            PendingInitVal[PendingInitCount]  := cCi;
            PendingInitTk[PendingInitCount]   := Ord(tyPointer);
            Inc(PendingInitCount);
          end;
        end
        else if cTk = tyRecord then
        begin
          { Record typed constant: `const r: TRec = (f1: v1; f2: v2; ...)` (FPC
            named-field form). Each scalar field initializer is recorded as a
            `r.field := value` init (field span drives an AN_FIELD target in the
            init emitter). Nested record/array fields are not handled yet. }
          cRec := Syms[cIdx].RecName;
          Expect(tkLParen, '(');
          while CurTok.Kind <> tkRParen do
          begin
            if CurTok.Kind <> tkIdent then Error('expected field name in record constant');
            fName := CurTok.SVal;
            fNameOff := Tokens[TokPos-1].SOffset;
            fNameLen := Tokens[TokPos-1].SLen;
            Next;
            Expect(tkColon, ':');
            fTk := RecFieldType(cRec, fName);
            if fTk = tyUnknown then Error('unknown field in record constant: ' + fName);
            if RecFieldIsArray(cRec, fName) and (CurTok.Kind = tkLParen) then
            begin
              { Array-valued field: `D4: ($C0, 0, ..., $46)` (TGuid). Each
                element is a `sym.field[k] := v` init (Kind 7 — the emitter
                builds FIELD then INDEX). Global-only for now. }
              if isLocalConst then Error('array-valued field in a LOCAL record constant is not supported');
              Next;   { consume '(' }
              cElem := 0;
              while CurTok.Kind <> tkRParen do
              begin
                EnsurePendingInitCapacity(PendingInitCount);
                PendingInitSym[PendingInitCount]  := cIdx;
                PendingInitElem[PendingInitCount] := PI_ELEM_NONE;
                PendingInitFOff[PendingInitCount] := fNameOff;
                PendingInitFLen[PendingInitCount] := fNameLen;
                PendingInitKind[PendingInitCount] := 7;
                PendingInitValAux[PendingInitCount] := cElem;
                PendingInitVal[PendingInitCount]  := ParseInitValTk(fTk);
                PendingInitTk[PendingInitCount]   := Ord(fTk);
                Inc(PendingInitCount);
                Inc(cElem);
                if not Eat(tkComma) then Break;
              end;
              Expect(tkRParen, ')');
            end
            else if isLocalConst then
            begin
              if LocalInitCount >= MAX_LOCAL_INITS then Error('too many local initializers');
              LocalInitSym[LocalInitCount]  := cIdx;
              LocalInitElem[LocalInitCount] := PI_ELEM_NONE;
              LocalInitFOff[LocalInitCount] := fNameOff;
              LocalInitFLen[LocalInitCount] := fNameLen;
              if TryParseInitValForm(fTk, fvKind, fvVal, fvAux) then
              begin
                { A LOCAL record const has no ValAux slot, and FLen is already
                  spoken for by the field NAME span the FIELD target reads. A
                  string value would have to overwrite it, so refuse rather than
                  corrupt the target -- the same call, and the same wording, the
                  array-of-record path above already makes. `@proc` / `@var`
                  carry everything in Val and are fine. }
                if fvKind = 1 then
                  Error('record constant with string fields must be global');
                LocalInitKind[LocalInitCount] := fvKind;
                LocalInitVal[LocalInitCount]  := fvVal;
              end
              else
              begin
                LocalInitKind[LocalInitCount] := 0;
                LocalInitVal[LocalInitCount]  := ParseInitValTk(fTk);
              end;
              LocalInitTk[LocalInitCount]   := Ord(fTk);
              Inc(LocalInitCount);
            end
            else
            begin
              EnsurePendingInitCapacity(PendingInitCount);
              PendingInitSym[PendingInitCount]  := cIdx;
              PendingInitElem[PendingInitCount] := PI_ELEM_NONE;
              PendingInitFOff[PendingInitCount] := fNameOff;
              PendingInitFLen[PendingInitCount] := fNameLen;
              if TryParseInitValForm(fTk, fvKind, fvVal, fvAux) then
              begin
                PendingInitKind[PendingInitCount]   := fvKind;
                PendingInitVal[PendingInitCount]    := fvVal;
                PendingInitValAux[PendingInitCount] := fvAux;
              end
              else
              begin
                PendingInitKind[PendingInitCount] := 0;
                PendingInitVal[PendingInitCount]  := ParseInitValTk(fTk);
              end;
              PendingInitTk[PendingInitCount]   := Ord(fTk);
              Inc(PendingInitCount);
            end;
            { FPC separates fields with `;`; tolerate a trailing `,` too. }
            if not Eat(tkSemicolon) then Eat(tkComma);
          end;
          Expect(tkRParen, ')');
        end
        else if isLocalConst then
        begin
          if LocalInitCount >= MAX_LOCAL_INITS then Error('too many local initializers');
          LocalInitSym[LocalInitCount]  := cIdx;
          LocalInitElem[LocalInitCount] := PI_ELEM_NONE;
          LocalInitFOff[LocalInitCount] := -1;
          LocalInitKind[LocalInitCount] := 0;   { slots are reused; clear a stale kind }
          LocalInitVal[LocalInitCount]  := ParseInitValTk(cTk);
          LocalInitTk[LocalInitCount]   := Ord(cTk);
          Inc(LocalInitCount);
        end
        else
        begin
          EnsurePendingInitCapacity(PendingInitCount);
          PendingInitSym[PendingInitCount]  := cIdx;
          PendingInitElem[PendingInitCount] := PI_ELEM_NONE;
          PendingInitFOff[PendingInitCount] := -1;
          { Same non-ordinal value forms the record-field path takes, for a
            SCALAR typed const: `const P: Pointer = @Something`. The string arm
            cannot fire here -- a string-typed const is handled well above this
            point -- but @proc / @var / @TClass.Method all reach it.
            rtl-generics publishes its comparer instances this way
            (`Comparer_Int8_Instance: Pointer = @Comparer_Int8_VMT`). }
          if TryParseInitValForm(cTk, fvKind, fvVal, fvAux) then
          begin
            PendingInitKind[PendingInitCount]   := fvKind;
            PendingInitVal[PendingInitCount]    := fvVal;
            PendingInitValAux[PendingInitCount] := fvAux;
          end
          else
          begin
            PendingInitKind[PendingInitCount] := 0;
            PendingInitVal[PendingInitCount]  := ParseInitValTk(cTk);
          end;
          PendingInitTk[PendingInitCount]   := Ord(cTk);
          Inc(PendingInitCount);
        end;
        end;
      end;
    end
    else
    begin
      Expect(tkEq, '=');
      { Class-body const (`type TFoo = class const Max = 5`): register a registry
        row (owner + visibility) and mangle the backing NAME so this scalar/string/
        set const does not collide with another class's `Max` or a unit global —
        bug-pascal-class-const-visibility. Only the untyped forms below are scoped;
        typed (`const X: T = ..`) class consts have real storage and stay global
        (rare; tracked as a follow-up). The bare name is captured first. }
      if ParsingClassConstCi >= 0 then
      begin
        if ClassConstCount >= MAX_TYPEALIAS then Error('too many class constants');
        ClassConstCi[ClassConstCount]   := ParsingClassConstCi;
        ClassConstName[ClassConstCount] := name;
        ClassConstVis[ClassConstCount]  := ParsingClassConstVis;
        Inc(ClassConstCount);
        name := ClassConstMangle(ParsingClassConstCi, name);
      end;
      if (CurTok.Kind = tkLBrack) or
         ((CurTok.Kind = tkIdent) and (FindSetConst(CurTok.SVal) >= 0)) then
      begin
        { Untyped set constant `const S = [1,2,3]`: bake a plain-ordinal set mask
          (no element enum type) and record it; uses resolve to AN_SET_CONST_REF.

          The value may be a set EXPRESSION, not just a literal -- `S2 = S1 - [b]` --
          so it can also START with the name of an earlier set constant. Without that
          second test the name fell through to the integer const path and died in
          ConstEval. }
        if SetConstCount >= MAX_TYPEALIAS then Error('too many set constants');
        SetConstName[SetConstCount]   := name;
        SetConstEnumId[SetConstCount] := -1;
        SetConstOff[SetConstCount]    := BakeSetConst;
        SetConstUnitIdx[SetConstCount] := CurrentUnitIdx; Inc(SetConstCount);
      end
      else if (CurTok.Kind = tkString) or
              ((CurTok.Kind = tkIdent) and (FindStrConst(CurTok.SVal) >= 0)) or
              ((CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind = tkPlus) and
               (CharConstSymOf(CurTok.SVal) >= 0)) then
      begin
        if (CurTok.Kind = tkIdent) or (Tokens[TokPos].Kind = tkPlus) then
        begin
          { `+`-concatenation of string/char literals and NAMED string consts,
            e.g. `const T = #65 + #66`, `'foo' + 'bar'`, or blcksock's
            `CRLF = CR + LF` (CR/LF are prior #$0d/#$0a consts). #65 and 'A'
            both arrive as tkString tokens whose decoded value is in SVal; a
            named const contributes its recorded TokChars span. Build the
            concatenated value into a fresh TokChars span and point the string
            const at it; a use expands to an AN_STR_LIT over that span, like a
            single literal (bug-char-literal-concat-in-const-expr). A single
            named-const operand (`A = CR;`) shares the source span. }
          scOff := TokCharLen; scLen := 0;
          repeat
            if CurTok.Kind = tkString then
            begin
              for si := 1 to Length(CurTok.SVal) do
              begin
                if TokCharLen >= STRING_CAP then Error('string constant buffer overflow');
                TokChars[TokCharLen] := CurTok.SVal[si]; Inc(TokCharLen); Inc(scLen);
              end;
            end
            else if (CurTok.Kind = tkIdent) and (FindStrConst(CurTok.SVal) >= 0) then
            begin
              sci2 := FindStrConst(CurTok.SVal);
              for si := StrConstSOff[sci2] to StrConstSOff[sci2] + StrConstSLen[sci2] - 1 do
              begin
                if TokCharLen >= STRING_CAP then Error('string constant buffer overflow');
                TokChars[TokCharLen] := TokChars[si]; Inc(TokCharLen); Inc(scLen);
              end;
            end
            else if (CurTok.Kind = tkIdent) and (CharConstSymOf(CurTok.SVal) >= 0) then
            begin
              { a named CHAR const as an operand — `const Sep = '/'; P = Sep + 'x'`.
                One-character untyped consts are typed Char now
                (bug-pascal-ord-of-a-one-char-string-const-is-its-address), so
                blcksock's `CRLF = CR + LF` shape reaches this arm instead of the
                string-const one above; without it the whole concatenation fell
                through to the integer ConstEval path and produced garbage. }
              if TokCharLen >= STRING_CAP then Error('string constant buffer overflow');
              TokChars[TokCharLen] := Chr(Syms[CharConstSymOf(CurTok.SVal)].ConstVal and $FF);
              Inc(TokCharLen); Inc(scLen);
            end
            else if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'LineEnding') then
            begin
              { System.LineEnding — FPC has it with no `uses`, and fcl-fpcunit builds its
                message formats out of it (`'Expected:' + LineEnding + '"%s"'`). A
                FALLBACK, reached only after FindStrConst misses, so a source that
                declares its own LineEnding still wins — registering it up front would
                shadow that, which is the trap bug-pascal-builtin-pointer-type-cast
                records. Posix line ending; Windows is not a target. }
              if TokCharLen >= STRING_CAP then Error('string constant buffer overflow');
              TokChars[TokCharLen] := #10; Inc(TokCharLen); Inc(scLen);
            end
            else
              Error('const string concatenation: expected a string/char literal or string constant');
            Next;
          until not Eat(tkPlus);
          if StrConstCount >= MAX_TYPEALIAS then Error('too many string constants');
          StrConstName[StrConstCount] := name;
          StrConstOwner[StrConstCount] := CurProc;
          StrConstSOff[StrConstCount] := scOff;
          StrConstSLen[StrConstCount] := scLen;
          StrConstUnitIdx[StrConstCount] := CurrentUnitIdx; Inc(StrConstCount);
        end
        else if Tokens[TokPos-1].SLen = 1 then
        begin
          { A ONE-CHARACTER untyped constant is a CHAR, which is what FPC types
            it as — not a string of length one. Registered as a char const here,
            at the point of CLASSIFICATION, rather than teaching each consumer
            to recognise a one-character AN_STR_LIT: measured against FPC 3.2.2,
            SIX consumers were wrong for `const C = 'z'`, not one —

              Ord(C)            gave the string's ADDRESS (4288109) not 122
              c := C            gave a byte of the address, not 'z'
              Chr(Ord(C))       likewise
              C in ['a','z']    FALSE
              Ord(Succ(C))      an address again
              (case C of / C = 'z' were the only two that worked)

            so a fix at any one consumer would have left the other five, which
            is the two-mechanisms-for-one-concept smell
            devdocs/dev/normalise-dont-special-case.md names.
            String contexts keep working because a Char already converts into
            them: `C + 'x'`, assigning to an AnsiString, and passing to a
            string parameter all go through the existing char->string paths.
            bug-pascal-ord-of-a-one-char-string-const-is-its-address }
          AddConst(name, tyChar, Ord(TokChars[Tokens[TokPos-1].SOffset]));
          Next;
        end
        else
        begin
          { Untyped string constant: remember the literal's source span; a use of
            the name builds an AN_STR_LIT over it. }
          if StrConstCount >= MAX_TYPEALIAS then Error('too many string constants');
          StrConstName[StrConstCount] := name;
          StrConstOwner[StrConstCount] := CurProc;
          StrConstSOff[StrConstCount] := Tokens[TokPos-1].SOffset;
          StrConstSLen[StrConstCount] := Tokens[TokPos-1].SLen;
          StrConstUnitIdx[StrConstCount] := CurrentUnitIdx; Inc(StrConstCount);
          Next;
        end;
      end
      else if (CurTok.Kind = tkFloat) or
              ((CurTok.Kind = tkMinus) and (Tokens[TokPos].Kind = tkFloat)) or
              ((CurTok.Kind = tkPlus) and (Tokens[TokPos].Kind = tkFloat)) or
              ConstExprIsFloat then
      begin
        { Untyped real constant (`const EPS = 0.001;` / `= -2.5` / `= 1e-9`). FPC
          infers a real-typed const. Store the IEEE-754 double bits tagged
          tyDouble (sign handled by ParseInitVal); a use builds an AN_FLOAT_LIT. }
        AddConst(name, tyDouble, ParseInitVal);
      end
      else if (CurTok.Kind in [tkTrue, tkFalse]) and
              (Tokens[TokPos].Kind = tkSemicolon) then
      begin
        { Untyped BOOLEAN constant (`const S = True;`). ConstEval collapses it
          to an integer, which then boxed as vtInteger in `array of const` —
          fpjson's TJSONArray.Create([S]) built a NUMBER element for a Boolean
          (FPC: vtBoolean). Bare True/False only; a folded boolean EXPRESSION
          still lands in the integer path below. }
        if CurTok.Kind = tkTrue then v := 1 else v := 0;
        Next;
        AddConst(name, tyBoolean, v);
      end
      else
      begin
        v := ConstEval;
        { Widen to Int64 when the value does not fit a 32-bit Integer. The value
          itself always survived (ConstVal is an Int64); it was the declared TYPE
          that collapsed, so the 32-bit backends materialized only the low word
          and sign-extended it — `const K = UInt64($FFFFFFFF00000001)` loaded as
          1 on i386/arm32/riscv32 while being right on x86-64, where every
          register is 64 bits wide and the truncation could not show
          (bug-64bit-named-const-truncated-32bit-targets). Small constants stay
          tyInteger so nothing else moves. }
        if (v > 2147483647) or (v < -2147483648) then
          AddConst(name, tyInt64, v)
        else
          AddConst(name, tyInteger, v);
      end;
    end;
    SkipHintDirectives;   { const K = v deprecated; }
    Eat(tkSemicolon);
  end;
  ParsingClassConstCi := savedCCi; ParsingClassConstVis := savedCVis;
end;

{ Parse a variant part `case [tag:] T of c1,..: (fields); ...` into UCls
  entry `ci`, starting with CurTok on the `case` keyword. All branches are a
  union — their fields share the same base offset, and the record grows by
  the largest branch. A branch body may itself end in a nested variant part
  (`case f: T of` inside the parens — synsock's TVarSin), handled by direct
  recursion; a tagged discriminant declares its tag as an ordinary field at
  the variant offset; const case labels are skipped like any label list.
  Stops (without consuming) at the record's `end` (top level) or the
  enclosing branch's `)` (nested). Returns the field offset just past the
  variant part (base + largest branch). Scalar / fixed-array / record branch
  fields are supported. }
function ParseRecordVariantPart(ci: Integer; isPackedRecord: Boolean;
  startOff: Integer; var classAlign: Integer): Integer;
var
  variantBaseOff, variantMax, branchFieldOff, curOff: Integer;
  arrLen, loVal, hiVal, fRec, fSize, fAlign, nFldNames, fni: Integer;
  fStrCap: Integer;
  isArr: Boolean;
  fTk: TTypeKind;
  fldNOffs: array[0..15] of Integer;   { comma-separated field-name spans }
  fldNLens: array[0..15] of Integer;
  vFirstFld, vMaxAlign, vNewBase, vDelta, vfi: Integer;
begin
  curOff := startOff;
  vMaxAlign := 1;
  Next;   { consume 'case' }
  if (CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind = tkColon) then
  begin
    { discriminant is also a real (tag) field: `case tag: T of` }
    fldNOffs[0] := Tokens[TokPos-1].SOffset; fldNLens[0] := Tokens[TokPos-1].SLen;
    Next; Next;   { tag name, ':' }
    fTk := ParseTypeKind; fRec := LastTypeRecId;
    if fTk = tyRecord then fSize := RecSize(fRec) else fSize := TypeSize(fTk);
    fAlign := TypeAlign(fTk);
    if isPackedRecord then fAlign := 1;
    curOff := AlignTo(curOff, fAlign);
    AddUField(ci, fldNOffs[0], fldNLens[0], curOff, Ord(fTk), fRec);
    UFldIsArray[UFldCount-1] := False; UFldArrLen[UFldCount-1] := 1;
    UFldDynDepth[UFldCount-1] := 0;
    curOff := curOff + fSize;
    if fAlign > classAlign then classAlign := fAlign;
  end
  else
    ParseTypeKind;   { discriminant type only (no field) }
  Expect(tkOf, 'of');
  if isPackedRecord then
    variantBaseOff := curOff   { packed: branches overlay right after the tag }
  else
    variantBaseOff := AlignTo(curOff, TARGET_PTR_SIZE);
  { Laid out from a base that satisfies EVERY alignment, then shifted back down
    to the alignment the branches actually need — because that need is only
    known once they are parsed, and laying out from an under-aligned base would
    change the fields' offsets RELATIVE to each other. The shift is a multiple
    of the branch alignment, so those relative offsets survive it.

    Without the shift the variant part always began on an 8-byte boundary, and
    `record case k: Integer of 0: (i: Integer) end` measured 12 bytes where FPC
    says 8 — the tag's own 4 bytes of padding, charged twice. Values were right
    (the branches do overlay), so this is a LAYOUT divergence: SizeOf, the
    stride of an array of the record, and anything reading such a record from a
    file or a C library. bug-p-a-tagged-variant-record-is-padded-to-eight }
  vFirstFld := UFldCount;
  variantMax := 0;
  while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkRParen) and
        (CurTok.Kind <> tkEOF) do
  begin
    { constant label list, e.g. `0, 1:` / `true:` / `AF_INET:` — skip to ':' }
    while (CurTok.Kind <> tkColon) and (CurTok.Kind <> tkEOF) do Next;
    Expect(tkColon, ':');
    Expect(tkLParen, '(');
    branchFieldOff := variantBaseOff;
    while (CurTok.Kind <> tkRParen) and (CurTok.Kind <> tkEOF) do
    begin
      if CurTok.Kind = tkCase then
      begin
        { nested variant part — grammatically the last item of the branch }
        branchFieldOff := ParseRecordVariantPart(ci, isPackedRecord,
          branchFieldOff, classAlign);
        break;
      end;
      if CurTok.Kind <> tkIdent then Error('expected field name in variant part');
      fldNOffs[0] := Tokens[TokPos-1].SOffset; fldNLens[0] := Tokens[TokPos-1].SLen;
      nFldNames := 1; Next;
      while CurTok.Kind = tkComma do
      begin
        Next;
        if CurTok.Kind <> tkIdent then Error('expected field name after ","');
        fldNOffs[nFldNames] := Tokens[TokPos-1].SOffset; fldNLens[nFldNames] := Tokens[TokPos-1].SLen;
        Inc(nFldNames); Next;
      end;
      Expect(tkColon, ':');
      isArr := False; arrLen := 1;
      if CurTok.Kind = tkArray then
      begin
        Next; Expect(tkLBrack, '[');
        { Through ParseArrayDimBounds, like every other array-bound site: a whole
          ordinal TYPE as the index (`array[Byte]`, `array[TKind]`) as well as the
          `lo..hi` const-expression form. See the class-field site above --
          normalise-dont-special-case: this was the same concept's third copy. }
        ParseArrayDimBounds(loVal, hiVal);
        arrLen := hiVal - loVal + 1;
        Expect(tkRBrack, ']'); Expect(tkOf, 'of');
        fTk := ParseTypeKind; fRec := LastTypeRecId; isArr := True;
      end
      else
      begin fTk := ParseTypeKind; fRec := LastTypeRecId; end;
      { Frozen strings, exactly as the FIXED part of the record does it a few
        hundred lines down. This arm was simply absent: a `string[N]` branch got
        TypeSize(tyFixedString) = 8 bytes and was registered as tyFixedString
        rather than tyString+UFldStrCap. So the field READ back as an address
        (`v.s` printed a number) AND the record was undersized — a `case` with a
        `string[40]` branch measured 16 bytes where it needs 52, so writing the
        field ran past the end of the record. Silent both ways.
        bug-a-a-frozen-string-field-in-a-variant-part-is-8-bytes-and-untyped }
      fStrCap := 0;
      if fTk = tyString then
      begin
        fSize := LOCAL_STR_CAP + 8;
        fAlign := TARGET_PTR_SIZE;
      end
      else if (fTk = tyFixedString) or (fTk = tyShortString) then
      begin
        fStrCap := LastTypeStrCap;
        if fStrCap <= 0 then fStrCap := DEFAULT_STR_CAP;
        fSize := FrozenStrSlotSize(fTk, fStrCap);
        fAlign := TARGET_PTR_SIZE;
      end
      else
      begin
        if fTk = tyRecord then fSize := RecSize(fRec) else fSize := TypeSize(fTk);
        fAlign := TypeAlign(fTk);
      end;
      if isPackedRecord then fAlign := 1;
      if isArr then fSize := fSize * arrLen;
      for fni := 0 to nFldNames - 1 do
      begin
        branchFieldOff := AlignTo(branchFieldOff, fAlign);
        if fStrCap > 0 then
        begin
          AddUField(ci, fldNOffs[fni], fldNLens[fni], branchFieldOff, Ord(tyString), fRec);
          UFldStrCap[UFldCount-1] := fStrCap;
        end
        else
          AddUField(ci, fldNOffs[fni], fldNLens[fni], branchFieldOff, Ord(fTk), fRec);
        UFldIsArray[UFldCount-1] := isArr;
        UFldArrLen[UFldCount-1] := arrLen;
        UFldDynDepth[UFldCount-1] := 0;
        { …and its LOW BOUND, exactly as the fixed part records it. This site is
          the third copy of the same concept (the comment on the bounds parse
          above says so) and it was the copy that still indexed from the raw
          index: `case Integer of 1: (arr: array[1..2] of SmallInt)` overlaid the
          branch two bytes into the tag's neighbour, so `v.arr[1]` read the HIGH
          half of the 0-branch's first field.
          bug-p-record-field-array-with-a-non-zero-low-bound-writes-out-of-bounds }
        if isArr then UFldArrDimLo[(UFldCount-1) * MAX_ARR_DIMS] := loVal;
        branchFieldOff := branchFieldOff + fSize;
      end;
      if fAlign > classAlign then classAlign := fAlign;
      if fAlign > vMaxAlign then vMaxAlign := fAlign;
      Eat(tkSemicolon);
    end;
    Expect(tkRParen, ')');
    Eat(tkSemicolon);
    if (branchFieldOff - variantBaseOff) > variantMax then
      variantMax := branchFieldOff - variantBaseOff;
  end;
  { the shift promised above; a packed record already starts right after the tag }
  if not isPackedRecord then
  begin
    vNewBase := AlignTo(curOff, vMaxAlign);
    vDelta := variantBaseOff - vNewBase;
    if vDelta > 0 then
    begin
      for vfi := vFirstFld to UFldCount - 1 do
        UFldOff_[vfi] := UFldOff_[vfi] - vDelta;
      variantBaseOff := vNewBase;
    end;
  end;
  Result := variantBaseOff + variantMax;
end;

{ Parse a record body's fields into UCls entry `ci`, from just after the
  `record` keyword through its closing `end` (consumed). Shared by named
  records (ParseTypeSection) and anonymous inline records
  (ParseTypeKind's tkRecord/tkPacked case — feature-anonymous-record-type).
  Handles comma field lists, nested fixed/dynamic array fields, and
  case/variant sections; sets UClsSize_/UClsAlign. }
procedure ParseRecordPropertyDecl(ci: Integer);
{ `property Height: Longint read cy write cy;` inside a record. FPC's own RTL uses this —
  typshrdh.inc's TSize and TRect are records with properties — so nothing that includes them
  parses without it.

  Only the FIELD-BACKED form is supported, which is what those declarations are: read/write
  name an existing field, and the property is registered so `r.Height` resolves through the
  ordinary property path. A method-backed accessor on a record would need the record's own
  method table wired into the accessor lookup; it is rejected loudly rather than
  half-supported. }
var
  pnOff, pnLen, pri: Integer;
  rFOff, rFLen, wFOff, wFLen: Integer;
  rMOff, rMLen, wMOff, wMLen: Integer;
  pTk: TTypeKind;
  pRec: Integer;
begin
  Next;  { consume `property` }
  if not IsMemberNameTok then Error('expected record property name');
  pnOff := Tokens[TokPos-1].SOffset;
  pnLen := Tokens[TokPos-1].SLen;
  Next;

  Expect(tkColon, ':');
  pTk := ParseTypeKind;
  pRec := LastTypeRecId;

  rFOff := 0; rFLen := 0; rMOff := 0; rMLen := 0;
  wFOff := 0; wFLen := 0; wMOff := 0; wMLen := 0;

  { `read` / `write` are TOKENS here (tkRead / tkwrite — they double as the I/O builtins),
    not identifiers. Testing for tkIdent silently never matched. }
  while (CurTok.Kind = tkRead) or (CurTok.Kind = tkwrite) do
  begin
    { An accessor is either a FIELD (`read cy`) or a METHOD (`read getHeight`) — FPC's
      typshrdh.inc uses both, TSize field-backed and TRect method-backed. Which one it is
      is decided by looking it up, so the same syntax serves both. }
    if CurTok.Kind = tkRead then
    begin
      Next;
      if not IsMemberNameTok then Error('expected record property read accessor');
      if FindUField(ci, CurTok.SVal) >= 0 then
      begin
        rFOff := Tokens[TokPos-1].SOffset;
        rFLen := Tokens[TokPos-1].SLen;
      end
      else if FindUMeth(ci, CurTok.SVal) >= 0 then
      begin
        rMOff := Tokens[TokPos-1].SOffset;
        rMLen := Tokens[TokPos-1].SLen;
      end
      else
        Error('record property accessor is neither a field nor a method: ' + CurTok.SVal);
      Next;
    end
    else
    begin
      Next;
      if not IsMemberNameTok then Error('expected record property write accessor');
      if FindUField(ci, CurTok.SVal) >= 0 then
      begin
        wFOff := Tokens[TokPos-1].SOffset;
        wFLen := Tokens[TokPos-1].SLen;
      end
      else if FindUMeth(ci, CurTok.SVal) >= 0 then
      begin
        wMOff := Tokens[TokPos-1].SOffset;
        wMLen := Tokens[TokPos-1].SLen;
      end
      else
        Error('record property accessor is neither a field nor a method: ' + CurTok.SVal);
      Next;
    end;
  end;
  Eat(tkSemicolon);

  pri := AddUProperty(ci, pnOff, pnLen, Ord(pTk), pRec);
  UPropReadFOff[pri] := rFOff;  UPropReadFLen[pri] := rFLen;
  UPropReadMOff[pri] := rMOff;  UPropReadMLen[pri] := rMLen;
  UPropWriteFOff[pri] := wFOff; UPropWriteFLen[pri] := wFLen;
  UPropWriteMOff[pri] := wMOff; UPropWriteMLen[pri] := wMLen;
  UPropPub[pri] := 0;
end;

procedure ParseRecordMethodDecl(ci: Integer);
{ A method SIGNATURE inside an advanced record ({$modeswitch advancedrecords} in FPC; its
  own RTL leans on it — TPoint/TSize/TRect are all advanced records).

  A record method is an ordinary method whose implicit Self is the RECORD, passed BY
  REFERENCE. There is no VMT: records have no inheritance, so every call is static, which
  makes this far smaller than the class-method path. The IMPLEMENTATION side is the shared
  ParseSubroutine — FindUClass already finds record rows, and its Self injection is now
  record-aware.

  Registers the proc as `TRec.Method` with Self at param 0 and adds a UMeth entry, which is
  what makes `r.Method(...)` resolve through the ordinary member-call path. }
var
  isFunc, byref, sawConst, isCtor: Boolean;
  mname, recNm, fullNm: AnsiString;
  mnOff, mnLen, mpi, i, nP, startIdx, k: Integer;
  retPtrElemTk, retPtrElemRec: Integer;   { A pointer RETURN type's element kind, captured at the declaration exactly like
    mRetRecId above it. Without it a DECL-only PChar method — abstract, or an
    interface method, the two shapes whose call resolves to the DECL's procIdx and
    never to an implementation's — leaves ProcRetPtrElemTk = tyUnknown, IsNodePChar
    answers False, and `AnsiString(ref.GetP())` lowers as a raw pointer cast:
    an EMPTY string where FPC gives the text. Silent wrong value, no diagnostic.
    refactor-centralize-managed-string-pchar-conversion }
  pn: array[0..MAX_PROC_PARAMS-1] of AnsiString;
  pt: array[0..MAX_PROC_PARAMS-1] of TTypeKind;
  ptRec: array[0..MAX_PROC_PARAMS-1] of Integer;
  pRef: array[0..MAX_PROC_PARAMS-1] of Boolean;
  rmHasDef, rmStrDef, rmArr: array[0..MAX_PROC_PARAMS-1] of Boolean;
  rmFloatDef, rmSetDef: array[0..MAX_PROC_PARAMS-1] of Boolean;
  rmIsArr: Boolean;
  rmValDef: array[0..MAX_PROC_PARAMS-1] of Int64;
  rmSOffDef, rmSLenDef: array[0..MAX_PROC_PARAMS-1] of Integer;
  rmDefVal: Int64;
  rmDefSOff, rmDefSLen: Integer;
  rmDefIsStr, rmDefIsFloat, rmDefIsSet: Boolean;
  curTk, retTk: TTypeKind;
  rmSawStatic: Boolean;
  rmMandatory: Integer;
begin
  for k := 0 to MAX_PROC_PARAMS - 1 do
  begin
    rmHasDef[k] := False; rmStrDef[k] := False; rmArr[k] := False;
    rmFloatDef[k] := False; rmSetDef[k] := False;
    rmValDef[k] := 0; rmSOffDef[k] := 0; rmSLenDef[k] := 0;
  end;
  rmDefVal := 0; rmDefSOff := 0; rmDefSLen := 0;
  rmDefIsStr := False; rmDefIsFloat := False; rmDefIsSet := False;
  { A record CONSTRUCTOR fills a fresh receiver rather than returning anything, so it
    registers exactly like a procedure whose Self is the record. Only the CALL differs. }
  isCtor := (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'constructor');
  if isCtor then isFunc := False
  else isFunc := CurTok.Kind = tkFunction;
  Next;
  if not IsMethodNameTok then Error('expected record method name');
  mname := GetTokenStr(TokPos - 1);   { keyword-token names carry no SVal }
  mnOff := Tokens[TokPos-1].SOffset;
  mnLen := Tokens[TokPos-1].SLen;
  Next;

  { Self at param 0: the record, by reference. For a TYPE HELPER, Self is a
    reference to the TARGET type instead (s.ToLower reads Self as the string). }
  nP := 1;
  pn[0] := 'Self';
  if UClsHelperTk[ci] >= 0 then
  begin
    pt[0] := IntToTypeKind(UClsHelperTk[ci]);
    ptRec[0] := UClsHelperRec[ci];
    { a `class function ...; static;` helper method takes Self BY VALUE (the
      body may not use Self, per FPC static rules) so a TYPE-NAME call site
      (TU32Helper.GetSignMask) can pass a dummy literal }
    pRef[0] := not RecordMethodClassPrefix;
  end
  else
  begin
    pt[0] := tyRecord;
    ptRec[0] := REC_UCLASS_BASE + ci;
    pRef[0] := True;
  end;

  if CurTok.Kind = tkLParen then
  begin
    Next;
    while CurTok.Kind <> tkRParen do
    begin
      byref := False; sawConst := False;
      if (CurTok.Kind = tkVar) or
         ((CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'out')) then
      begin byref := True; Next; end
      else if IsConstParamTok then begin sawConst := True; Next; end;

      startIdx := nP;
      while IsDeclNameTok do
      begin
        if nP >= MAX_PROC_PARAMS then Error('record method: too many parameters');
        pn[nP] := CurTok.SVal; Inc(nP); Next;
        if not Eat(tkComma) then break;
      end;
      Expect(tkColon, ':');
      { open-array param: `const Points: array of TPoint` (typshrdh.inc's TRect.Union) }
      rmIsArr := False;
      if CurTok.Kind = tkArray then
      begin
        { open-array param `const Points: array of TPoint` (typshrdh.inc's
          TRect.Union) — same shape as the class/interface method paths: the
          IsArray flag is all the CALLER needs (pxx open arrays carry their
          length INLINE at data-8; the shared arg builder adapts static
          arrays). The old segfault predated the unified call-arg path (b287);
          b334 pins call + High() + indexing. }
        Next;
        Expect(tkOf, 'of');
        rmIsArr := True;
      end;
      curTk := ParseTypeKind;
      for k := startIdx to nP - 1 do
      begin
        pt[k] := curTk;
        ptRec[k] := LastTypeRecId;
        rmArr[k] := rmIsArr;
        { a const record/variant param goes by reference, as everywhere else }
        pRef[k] := byref or (sawConst and ((curTk = tyRecord) or (curTk = tyVariant)));
      end;
      { default value: `Normalize: Boolean = False` (typshrdh.inc's TRect.Contains).
        Every shape, via the one shared parser — this site used to know only two
        of them. }
      if CurTok.Kind = tkEq then
      begin
        Next;
        ParseParamDefaultValue(curTk, rmDefVal, rmDefIsStr, rmDefIsFloat, rmDefIsSet,
                               rmDefSOff, rmDefSLen);
        for k := startIdx to nP - 1 do
        begin
          rmHasDef[k] := True;
          rmValDef[k] := rmDefVal;
          rmStrDef[k] := rmDefIsStr;
          rmFloatDef[k] := rmDefIsFloat;
          rmSetDef[k] := rmDefIsSet;
          rmSOffDef[k] := rmDefSOff;
          rmSLenDef[k] := rmDefSLen;
        end;
      end;
      if not Eat(tkSemicolon) then break;
    end;
    Expect(tkRParen, ')');
  end;

  retTk := tyInteger;
  LastTypeRecId := REC_NONE;
  retPtrElemTk := Ord(tyUnknown);
  retPtrElemRec := REC_NONE;
  if isFunc then
  begin
    Expect(tkColon, ':');
    retTk := ParseTypeKind;
    retPtrElemTk := Ord(LastTypePointerElemTk);
    retPtrElemRec := LastTypePointerElemRec;
  end;
  Eat(tkSemicolon);

  { parse-and-ignore directives: records have no VMT, so none of the dispatch ones mean
    anything here. `static` is the exception — it is REQUIRED on a record's class method
    (below), so its presence has to be observed rather than skipped. }
  rmSawStatic := False;
  while (CurTok.Kind = tkOverload) or IsCallConvDirectiveTok or
        ((CurTok.Kind = tkIdent) and
         (CaseEqual(CurTok.SVal, 'inline') or CaseEqual(CurTok.SVal, 'static') or
          CaseEqual(CurTok.SVal, 'deprecated'))) do
  begin
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'static') then rmSawStatic := True;
    Next;
    Eat(tkSemicolon);
  end;

  { A record's `class procedure` / `class function` must be `static` (terecs5). A
    non-static class method dispatches on the runtime metaclass, and a record has none —
    no VMT, no class reference. FPC rejects it; pxx used to consume `class` and treat the
    method as an ordinary one, so the declaration compiled and meant something else. }
  if RecordMethodClassPrefix and not rmSawStatic then
    Error('a class method of a record must be declared static');

  { A record CONSTRUCTOR needs at least one MANDATORY parameter (terecs17 / terecs17a).
    A record always exists — it is a value, not an allocation — so a parameterless ctor
    would be indistinguishable from the record's own default state and would collide with
    the implicit initialisation. FPC rejects both the no-parameter form and the form whose
    only parameter has a DEFAULT, since that one is still callable with none: terecs17a's
    `constructor Create(I: integer = 0)` is the same hole spelled differently. }
  if isCtor then
  begin
    rmMandatory := 0;
    for k := 1 to nP - 1 do    { param 0 is the implicit Self — not a user parameter }
      if not rmHasDef[k] then rmMandatory := rmMandatory + 1;
    if rmMandatory = 0 then
      Error('a record constructor must have at least one parameter without a default value');
  end;

  recNm := GetTokenStrFromRaw(UClsNOff[ci], UClsNLen[ci]);
  fullNm := recNm + '.' + mname;

  mpi := RegisterProc(fullNm, isFunc, retTk, nP, pn, pt);
  Procs[mpi].BodyAddr := -1;
  if isFunc and (retTk = tyPointer) then
  begin
    ProcRetPtrElemTk[mpi] := retPtrElemTk;
    ProcRetPtrElemRec[mpi] := retPtrElemRec;
  end;
  for i := 0 to nP - 1 do
  begin
    Procs[mpi].Params[i].IsRef := pRef[i];
    Procs[mpi].Params[i].IsArray := rmArr[i];
    if (pt[i] = tyRecord) or (pt[i] = tyClass) then
      ProcParamRecId[mpi * MAX_PROC_PARAMS + i] := ptRec[i];
    if rmHasDef[i] then
    begin
      ProcParamHasDefault[mpi * MAX_PROC_PARAMS + i] := True;
      ProcParamDefaultVal[mpi * MAX_PROC_PARAMS + i] := rmValDef[i];
      ProcParamDefaultIsStr[mpi * MAX_PROC_PARAMS + i] := rmStrDef[i];
      ProcParamDefaultIsFloat[mpi * MAX_PROC_PARAMS + i] := rmFloatDef[i];
      ProcParamDefaultIsSet[mpi * MAX_PROC_PARAMS + i] := rmSetDef[i];
      ProcParamDefaultSOff[mpi * MAX_PROC_PARAMS + i] := rmSOffDef[i];
      ProcParamDefaultSLen[mpi * MAX_PROC_PARAMS + i] := rmSLenDef[i];
    end;
  end;

  AddUMeth(ci, mnOff, mnLen, mpi);
  UMthIsStatic[UMthCount - 1] := RecordMethodClassPrefix;
  UMthIsCtor[UMthCount - 1] := isCtor;
  UMthVirSlot[UMthCount - 1] := -1;   { no VMT — records have no inheritance }
  UMthPub[UMthCount - 1] := 0;
end;

procedure ParseRecordFields(ci: Integer; isPackedRecord: Boolean);
var
  arrLen, curFieldOff, fAi, fAlign, fDynDepth, fRec, fSize, fStrCap: Integer;
  hiVal, loVal, i, nFldNames, fni, fNDims: Integer;
  tdLo, tdHi, tdi, classAlign: Integer;
  opDepth: Integer;   { paren nesting while skipping a `class operator` signature }
  isArr, fIsDyn: Boolean;
  fTk: TTypeKind;
  fldNOffs: array[0..15] of Integer;   { comma-separated field-name spans }
  fldNLens: array[0..15] of Integer;
  tdDimLo, tdDimSpan: array[0..MAX_ARR_DIMS-1] of Integer;
begin
  curFieldOff := 0;
  classAlign := 1;
  while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
  begin
    { `class var` inside a RECORD: no shared-storage model for record class
      vars in pxx (class-body class vars have one, see ParseTypeSection).
      FPC additionally forbids the local-type and anonymous-record contexts
      (terecs12c/terecs13c) — reject all three loudly instead of silently
      skipping the section (the old fall-through made TRec.X fail later with
      a misleading 'class method not found'). }
    if (CurTok.Kind = tkClass) and (TokPos < TokCount) and
       (Tokens[TokPos].Kind = tkVar) then
      Error('class var is not allowed in a record type');

    { `const` section inside a record — same treatment as in a class body, and
      that now means SCOPED to the record, not global.

      This used to pass -1 (no owner) on the reasoning that "a constant has no
      storage and pxx does not scope declarations, so there is nothing to
      scope". Both halves are false for a TYPED const (`const X: T = ...`),
      which FPC defines as writable storage with an initial value — so two
      records, or two type HELPERS, declaring the same const name shared one
      global slot and read each other's values, and `TRec.X` could not resolve
      it at all because no registry row existed.
      bug-p-two-classes-typed-consts-of-the-same-name-collide

      Visibility is passed as 0 (public): a record's sections are already
      restricted above (protected and published are refused outright), and
      record consts were never visibility-checked, so this keeps today's
      behaviour rather than quietly tightening it. }
    if CurTok.Kind = tkConst then
    begin
      ParseConstSection(ci, 0);
      continue;
    end;

    { ADVANCED members (visibility sections, consts, methods, properties) are only legal
      on a record type declared with a NAME in a type section at unit/program level.
      They are rejected on:
        - an ANONYMOUS inline record type (`var R: record ... end`) — it has no name, so
          a method could never be given an implementation (terecs13a/13b/13d);
        - a record type declared LOCALLY inside a routine — same problem: the
          implementation would have nowhere to live (terecs12a/12b).
      Plain FIELDS remain legal in both, which is the only thing either form is for.
      pxx used to accept the whole advanced surface here and silently register methods
      that could never be defined. }
    if (UClsNLen[ci] = 0) or (CurProc >= 0) then
    begin
      if (CurTok.Kind = tkProperty) or (CurTok.Kind = tkProcedure) or
         (CurTok.Kind = tkFunction) or (CurTok.Kind = tkConst) or
         (CurTok.Kind = tkClass) or
         ((CurTok.Kind = tkIdent) and
          (CaseEqual(CurTok.SVal, 'constructor') or CaseEqual(CurTok.SVal, 'strict') or
           CaseEqual(CurTok.SVal, 'private') or CaseEqual(CurTok.SVal, 'protected') or
           CaseEqual(CurTok.SVal, 'public') or CaseEqual(CurTok.SVal, 'published'))) then
      begin
        if UClsNLen[ci] = 0 then
          Error('an anonymous record type can only have fields (no methods, properties, consts or visibility sections)')
        else
          Error('a record type declared inside a routine can only have fields (no methods, properties, consts or visibility sections)');
      end;
    end;

    { ADVANCED RECORDS: visibility sections and methods. Access is still not ENFORCED
      (that is a separate job), but the sections a record may legally OPEN are checked —
      a record is not a class, and two of the four are meaningless on it:

        - `protected` / `strict protected` presuppose inheritance, and records do not
          inherit (terecs19);
        - `published` presupposes RTTI-driven streaming of an object, which a record has
          no place in (terecs2).

      Both used to be consumed and dropped, so the declaration compiled and the modifier
      silently meant nothing. }
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'strict') and
       (TokPos < TokCount) and (Tokens[TokPos].Kind = tkIdent) and
       (CaseEqual(GetTokenStr(TokPos), 'private') or
        CaseEqual(GetTokenStr(TokPos), 'protected')) then
    begin
      if CaseEqual(GetTokenStr(TokPos), 'protected') then
        Error('a record cannot have protected members (records do not inherit)');
      Next;
    end;
    if (CurTok.Kind = tkIdent) and
       (CaseEqual(CurTok.SVal, 'private') or CaseEqual(CurTok.SVal, 'protected') or
        CaseEqual(CurTok.SVal, 'public') or CaseEqual(CurTok.SVal, 'published')) then
    begin
      if CaseEqual(CurTok.SVal, 'protected') then
        Error('a record cannot have protected members (records do not inherit)');
      if CaseEqual(CurTok.SVal, 'published') then
        Error('a record cannot have a published section');
      Next;
      continue;
    end;
    if (CurTok.Kind = tkProcedure) or (CurTok.Kind = tkFunction) or
       ((CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'constructor')) then
    begin
      ParseRecordMethodDecl(ci);
      continue;
    end;
    if CurTok.Kind = tkProperty then
    begin
      ParseRecordPropertyDecl(ci);
      continue;
    end;
    { `class function` / `class procedure` in a record: consume the prefix and treat it as
      an ordinary record method. There is no per-instance state to distinguish, and pxx
      resolves the call the same way. }
    if (CurTok.Kind = tkClass) and (TokPos < TokCount) and
       ((Tokens[TokPos].Kind = tkProcedure) or (Tokens[TokPos].Kind = tkFunction)) then
    begin
      Next;
      RecordMethodClassPrefix := True;
      ParseRecordMethodDecl(ci);
      RecordMethodClassPrefix := False;
      continue;
    end;

    { `class operator + (const a, b: TPt): TPt;` inside a record — the SIGNATURE only. pxx
      keys an operator on its OPERAND TYPES, so the in-record declaration carries nothing the
      definition does not; it is parsed and discarded, and the `class operator TPt.+(...)`
      DEFINITION (top level) is what actually registers it. Skip to the terminating ';'. }
    if (CurTok.Kind = tkClass) and (TokPos < TokCount) and
       (Tokens[TokPos].Kind = tkIdent) and CaseEqual(GetTokenStr(TokPos), 'operator') then
    begin
      { Skip to the ';' that ENDS the signature — the one at paren depth 0. A
        parameter list separates groups with ';' too, so a depth-blind scan
        stopped inside the parens and left `k: Integer): TVec;` to be parsed as
        a field. That made every MIXED-TYPE operator a syntax error
        (`class operator * (const a: TVec; k: Integer): TVec`, i.e. scaling a
        vector — one of the commonest overloads there is), while the
        homogeneous `(const a, b: TVec)` form parsed fine because it has no
        inner ';'. bug-a-a-mixed-type-record-operator-signature-fails-to-parse }
      opDepth := 0;
      while ((CurTok.Kind <> tkSemicolon) or (opDepth > 0)) and
            (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
      begin
        if CurTok.Kind = tkLParen then Inc(opDepth)
        else if CurTok.Kind = tkRParen then Dec(opDepth);
        Next;
      end;
      Eat(tkSemicolon);
      continue;
    end;

    if CurTok.Kind = tkIdent then
    begin
      { comma-separated names share one type: `X, Y: Integer` }
      fldNOffs[0] := Tokens[TokPos-1].SOffset;
      fldNLens[0] := Tokens[TokPos-1].SLen;
      nFldNames := 1;
      Next;
      while CurTok.Kind = tkComma do
      begin
        Next;
        if CurTok.Kind <> tkIdent then Error('expected field name after ","');
        fldNOffs[nFldNames] := Tokens[TokPos-1].SOffset;
        fldNLens[nFldNames] := Tokens[TokPos-1].SLen;
        Inc(nFldNames);
        Next;
      end;
      Expect(tkColon, ':');
      isArr := False;
      arrLen := 1;
      fIsDyn := False;
      fDynDepth := 0;
      fNDims := 0;
      { `entries: packed array[0..0] of TRec;` (fcl-fpcunit's testutils) — `packed`
        is legal on an array field, not just on a record. It only affects ELEMENT
        padding, and pxx already lays array elements out contiguously, so it is
        accepted and the array parsed exactly as an unpacked one. Without this the
        field type parser fell through to ParseTypeKind, whose tkPacked case assumes
        a record and demanded one. }
      if (CurTok.Kind = tkPacked) and (TokPos < TokCount) and
         (Tokens[TokPos].Kind = tkArray) then
        Next;
      if CurTok.Kind = tkArray then
      begin
        Next;
        if CurTok.Kind = tkLBrack then
        begin
          Next;
          { Bounds through ParseArrayDimBounds: const EXPRESSIONS (`0..N - 1`,
            bug-inline-array-field-const-bound) and a whole ordinal TYPE as the
            index (`array[Byte]`, `array[TKind]`) alike. }
          ParseArrayDimBounds(loVal, hiVal);
          arrLen := hiVal - loVal + 1;
          { N-D field: collect dim0 then any comma dims. }
          fNDims := 1; tdDimLo[0] := loVal; tdDimSpan[0] := hiVal - loVal + 1;
          while CurTok.Kind = tkComma do
          begin
            Eat(tkComma);
            ParseArrayDimBounds(tdLo, tdHi);
            if fNDims >= MAX_ARR_DIMS then Error('too many array dimensions');
            tdDimLo[fNDims] := tdLo; tdDimSpan[fNDims] := tdHi - tdLo + 1;
            arrLen := arrLen * tdDimSpan[fNDims];
            Inc(fNDims);
          end;
          Expect(tkRBrack, ']');
          Expect(tkOf, 'of');
          fTk := ParseTypeKind;
          fRec := LastTypeRecId;
          isArr := True;
        end
        else
        begin
          { Dynamic-array field: `array of T`, including nested. }
          fIsDyn := True;
          fDynDepth := 1;
          Expect(tkOf, 'of');
          while CurTok.Kind = tkArray do
          begin
            Next;
            Inc(fDynDepth);
            Expect(tkOf, 'of');
          end;
          fTk := ParseTypeKind;
          fRec := LastTypeRecId;
        end;
      end
      else
      begin
        { Named dynamic-array type field (`TDynArr = array of T`): mirror
          the inline `array of T` field so SetLength/Length/indexing see a
          real dynamic array. Without this the field's UFldDynDepth stayed
          0 and SetLength(Self.field, n) misrouted to the string path. }
        fAi := -1;
        if CurTok.Kind = tkIdent then fAi := FindArrayType(CurTok.SVal);
        if (fAi >= 0) and ArrTypeIsDyn[fAi] then
        begin
          fIsDyn := True;
          fDynDepth := ArrTypeDynDepth[fAi];
          fTk := IntToTypeKind(ArrTypeElemTk[fAi]);
          fRec := ArrTypeElemRec[fAi];
          { AddUField reads the pointee record for a tyPointer field straight off
            the LastTypePointerElemRec global -- prime it here (see
            ArrTypePtrElemRec's comment in defs.inc for the general landmine). }
          LastTypePointerElemRec := ArrTypePtrElemRec[fAi];
          Next;   { consume the named array type }
        end
        else if (fAi >= 0) and (not ArrTypeIsDyn[fAi]) then
        begin
          { Named FIXED-array type field (`a: TG`, `TG = array[..] of T`):
            make it a real array field (1-D or flattened N-D) so a.x[i]
            indexes with the right stride. Without this ParseTypeKind drops
            TG's dimension and the field collapses to a single base element
            (corrupting r.field[i] and r.field passed as a var array arg). }
          isArr := True;
          fTk := IntToTypeKind(ArrTypeElemTk[fAi]);
          fRec := ArrTypeElemRec[fAi];
          LastTypePointerElemRec := ArrTypePtrElemRec[fAi];
          if ArrTypeNDims[fAi] >= 2 then
          begin
            fNDims := ArrTypeNDims[fAi];
            arrLen := 1;
            for tdi := 0 to fNDims - 1 do
            begin
              tdDimLo[tdi]   := ArrTypeDimLo[fAi * MAX_ARR_DIMS + tdi];
              tdDimSpan[tdi] := ArrTypeDimSpan[fAi * MAX_ARR_DIMS + tdi];
              arrLen := arrLen * tdDimSpan[tdi];
            end;
          end
          else
          begin
            fNDims := 1;
            tdDimLo[0]   := ArrTypeLo[fAi];
            tdDimSpan[0] := ArrTypeHi[fAi] - ArrTypeLo[fAi] + 1;
            arrLen := tdDimSpan[0];
          end;
          Next;   { consume the named array type }
        end
        else
        begin
          fTk := ParseTypeKind;
          fRec := LastTypeRecId;
        end;
      end;
      if fIsDyn then
      begin
        fSize := TARGET_PTR_SIZE;
        fAlign := TARGET_PTR_SIZE;
      end
      else if fTk = tyString then
      begin
        fSize := LOCAL_STR_CAP + 8;
        fAlign := TARGET_PTR_SIZE;
      end
      else if fTk = tyFixedString then
      begin
        { `string[N]` field: inline [len:8][chars:N] slot, same layout as a
          tyString field but capacity N. Stored as tyString (identical read/
          write codegen) with UFldStrCap = N driving the truncating store. }
        fStrCap := LastTypeStrCap;
        if fStrCap <= 0 then fStrCap := DEFAULT_STR_CAP;
        fSize := FrozenStrSlotSize(fTk, fStrCap);
        fAlign := TARGET_PTR_SIZE;
      end
      else if fTk = tyRecord then
      begin
        fSize := RecSize(fRec);
        if fRec >= REC_UCLASS_BASE then
          fAlign := UClsAlign[fRec - REC_UCLASS_BASE]
        else
          fAlign := TARGET_PTR_SIZE;
      end
      else
      begin
        fSize := TypeSize(fTk);
        fAlign := TypeAlign(fTk);
      end;
      if isPackedRecord then
        fAlign := 1
      else if fAlign > TokPackRecords[TokPos - 1] then
        fAlign := TokPackRecords[TokPos - 1];
      if isArr then
        fSize := fSize * arrLen;
      { A by-value field of the record's OWN type (direct or transitive) is
        infinitely recursive — FPC rejects it (terecs9); pxx used to lay out a
        zero-sized field silently. Dynarray fields (heap indirection) are fine
        and skipped by the walk. }
      if (fTk = tyRecord) and (not fIsDyn) and (fRec <> REC_NONE) and
         RecContainsRecId(fRec, REC_UCLASS_BASE + ci) then
        Error('record field cannot be of the enclosing record type');
      for fni := 0 to nFldNames - 1 do
      begin
        curFieldOff := AlignTo(curFieldOff, fAlign);
        if fTk = tyFixedString then
        begin
          AddUField(ci, fldNOffs[fni], fldNLens[fni], curFieldOff, Ord(tyString), fRec);
          UFldStrCap[UFldCount-1] := fStrCap;
        end
        else
          AddUField(ci, fldNOffs[fni], fldNLens[fni], curFieldOff, Ord(fTk), fRec);
        UFldIsArray[UFldCount-1] := isArr or fIsDyn;
        if fIsDyn then UFldArrLen[UFldCount-1] := -1
        else UFldArrLen[UFldCount-1] := arrLen;
        UFldDynDepth[UFldCount-1] := fDynDepth;
        if fNDims >= 2 then
        begin
          UFldArrNDims[UFldCount-1] := fNDims;
          for tdi := 0 to fNDims - 1 do
          begin
            UFldArrDimLo[(UFldCount-1) * MAX_ARR_DIMS + tdi]   := tdDimLo[tdi];
            UFldArrDimSpan[(UFldCount-1) * MAX_ARR_DIMS + tdi] := tdDimSpan[tdi];
          end;
        end
        else if isArr and (not fIsDyn) then
          { 1-D static array field: record its LOW BOUND in dim 0 of the same table.
            UFldArrNDims deliberately stays 0 — nothing dispatches differently — this
            is only where the index lowering reads a field array's `lo` from. Without
            it the low was never subtracted: `array[1..3]` wrote one element past its
            extent and `array[-2..2]` two before it, corrupting the neighbouring field
            (or, on a class, the object header — Free then segfaulted).
            bug-p-record-field-array-with-a-non-zero-low-bound-writes-out-of-bounds }
          UFldArrDimLo[(UFldCount-1) * MAX_ARR_DIMS] := tdDimLo[0];
        curFieldOff := curFieldOff + fSize;
      end;
      if fAlign > classAlign then classAlign := fAlign;
      Eat(tkSemicolon);
    end
    else if CurTok.Kind = tkCase then
      { Variant part — see ParseRecordVariantPart. (Previously `case` fell to
        the skip-`else` below, so branch fields were laid out sequentially
        and r.i:=x; r.c read 0.) }
      curFieldOff := ParseRecordVariantPart(ci, isPackedRecord, curFieldOff,
        classAlign)
    else
      Next;
  end;
  UClsSize_[ci] := AlignTo(curFieldOff, classAlign);
  UClsAlign[ci] := classAlign;
  Expect(tkEnd, 'end');
end;

function QualClassAliasCi: Integer;
{ `T = someunit.TClass;` — the class row someunit declares, or -1 when the shape
  ahead is not a unit-qualified class alias. Pure lookahead: consumes nothing.

  The UNQUALIFIED alias branch in ParseTypeSection cannot answer this. Its
  lookahead requires a semicolon immediately after the first identifier, so a
  qualified target fell through to the plain-type-alias path and no UClass alias
  row was ever registered — `TThread = palthreadobj.TThread;` in classes.pas was
  a no-op, and `uses Classes` never got TThread. Invisible for as long as `uses`
  was transitive, because the importer then found palthreadobj's row directly
  through the leak; closing the leak (2026-08-15, VisibilityAllows) is what made
  the dead re-export observable.

  Requires the qualifier to name a real UNIT. `TOuter.TInner` is a NESTED type,
  not a re-export, and aliasing it to the flat first match of `TInner` is the
  bind-to-the-wrong-class failure the duplicate-class work exists to prevent —
  so an unresolvable qualifier declines here and the general-alias path keeps it.
  bug-p-unit-qualified-class-alias-is-never-registered }
var ti, u: Integer; qn, mem: AnsiString;
begin
  Result := -1;
  if CurTok.Kind <> tkIdent then Exit;
  if (TokPos >= TokCount) or (Tokens[TokPos].Kind <> tkDot) then Exit;
  qn := CurTok.SVal;
  mem := '';
  ti := TokPos;                       { points at the first '.' }
  { Split the dotted name: every `.ident` with a further `.ident` behind it
    belongs to the unit name (`System.Generics.Collections.TList`); the last one
    is the member. }
  while (ti + 1 < TokCount) and (Tokens[ti].Kind = tkDot) and
        (Tokens[ti + 1].Kind = tkIdent) do
  begin
    if (ti + 3 < TokCount) and (Tokens[ti + 2].Kind = tkDot) and
       (Tokens[ti + 3].Kind = tkIdent) then
    begin
      AppendChar(qn, '.');
      AppendString(qn, GetTokenStr(ti + 1));
      ti := ti + 2;
    end
    else
    begin
      mem := GetTokenStr(ti + 1);
      ti := ti + 2;
      Break;
    end;
  end;
  if mem = '' then Exit;
  if (ti >= TokCount) or (Tokens[ti].Kind <> tkSemicolon) then Exit;
  u := PyFindUnitDotted(qn);
  if u < 0 then Exit;
  Result := FindUClassInUnit(mem, u);
end;

function ParseProcTypeSignature: Integer;
{ `procedure(...)` / `function(...): R` — the SIGNATURE only, from the keyword
  up to (not including) any `of object`. Returns the body-less Procs[] index
  that AliasProcSig / SymProcSig carry so an indirect call `v(args)` marshals
  args and return value through the same machinery as a direct call.

  Extracted from ParseTypeSection's named-alias arm, which was the only place
  that could parse this. That is why `cb: procedure(l: LongInt)` written inline
  — as a record field, a var, or a parameter — was a hard syntax error while the
  identical shape behind a named alias worked: the grammar lived in the naming
  path instead of in the type path.
  bug-a-an-anonymous-procedural-type-is-not-accepted }
var
  mIsFunc, mDoneArgs, mIsByRef, mSawConst, mDoneParam, mIsArr: Boolean;
  mNParams, mStartIdx, mpi, i: Integer;
  mRetType, mTk: TTypeKind;
  mPNames: array[0..MAX_PROC_PARAMS-1] of AnsiString;
  mPTypes: array[0..MAX_PROC_PARAMS-1] of TTypeKind;
  mPTypesRec: array[0..MAX_PROC_PARAMS-1] of Integer;
  mPArr, mPByRef: array[0..MAX_PROC_PARAMS-1] of Boolean;
begin
      mIsFunc := (CurTok.Kind = tkFunction);
      Next;
      mNParams := 0;
      mRetType := tyInteger;
      if CurTok.Kind = tkLParen then
      begin
        Next;
        mDoneArgs := False;
        while (CurTok.Kind <> tkRParen) and not mDoneArgs do
        begin
          mIsByRef := False;
          mSawConst := False;
          if (CurTok.Kind = tkVar) or
             ((CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'out')) then
          begin mIsByRef := True; Next; end
          else if IsConstParamTok then
          begin mSawConst := True; Next; end;
          mStartIdx := mNParams;
          mDoneParam := False;
          while IsDeclNameTok and not mDoneParam do
          begin
            mPNames[mNParams] := CurTok.SVal; Inc(mNParams); Next;
            if not Eat(tkComma) then mDoneParam := True;
            if CurTok.Kind = tkColon then mDoneParam := True;
          end;
          Expect(tkColon, ':');
          mIsArr := False;
          if CurTok.Kind = tkArray then
          begin
            Next; Expect(tkOf, 'of'); mTk := ParseTypeKind; mIsArr := True;
          end
          else
            mTk := ParseTypeKind;
          { A `const` record/variant param is passed by reference — must match
            ParseSubroutine's rule (pasparser_*.inc ~11403) so an INDIRECT call
            through this proc-type marshals the arg the same way the callee
            receives it (else the address/value mismatch segfaults — see
            bug-proc-typed-call-const-record-arg). }
          if mSawConst and ((mTk = tyRecord) or (mTk = tyVariant)) and not mIsArr then
            mIsByRef := True;
          for i := mStartIdx to mNParams-1 do
          begin
            mPTypes[i] := mTk;
            mPTypesRec[i] := LastTypeRecId;
            mPArr[i] := mIsArr;
            mPByRef[i] := mIsByRef;
          end;
          if not Eat(tkSemicolon) then mDoneArgs := True;
        end;
        Expect(tkRParen, ')');
      end;
      if mIsFunc then
      begin
        Expect(tkColon, ':');
        mRetType := ParseTypeKind;
      end;
      mpi := RegisterProc('$proctype', mIsFunc, mRetType, mNParams, mPNames, mPTypes);
      Procs[mpi].BodyAddr := -1;
      { Record the return pointer-element type on the signature (mRetType was the
        last type parsed above, so LastTypePointerElem* still describe it). Without
        this a `T = function(...): PAnsiChar` sig leaves ProcRetPtrElemTk at
        tyUnknown, so IsNodePChar can't tell an indirect call through T returns
        char* and `AnsiString(fp(...))` mis-lowers. Same dropped-field pattern as
        the external-decl path. See bug-pascal-ansistring-cast-of-fnptr-call-result. }
      if mIsFunc and (mRetType = tyPointer) then
      begin
        ProcRetPtrElemTk[mpi] := Ord(LastTypePointerElemTk);
        ProcRetPtrElemRec[mpi] := LastTypePointerElemRec;
      end;
      for i := 0 to mNParams-1 do
      begin
        Procs[mpi].Params[i].IsArray := mPArr[i];
        Procs[mpi].Params[i].IsRef := mPByRef[i];
      end;
  Result := mpi;
end;

procedure EatProcTypeCdecl(mpi: Integer);
{ Optional `; cdecl` on a procedural type (`T = function(...): R; cdecl;`).
  Marks the signature C-ABI so an indirect call through a value of this type
  marshals System V — needed for dlsym'd C functions. Other directives
  (stdcall etc.) are not modelled yet. Shared by the named and anonymous forms. }
begin
  if (CurTok.Kind = tkSemicolon) and (TokPos < TokCount) and
     (Tokens[TokPos].Kind = tkIdent) and CaseEqual(GetTokenStr(TokPos), 'cdecl') then
  begin
    Next;   { consume ';' }
    Next;   { consume 'cdecl' }
    ProcCdecl[mpi] := True;
  end;
end;

procedure ParseTypeSection;
{ Handles enum types, record/class type declarations }
var
  ordinal: Int64;
  tname: AnsiString;
  done, stopTypes: Boolean; loVal, hiVal, arrLen: Integer; isArr: Boolean; isPackedRecord: Boolean;
  fIsDyn: Boolean; fDynDepth: Integer; fAi: Integer; tMoreDims: Boolean;
  tnOff, tnLen, ci, fnOff, fnLen, curFieldOff, fRec, fSize, fStrCap, fAlign, classAlign, depth, targetNOff, targetNLen: Integer;
  subLoVal, subHiVal: Int64;
  variantBaseOff, variantMax, branchFieldOff: Integer;
  enumNOff, enumNLen: Integer; enumNm: AnsiString;
  fTk: TTypeKind;
  parentCi, slot, mmi, mnOff, mnLen, pnOff, pnLen, rFOff, rFLen, rMOff, rMLen, wFOff, wFLen, wMOff, wMLen, rnOff, rnLen, wnOff, wnLen, propRec, i, vmtSlots: Integer;
  implIntf: array[0..15] of Integer; implCnt, tmpCi, ii, imSlot, imProc: Integer;
  parentIntfCi, ancCur, ij, implOrig: Integer; alreadyImpl: Boolean;
  imName: AnsiString;
  isConstructor, isDestructor, isVirtual, isOverride, isAbstract, isClassMethod: Boolean;
  hadParens: Boolean;
  clsSealed, clsAbstract: Boolean;
  savedPCB: Integer;   { nested-type scoping — see AddClassLikeType }
  mname, propName, readName, writeName: AnsiString;
  propTk: TTypeKind;
  mIsFunc, mDoneArgs, mDoneParam, mIsArr, mIsByRef, mSawConst, mIsUntyped: Boolean;
  mRetType, mTk: TTypeKind;
  mNParams, mStartIdx, mTokKindOrd, mpi, mSelfIdx, mFullNameOff, mFullNameLen: Integer;
  curPublished: Integer;  { 1 while inside a published section of the current class body }
  curPublishedExplicit: Boolean;  { the section was an EXPLICIT `published` marker (not the implicit default) — the class-property publish check keys on it }
  curVis: Integer;   { current member visibility (VIS_*) for the class body section; stamped onto each field/method (enforced only under StrictVisibility) }
  curStrictVis: Boolean;  { the pending section was introduced by `strict` }
  etid, propEnumId, propSetEnumId: Integer;
  propIsIndexed, propIsDefault, propRedecl, propHasIndex: Boolean;
  propIndexVal: Int64;   { indexed (array) property + `default;` + `property X;` redeclaration }
  propBase: Integer;                                   { the ancestor row a redeclaration copies }
  mFullName: AnsiString;
  aLo, aHi: Integer; aElemTk: TTypeKind;
  tdCnt, tdLo, tdHi, tdi, tflatLen, fNDims: Integer;
  aElemStrCap: Integer;   { `array[..] of string[N]`: N, captured where it is parsed }
  tdDimLo, tdDimSpan: array[0..MAX_ARR_DIMS-1] of Integer;
  mPNames: array[0..MAX_PROC_PARAMS-1] of AnsiString;
  mPTypes: array[0..MAX_PROC_PARAMS-1] of TTypeKind;
  mPTypesRec: array[0..MAX_PROC_PARAMS-1] of Integer;
  mPArr: array[0..MAX_PROC_PARAMS-1] of Boolean;
  fldNOffs: array[0..MAX_PROC_PARAMS-1] of Integer;   { comma-separated field-name spans }
  fldNLens: array[0..MAX_PROC_PARAMS-1] of Integer;
  nFldNames, fni: Integer;
  mPByRef: array[0..MAX_PROC_PARAMS-1] of Boolean;
  mPConst: array[0..MAX_PROC_PARAMS-1] of Boolean;
  mPUntyped: array[0..MAX_PROC_PARAMS-1] of Boolean;
  mPDefault: array[0..MAX_PROC_PARAMS-1] of Boolean;
  mPDefaultVal: array[0..MAX_PROC_PARAMS-1] of Int64;
  mPDefaultIsStr: array[0..MAX_PROC_PARAMS-1] of Boolean;
  mPDefaultIsSet: array[0..MAX_PROC_PARAMS-1] of Boolean;   { twin of mPDefaultIsStr, for SET defaults }
  mPDefaultIsFloat: array[0..MAX_PROC_PARAMS-1] of Boolean; { ...and for FLOAT defaults (`d: Double = 2.5`): mPDefaultVal holds the IEEE bits }
  mDefaultIsSet: Boolean;
  mRetRecId: Integer;      { the DECL's return-type class/record id (ProcRetRecId) }
  mRetPtrElemTk, mRetPtrElemRec: Integer;   { A pointer RETURN type's element kind, captured at the declaration exactly like
    mRetRecId above it. Without it a DECL-only PChar method — abstract, or an
    interface method, the two shapes whose call resolves to the DECL's procIdx and
    never to an implementation's — leaves ProcRetPtrElemTk = tyUnknown, IsNodePChar
    answers False, and `AnsiString(ref.GetP())` lowers as a raw pointer cast:
    an EMPTY string where FPC gives the text. Silent wrong value, no diagnostic.
    refactor-centralize-managed-string-pchar-conversion }
  mPDefaultSOff: array[0..MAX_PROC_PARAMS-1] of Integer;
  mPDefaultSLen: array[0..MAX_PROC_PARAMS-1] of Integer;
  mHasDefault: Boolean;
  mDefaultVal: Int64;
  mDefaultIsStr, mDefaultIsFloat: Boolean;
  mDefaultSOff, mDefaultSLen: Integer;
begin
  Next;
  stopTypes := False;
  { A plain entry must look like `Name = ...` — an ident NOT followed by `=`
    (e.g. `protected` resuming members after a NESTED class-body type section)
    ends the section instead of desyncing on Expect('='). generic/operator
    keep their keyword forms. }
  while (CurTok.Kind = tkIdent) and (not CaseEqual(CurTok.SVal, 'constructor')) and (not CaseEqual(CurTok.SVal, 'destructor')) and (not CaseEqual(CurTok.SVal, 'implementation')) and (not CaseEqual(CurTok.SVal, 'initialization')) and (not CaseEqual(CurTok.SVal, 'finalization')) and not stopTypes and
        (CaseEqual(CurTok.SVal, 'generic') or CaseEqual(CurTok.SVal, 'specialize') or CaseEqual(CurTok.SVal, 'operator') or
         ((TokPos < TokCount) and (Tokens[TokPos].Kind = tkEq)) or
         ((not CaseEqual(CurTok.SVal, 'operator')) and
          (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLt))) do
  begin
    { `TFoo<T> = class` — Delphi-style generic template. Accepted in every
      mode (not just {$mode delphi}): at type-declaration position the
      `ident <` shape is unambiguous — except `operator < (...)` overload
      definitions, which the operator branch below owns. }
    if (not CaseEqual(CurTok.SVal, 'operator')) and
       (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLt) then
    begin
      { mode-Delphi generic template `TFoo<T> = class ... end;` — the name
        comes first; ParseGenericTemplateNamed captures the template and
        desugars all later Delphi-surface uses (see DelphiRewriteGenericUses). }
      ParseGenericTemplateNamed(CurTok.SVal, True);
    end
    else if CaseEqual(CurTok.SVal, 'generic') then
    begin
      ParseGenericTemplate;
    end
    else if CaseEqual(CurTok.SVal, 'operator') then
      stopTypes := True  { top-level operator def follows type section }
    else
    begin
      tnOff := Tokens[TokPos-1].SOffset;
      tnLen := Tokens[TokPos-1].SLen;
      tname := CurTok.SVal; Next;
      Expect(tkEq, '=');
      { A generic class specialization streams the concrete class body in place
        and leaves CurTok on 'class', falling through to the class-binding
        branch below — the concrete name comes from the saved tnOff/tnLen. }
      if CaseEqual(CurTok.SVal, 'specialize') then
        { True = handled, nothing to bind, go round again — either the
          declaration was deferred behind its nested generic prerequisites and
          re-emitted, or it was an exact re-statement of a specialization that
          another deferral had already queued. }
        if ParseSpecialization(tname) then Continue;
      if CurTok.Kind = tkLParen then
      begin
        etid := RegisterEnumType(tnOff, tnLen);
        { {$SCOPEDENUMS ON} at this token: members only under TEnum.member }
        EnumTypeScoped[etid] := TokScopedEnums[TokPos-1];
        ParseEnumMembers(etid);
      end
      else if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'interface') then
      begin
        { `IFoo = interface [guid] <method signatures> end;` — CORBA-style.
          The interface is a UCls entry with no fields; its methods are slot
          signatures (declaration order = IMT slot). A var of it is a 16-byte
          fat pointer {IMT, instance}. }
        Next;
        { optional parent interface: `IBar = interface(IFoo)`. IFoo's method
          signatures are inherited at the leading IMT slots, so a value of IBar
          dispatches its inherited methods and a class implementing IBar also
          satisfies IFoo (the ancestor IMTs are built at the class below). }
        parentIntfCi := -1;
        if CurTok.Kind = tkLParen then
        begin
          Next;
          if CurTok.Kind <> tkIdent then Error('expected parent interface name');
          parentIntfCi := FindUClass(CurTok.SVal);
          if (parentIntfCi < 0) or not UClsIsInterface[parentIntfCi] then
            Error('the parent of an interface must be an interface');
          Next;
          Expect(tkRParen, ')');
        end;
        { COM/ARC interface ({$interfaces com}): with no explicit parent, derive
          implicitly from IInterface so the three reserved slots QueryInterface /
          _AddRef / _Release occupy IMT slots 0..2 (ARC dispatches _Release via
          slot 2). IInterface's own declaration finds no prior IInterface, so it
          does not self-parent and supplies the three slots itself. }
        if InterfacesComMode and (parentIntfCi < 0) then
        begin
          parentIntfCi := FindUClass('IInterface');
          if parentIntfCi < 0 then parentIntfCi := FindUClass('IUnknown');
          if (parentIntfCi >= 0) and not UClsIsInterface[parentIntfCi] then
            parentIntfCi := -1;
        end;
        ci := AddClassLikeType(FindUClass(tname), tnOff, tnLen, tname);
        UClsIsInterface[ci] := True;
        UClsIsComInterface[ci] := InterfacesComMode;
        if InterfacesComMode then ComInterfaceUsed := True;
        { An interface VALUE is ONE pointer — the instance (FPC's ABI), so
          Pointer(intf) roundtrips and an interface fits any pointer-shaped
          container (fcl-fpcunit stores its listeners in a TFPList exactly so).
          The IMT is recovered per call from the instance's RTTI blob by
          interface id — see __pxxIntfIMT. }
        UClsSize_[ci] := TARGET_PTR_SIZE;
        UClsAlign[ci] := TARGET_PTR_SIZE;
        UClsParent[ci] := parentIntfCi;
        { Inherit the parent interface's methods first (contiguously, before this
          interface's own), so IMT slot order is [parent methods..., own...]. }
        if parentIntfCi >= 0 then
          for i := 0 to UClsMCount[parentIntfCi] - 1 do
          begin
            AddUMeth(ci, UMthNOff[UClsMBase[parentIntfCi] + i],
                     UMthNLen[UClsMBase[parentIntfCi] + i],
                     UMthProc_[UClsMBase[parentIntfCi] + i]);
            UMthVirSlot[UMthCount - 1] := UClsMCount[ci] - 1;
            UMthIsStatic[UMthCount - 1] := False;
          end;
        { optional GUID literal ['{...}'] — RECORDED (it used to be skipped). It is
          the key TObject.GetInterface looks an interface up by at runtime, so
          discarding it left nothing to search. Anything that is not a well-formed
          '{8-4-4-4-12}' string is still skipped, exactly as before. }
        if CurTok.Kind = tkLBrack then
        begin
          if (CurTok.Kind = tkLBrack) and (TokPos < TokCount) and
             (Tokens[TokPos].Kind = tkString) then
          begin
            Next;                          { now on the string literal }
            ParseGuidLiteral(ci, CurTok.SVal);
          end;
          while (CurTok.Kind <> tkRBrack) and (CurTok.Kind <> tkEOF) do Next;
          Expect(tkRBrack, ']');
        end;
        while (CurTok.Kind = tkProcedure) or (CurTok.Kind = tkFunction) do
        begin
          mIsFunc := CurTok.Kind = tkFunction;
          Next;
          if CurTok.Kind <> tkIdent then Error('expected interface method name');
          mname := CurTok.SVal;
          mnOff := Tokens[TokPos-1].SOffset; mnLen := Tokens[TokPos-1].SLen;
          Next;
          mNParams := 0; mRetType := tyInteger;
          if CurTok.Kind = tkLParen then
          begin
            Next; mDoneArgs := False;
            while (CurTok.Kind <> tkRParen) and not mDoneArgs do
            begin
              mIsByRef := False;
              mSawConst := False;
              if (CurTok.Kind = tkVar) or ((CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'out')) then
              begin mIsByRef := True; Next; end
              else if IsConstParamTok then begin mSawConst := True; Next; end;
              mStartIdx := mNParams; mDoneParam := False;
              while IsDeclNameTok and not mDoneParam do
              begin
                mPNames[mNParams] := CurTok.SVal; Inc(mNParams); Next;
                if not Eat(tkComma) then mDoneParam := True;
                if CurTok.Kind = tkColon then mDoneParam := True;
              end;
              mIsArr := False;
              if CurTok.Kind <> tkColon then
              begin
                { Untyped INTERFACE-method param (`out Obj`, no type) — the
                  class-method and standalone paths already allowed this; this one
                  demanded a ':' unconditionally, so IInterface.QueryInterface's
                  `out Obj` would not parse. By-ref, any arg type, address passed. }
                if not (mIsByRef or mSawConst) then
                  Error('untyped parameter requires var, const, or out');
                mIsByRef := True;
                mTk := tyPointer;
                LastTypeRecId := REC_NONE;
              end
              else
              begin
                Expect(tkColon, ':');
                if CurTok.Kind = tkArray then begin Next; Expect(tkOf, 'of'); mTk := ParseTypeKind; mIsArr := True; end
                else mTk := ParseTypeKind;
              end;
              { Default value: `n: Integer = 5` — mirror ParseSubroutine. }
              mHasDefault := False; mDefaultVal := 0;
              mDefaultIsStr := False; mDefaultIsFloat := False; mDefaultIsSet := False;
              mDefaultSOff := 0; mDefaultSLen := 0;
              if CurTok.Kind = tkEq then
              begin
                Next;
                ParseParamDefaultValue(mTk, mDefaultVal, mDefaultIsStr, mDefaultIsFloat,
                                       mDefaultIsSet, mDefaultSOff, mDefaultSLen);
                mHasDefault := True;
              end;
              { `const` record/variant param = by-ref, matching ParseSubroutine
                (sibling of the class-method fix; interface methods dispatch
                indirectly, so the mismatch would corrupt the arg silently).
                See bug-method-call-before-body-byvalue-small-record-arg. }
              if mSawConst and ((mTk = tyRecord) or (mTk = tyVariant)) and not mIsArr then
                mIsByRef := True;
              for i := mStartIdx to mNParams-1 do
              begin mPTypes[i] := mTk; mPTypesRec[i] := LastTypeRecId; mPArr[i] := mIsArr; mPByRef[i] := mIsByRef; mPConst[i] := mSawConst; mPDefault[i] := mHasDefault; mPDefaultVal[i] := mDefaultVal; mPDefaultIsStr[i] := mDefaultIsStr; mPDefaultIsFloat[i] := mDefaultIsFloat; mPDefaultIsSet[i] := mDefaultIsSet; mPDefaultSOff[i] := mDefaultSOff; mPDefaultSLen[i] := mDefaultSLen; end;
              if not Eat(tkSemicolon) then mDoneArgs := True;
            end;
            Expect(tkRParen, ')');
          end;
          mRetRecId := REC_NONE;
          mRetPtrElemTk := Ord(tyUnknown);
          mRetPtrElemRec := REC_NONE;
          if mIsFunc then
          begin
            Expect(tkColon, ':');
            mRetType := ParseTypeKind;
            mRetRecId := LastTypeRecId;   { the return type's class/record id }
            mRetPtrElemTk := Ord(LastTypePointerElemTk);
            mRetPtrElemRec := LastTypePointerElemRec;
          end;
          Eat(tkSemicolon);
          while EatIntfMethodDirective do ;
          { inject implicit Self (the instance) at param 0, like a class method }
          for i := mNParams downto 1 do
          begin mPNames[i] := mPNames[i-1]; mPTypes[i] := mPTypes[i-1]; mPTypesRec[i] := mPTypesRec[i-1]; mPArr[i] := mPArr[i-1]; mPByRef[i] := mPByRef[i-1]; mPConst[i] := mPConst[i-1]; mPDefault[i] := mPDefault[i-1]; mPDefaultVal[i] := mPDefaultVal[i-1]; mPDefaultIsStr[i] := mPDefaultIsStr[i-1]; mPDefaultIsFloat[i] := mPDefaultIsFloat[i-1]; mPDefaultIsSet[i] := mPDefaultIsSet[i-1]; mPDefaultSOff[i] := mPDefaultSOff[i-1]; mPDefaultSLen[i] := mPDefaultSLen[i-1]; end;
          mPNames[0] := 'Self'; mPTypes[0] := tyClass; mPTypesRec[0] := REC_NONE; mPArr[0] := False; mPByRef[0] := False; mPConst[0] := False; mPDefault[0] := False; mPDefaultVal[0] := 0; mPDefaultIsStr[0] := False; mPDefaultIsFloat[0] := False; mPDefaultIsSet[0] := False; mPDefaultSOff[0] := 0; mPDefaultSLen[0] := 0;
          mNParams := mNParams + 1;
          mFullName := tname; AppendChar(mFullName, '.');
          for i := 1 to Length(mname) do AppendChar(mFullName, mname[i]);
          mpi := RegisterProc(mFullName, mIsFunc, mRetType, mNParams, mPNames, mPTypes);
          Procs[mpi].BodyAddr := -1;
          { Record the return type's class/record id AT THE DECLARATION. It used to be set
            only when the method's BODY was parsed -- so a method called before its own
            implementation appeared (an ordinary thing inside one unit: fpjson's
            TJSONData.DumpJSON reads `O.Items[I].DumpJSON(S)` long before
            TJSONObject.GetItem's body) had ProcRetRecId = REC_NONE, and a selector on its
            result could not resolve. `.DumpJSON` silently degraded to a FIELD access, and the
            statement then demanded a ':='. }
          if (mRetType = tyClass) or (mRetType = tyRecord) then ProcRetRecId[mpi] := mRetRecId;
          if mIsFunc and (mRetType = tyPointer) then
          begin
            ProcRetPtrElemTk[mpi] := mRetPtrElemTk;
            ProcRetPtrElemRec[mpi] := mRetPtrElemRec;
          end;
          for i := 0 to mNParams-1 do
          begin
            Procs[mpi].Params[i].IsArray := mPArr[i]; Procs[mpi].Params[i].IsRef := mPByRef[i];
            { ...and the parameter's class/record id, which this path computed and
              then dropped -- so a class-typed interface PARAMETER was REC_NONE and
              nothing downstream could tell two overloads of it apart. The
              class-method path has always recorded it. }
            if i < MAX_PROC_PARAMS then ProcParamRecId[mpi * MAX_PROC_PARAMS + i] := mPTypesRec[i];
            if i < MAX_PROC_PARAMS then ProcParamIsConst[mpi * MAX_PROC_PARAMS + i] := mPConst[i];
            if (i < MAX_PROC_PARAMS) and mPDefault[i] then
            begin
              ProcParamHasDefault[mpi * MAX_PROC_PARAMS + i] := True;
              ProcParamDefaultVal[mpi * MAX_PROC_PARAMS + i] := mPDefaultVal[i];
              ProcParamDefaultIsStr[mpi * MAX_PROC_PARAMS + i] := mPDefaultIsStr[i];
              ProcParamDefaultIsFloat[mpi * MAX_PROC_PARAMS + i] := mPDefaultIsFloat[i];
              ProcParamDefaultIsSet[mpi * MAX_PROC_PARAMS + i] := mPDefaultIsSet[i];
              ProcParamDefaultSOff[mpi * MAX_PROC_PARAMS + i] := mPDefaultSOff[i];
              ProcParamDefaultSLen[mpi * MAX_PROC_PARAMS + i] := mPDefaultSLen[i];
            end;
          end;
          AddUMeth(ci, mnOff, mnLen, mpi);
          { slot = method position within this interface (IMT index) }
          UMthVirSlot[UMthCount-1] := UClsMCount[ci] - 1;
          UMthIsStatic[UMthCount-1] := False;
        end;
        Expect(tkEnd, 'end');
        Eat(tkSemicolon);
      end
      else if (CurTok.Kind = tkClass) and (Tokens[TokPos].Kind = tkOf) then
      begin
        { Named metaclass alias: TFooClass = class of TFoo. Values use the
          existing RTTI-pointer class-reference representation. }
        Next;
        Expect(tkOf, 'of');
        if CurTok.Kind <> tkIdent then Error('expected base class after class of');
        ci := FindUClass(CurTok.SVal);
        if ci < 0 then
        begin
          { FPC allows `TFooClass = class of TFoo` BEFORE TFoo's declaration in
            the same type section (generics.defaults' THashServiceClass): mint
            a FORWARD class row; the real declaration completes it, exactly
            like `TFoo = class;`. }
          ci := AddUClass(Tokens[TokPos-1].SOffset, Tokens[TokPos-1].SLen);
          UClsForward[ci] := True;
        end;
        RegisterClassRefAlias(tnOff, tnLen, REC_UCLASS_BASE + ci);
        Next;
        Eat(tkSemicolon);
      end
      else if CurTok.Kind = tkClass then
      begin
        Next;
        { `class sealed` / `class abstract` — Delphi class modifiers, sitting between
          `class` and the heritage list. Unconsumed, `sealed` was read as the
          heritage/first member and the whole declaration desynced.

          `sealed` IS enforced now (no descendants; and no abstract methods, since a
          sealed class can never have a descendant to supply them — tsealed1/tsealed2).
          The two modifiers are also mutually exclusive: `abstract` means "must be
          derived from", `sealed` means "cannot be" (tsealed3).

          `abstract` alone is still only recorded, not enforced — forbidding
          instantiation of an abstract class is a separate check. }
        clsSealed := False;
        clsAbstract := False;
        while (CurTok.Kind = tkIdent) and
              (CaseEqual(CurTok.SVal, 'sealed') or CaseEqual(CurTok.SVal, 'abstract')) do
        begin
          if CaseEqual(CurTok.SVal, 'sealed') then clsSealed := True
          else clsAbstract := True;
          Next;
        end;
        if clsSealed and clsAbstract then
          Error('a class cannot be both abstract and sealed');
        parentCi := -1;
        implCnt := 0;
        hadParens := CurTok.Kind = tkLParen;
        if Eat(tkLParen) then
        begin
          { (ParentClass) and/or (Iface1, Iface2, ...): an interface name in the
            list is an implemented interface; a class name is the parent. }
          repeat
            if CurTok.Kind <> tkIdent then Error('expected base class or interface name');
            tmpCi := FindUClass(CurTok.SVal);
            { TObject is a registered builtin class row now, so exclude it from
              the parent lookup by name — a real-parent link would relocate
              every `class(TObject)` VMT and break the implicit-root model
              (and the COM/ARC synthesis for TInterfacedObject). }
            if CaseEqual(CurTok.SVal, 'TObject') then tmpCi := -1;
            if (tmpCi < 0) and CaseEqual(CurTok.SVal, 'TObject') then
            begin
              { Explicit root base `class(TObject)` == the implicit root: leave
                parentCi = -1, same as a plain `class`. TObject is excluded from
                the parent lookup above, so accept it by name rather than
                erroring. (TInterfacedObject used to be accepted-as-root here
                too — silently DROPPING its refcount contract, so COM ARC
                dispatched through a garbage IMT slot and crashed at scope
                exit. It is a real builtinheap class now, so it resolves like
                any other base; on targets without it (ESP) the name errors
                like any unknown base. bug-pascal-tinterfacedobject-missing-
                silent-segfault) }
            end
            else
            begin
              if tmpCi < 0 then Error('base type not found: ' + CurTok.SVal);
              if UClsIsInterface[tmpCi] then
              begin
                if implCnt > 15 then Error('too many implemented interfaces (v1: max 16)');
                implIntf[implCnt] := tmpCi; Inc(implCnt);
              end
              else
              begin
                if parentCi >= 0 then Error('a class may have only one parent class');
                parentCi := tmpCi;
              end;
            end;
            Next;
          until not Eat(tkComma);
          Expect(tkRParen, ')');
        end;

        { A class implementing a derived interface also implements every ancestor
          interface — add the ancestors so an IMT is built for each, making
          `is`/`as`/`Supports` and class->base-interface assignment work. }
        implOrig := implCnt;
        for ii := 0 to implOrig - 1 do
        begin
          ancCur := UClsParent[implIntf[ii]];
          while ancCur >= 0 do
          begin
            alreadyImpl := False;
            for ij := 0 to implCnt - 1 do
              if implIntf[ij] = ancCur then alreadyImpl := True;
            if not alreadyImpl then
            begin
              if implCnt > 15 then Error('too many implemented interfaces (v1: max 16)');
              implIntf[implCnt] := ancCur; Inc(implCnt);
            end;
            ancCur := UClsParent[ancCur];
          end;
        end;

        { A forward stub `TFoo = class;` already minted an entry that `class of`
          aliases and field types point at — the full decl must fill THAT entry.
          Registering a second one shadows it (FindUClass returns the first
          match), so the base + fields land on an entry no reference sees.

          A stub belongs to the unit that WROTE it: filling a stub some OTHER
          unit registered merges two unrelated classes into one row. NilPy's
          shell pre-pass registers a forward row per `class X` in the .npy
          BEFORE any import is parsed, so an imported Pascal unit declaring a
          class of the same name filled the program's row — the NilPy class and
          its own intended base became literally the same class, and
          `class PBase(probeu.PBase)` made the class its own parent and hung the
          ancestor walk (bug-nilpy-class-named-after-its-imported-base-hangs). }
        ci := FindUClass(tname);
        if (ci >= 0) and UClsForward[ci] and (UClsUnitIdx[ci] = CurrentUnitIdx) then
        begin
          { counts are 0 on a stub; re-anchor the member windows to the current
            tails (other classes may have registered members in between). }
          UClsFBase[ci] := UFldCount;
          UClsMBase[ci] := UMthCount;
          UClsPBase[ci] := UPropCount;
          UClsVirtCount[ci] := 0;
          UClsForward[ci] := False;
        end
        else
        begin
          { A SECOND class of this name in the same unit. It is accepted today
            and every USE of the name binds to the FIRST declaration, so the
            diagnostics land far away: implementing collections.Counter as
            `TPyCounter = class(TPyDict)` in pylib — where TPyCounter already
            existed — reported its methods' own fields as undefined and its own
            constructor as taking arguments it was not given. Each message was
            true about the OTHER class, which is what made it a long detour in a
            4000-line unit (bug-pascal-duplicate-class-name-silently-shadows).

            Scoped to the DECLARING UNIT: the same name in two units is
            legitimate and is what --strict-uses scopes properly
            (bug-pascal-uses-is-transitive). A FORWARD stub is not a duplicate and
            is handled above. TObject and TGuid are pre-registered by the
            compiler before any source is parsed, with whatever CurrentUnitIdx
            holds at the time, so a program declaring its own — which
            test_object_ref_array_identity.pas does, legitimately — must not
            read as one. }
          if (ci >= 0) and (UClsUnitIdx[ci] = CurrentUnitIdx) and
             not UClsIsRecord[ci] and
             not CaseEqual(tname, 'TObject') and not CaseEqual(tname, 'TGuid') and
             (ParsingClassBodyCi < 0) then
            Error('duplicate class name ' + tname
                  + ' — one of that name is already declared in this unit, and'
                  + ' every use of the name binds to the FIRST declaration');
          { …but INSIDE A CLASS BODY the name is not the unit's, it is that
            class's: `touter.tinner` and `tother.tinner` are two legal, distinct
            types, and a generic's nested type is re-materialized once per
            specialization ON PURPOSE (tgeneric72 exists to assert those two are
            unique). The flat per-unit class table read both as redeclarations,
            so legal Pascal did not compile. Register the later one under its
            QUALIFIED name — the first keeps the bare one, so every existing
            unqualified use resolves exactly as before — and let the nested-type
            registry below make it reachable.
            bug-a-duplicate-class-name-check-is-scope-blind }
          ci := AddClassLikeType(ci, tnOff, tnLen, tname);
        end;
        UClsSealed[ci] := clsSealed;
        UClsAbstractCls[ci] := clsAbstract;
        { `sealed` is a promise that the class has no descendants — so deriving from one
          is an error, not a silently-accepted hierarchy (tsealed1). }
        if (parentCi >= 0) and UClsSealed[parentCi] then
          Error('cannot derive from the sealed class ' +
                GetTokenStrFromRaw(UClsNOff[parentCi], UClsNLen[parentCi]));
        UClsParent[ci] := parentCi;
        { bare `class;` with no heritage = a forward declaration (FPC).
          `class(TBase);` stays the empty-body shorthand. }
        UClsForward[ci] := (not hadParens) and (CurTok.Kind = tkSemicolon);

        curFieldOff := 0;
        classAlign := 1;
        if parentCi >= 0 then
        begin
          curFieldOff := UClsSize_[parentCi];
          UClsVirtCount[ci] := UClsVirtCount[parentCi];
        end
        else
        begin
          curFieldOff := 8; { reserve offset 0 for VMT pointer }
          { ...and the leading VMT slots for TObject's root virtuals. A root
            class's own virtuals therefore start at RootVMTSlotCount, and a
            descendant inherits the count through the branch above, so the
            reservation is made exactly once per hierarchy. 0 under
            --compact-classes = today's layout.
            feature-a-tobject-root-method-vmt-slots. }
          if not UClsIsRecord[ci] and not UClsIsInterface[ci] then
            UClsVirtCount[ci] := RootVMTSlotCount;
        end;

        { Implicit first section defaults to published, as Delphi/Lazarus do for
          $M+ (TPersistent-descended) classes — so a stock TForm's fields and
          event handlers are streamable/reflectable without an explicit
          `published`. We don't track $M+, so this applies to every class; the
          only effect is extra RTTI, which is harmless. }
        curPublished := 1;
        curPublishedExplicit := False;
        curVis := VIS_PUBLIC;   { the implicit first section is public (published for RTTI) }
        { FPC shorthand: `TFoo = class(TBase);` — semicolon closes the type
          declaration immediately with an empty body; no `end` needed. }
        if CurTok.Kind <> tkSemicolon then
        begin
        { types declared from here to the matching `end` belong to THIS class }
        savedPCB := ParsingClassBodyCi;
        ParsingClassBodyCi := ci;
        while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
        begin
          { `strict private` / `strict protected` (FPC/Delphi): TYPE-scoped variants.
            Consume the `strict` marker and record it so the following
            private/protected section is stamped as the strict (type-scoped) level. }
          curStrictVis := False;
          if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'strict') and
             (TokPos < TokCount) and (Tokens[TokPos].Kind = tkIdent) and
             (CaseEqual(GetTokenStr(TokPos), 'private') or
              CaseEqual(GetTokenStr(TokPos), 'protected')) then
          begin curStrictVis := True; Next; end;

          { Visibility section markers. Not reserved words, so treat as section
            switch only when immediately at member-start position. curVis drives
            access control under StrictVisibility; curPublished the RTTI flag. }
          if (CurTok.Kind = tkIdent) and
             (CaseEqual(CurTok.SVal, 'private') or CaseEqual(CurTok.SVal, 'protected') or
              CaseEqual(CurTok.SVal, 'public') or CaseEqual(CurTok.SVal, 'published')) then
          begin
            if CaseEqual(CurTok.SVal, 'published') then
            begin curPublished := 1; curPublishedExplicit := True; curVis := VIS_PUBLIC; end
            else
            begin
              curPublished := 0; curPublishedExplicit := False;
              if CaseEqual(CurTok.SVal, 'private') then
                begin if curStrictVis then curVis := VIS_STRICT_PRIVATE else curVis := VIS_PRIVATE; end
              else if CaseEqual(CurTok.SVal, 'protected') then
                begin if curStrictVis then curVis := VIS_STRICT_PROTECTED else curVis := VIS_PROTECTED; end
              else
                curVis := VIS_PUBLIC;    { public }
            end;
            Next;
            continue;
          end;

          { Nested `type` section inside a class body (fgl's private types:
            TCompareFunc = function(...), PT = ^T, ...). Parsed as GLOBAL type
            aliases — pxx does not scope class-local types (access control is
            unenforced project-wide). ParseTypeSection now stops at the first
            ident not followed by `=`, i.e. the next member/visibility word.
            NOTE: two specializations of one generic re-register the same
            names; first registration wins on lookup. }
          if CurTok.Kind = tkType then
          begin
            Inc(TypeSectionDepth);
            ParseTypeSection;
            Dec(TypeSectionDepth);
            continue;
          end;

          { `const` / `class const` section inside a class body (FPC/Delphi):

              TFoo = class
              const MaxItems = 16;
              class const Version = 3;

            Parsed as GLOBAL constants, exactly as the nested `type` section above is
            parsed as global type aliases — pxx does not scope class-local declarations
            (access control is unenforced project-wide), and a constant has no storage,
            so there is nothing to scope. `class const` and `const` are the same thing:
            a constant is already per-class, not per-instance. Neither parsed before —
            `const` fell into the field parser, which demanded a ':' after the name. }
          if (CurTok.Kind = tkConst) or
             ((CurTok.Kind = tkClass) and (Tokens[TokPos].Kind = tkConst)) then
          begin
            if CurTok.Kind = tkClass then Next;   { consume `class`, leaving `const` }
            { Scope this const section to the class: each entry registers under a
              mangled key + a ClassConst registry row (owner ci + visibility)
              instead of the global tables — bug-pascal-class-const-visibility. }
            ParseConstSection(ci, curVis);
            continue;
          end;

          { class var x[, y]: T; — one shared GLOBAL slot per class (not per
            instance), addressed as TClass.x or obj.x. Registered in the ClassVar
            table; storage is an anonymous global var (CurProc < 0 here). }
          if (CurTok.Kind = tkClass) and (Tokens[TokPos].Kind = tkVar) then
          begin
            Next; Next;   { consume 'class' 'var' }
            while (CurTok.Kind = tkIdent) and (not IsClassMemberStartWord(CurTok.SVal)) do
            begin
              nFldNames := 0;
              repeat
                if CurTok.Kind <> tkIdent then Error('expected class var name');
                fldNOffs[nFldNames] := Tokens[TokPos-1].SOffset;
                fldNLens[nFldNames] := Tokens[TokPos-1].SLen;
                Inc(nFldNames); Next;
              until not Eat(tkComma);
              Expect(tkColon, ':');
              { The SAME type parser + allocator the `var` section uses, so a class
                var takes every type a global can: arrays (inline and named, fixed
                and dynamic, N-D), sets, pointers, enums, proc types. It used to be
                `ParseTypeKind + AllocVar`, which reserved a SCALAR slot for an
                array type — indexing worked, Length() silently answered garbage,
                and an inline `array[...] of T` did not parse at all. }
              ParseDeclTypeDesc;
              for fni := 0 to nFldNames - 1 do
              begin
                if ClassVarCount >= MAX_TYPEALIAS then Error('too many class variables');
                i := AllocFromDeclTypeDesc('');
                ClassVarCi[ClassVarCount]   := ci;
                ClassVarNOff[ClassVarCount] := fldNOffs[fni];
                ClassVarNLen[ClassVarCount] := fldNLens[fni];
                ClassVarSym[ClassVarCount]  := i;
                ClassVarPyOvr[ClassVarCount] := False;   { a Pascal/ClassVar-annotated slot never needs the NilPy per-instance override }
                Inc(ClassVarCount);
              end;
              Eat(tkSemicolon);
            end;
            continue;
          end;

          { `class property` — parsed like a plain property below (its accessors
            are static class methods; dispatch is b299). FPC forbids PUBLISHING
            one — class properties are not streamable (tclass14b %FAIL). The
            implicit default section stays lenient (pxx treats every class as
            $M+, so erroring there would reject plain Delphi code). }
          if (CurTok.Kind = tkClass) and (Tokens[TokPos].Kind = tkProperty) then
          begin
            if curPublishedExplicit then
              Error('a class property cannot be published');
            Next;   { consume `class`; the property branch parses the rest }
          end;

          isClassMethod := False;
          if (CurTok.Kind = tkClass) and ((Tokens[TokPos].Kind = tkProcedure) or (Tokens[TokPos].Kind = tkFunction)) then
          begin
            isClassMethod := True;
            Next; { consume 'class' }
          end;

          if (CurTok.Kind = tkProcedure) or (CurTok.Kind = tkFunction) or
             ((CurTok.Kind = tkIdent) and (CaseEqual(CurTok.SVal, 'constructor') or CaseEqual(CurTok.SVal, 'destructor'))) then
          begin
            mIsFunc := CurTok.Kind = tkFunction;
            isConstructor := False;
            isDestructor := False;
            if CurTok.Kind = tkIdent then
            begin
              isConstructor := CaseEqual(CurTok.SVal, 'constructor');
              isDestructor := CaseEqual(CurTok.SVal, 'destructor');
              Next;
            end
            else
              Next;

            if not IsMethodNameTok then Error('expected method name');
            mname := GetTokenStr(TokPos - 1);   { keyword-token names carry no SVal }
            mnOff := Tokens[TokPos-1].SOffset;
            mnLen := Tokens[TokPos-1].SLen;
            Next;

            mNParams := 0;
            mRetType := tyInteger;
            if CurTok.Kind = tkLParen then
            begin
              Next;
              mDoneArgs := False;
              while (CurTok.Kind <> tkRParen) and not mDoneArgs do
              begin
                mIsByRef := False;
                mSawConst := False;
                if (CurTok.Kind = tkVar) or
                   ((CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'out')) then
                begin
                  mIsByRef := True;
                  Next;
                end
                else if IsConstParamTok then
                begin mSawConst := True; Next; end;
                mStartIdx := mNParams;
                mDoneParam := False;
                while IsDeclNameTok and not mDoneParam do
                begin
                  mPNames[mNParams] := CurTok.SVal; Inc(mNParams); Next;
                  if not Eat(tkComma) then mDoneParam := True;
                  if CurTok.Kind = tkColon then mDoneParam := True;
                end;
                mIsArr := False;
                mIsUntyped := False;
                mHasDefault := False;
                mDefaultVal := 0;
                mDefaultIsStr := False;
                mDefaultIsFloat := False;
                mDefaultIsSet := False;
                mDefaultSOff := 0;
                mDefaultSLen := 0;
                if CurTok.Kind <> tkColon then
                begin
                  { Untyped method param (`var B` / `const B`, no type) — mirror the
                    standalone-routine path: by-ref, any arg type, address passed. }
                  if not (mIsByRef or mSawConst) then
                    Error('untyped parameter requires var, const, or out');
                  mIsUntyped := True; mIsByRef := True; mTk := tyPointer;
                  LastTypeRecId := REC_NONE;
                end
                else
                begin
                  Expect(tkColon, ':');
                  if CurTok.Kind = tkArray then
                  begin
                    Next;
                    Expect(tkOf, 'of');
                    if CurTok.Kind = tkConst then
                    begin
                      { `array of const` method param (Exception.CreateFmt):
                        TVarRec open array, same as the free-routine case. }
                      if TVarRecId = REC_NONE then
                        Error('array of const requires the builtinheap unit (use an array/heap feature)');
                      Next;
                      mTk := tyRecord;
                      LastTypeRecId := TVarRecId;
                    end
                    else
                      mTk := ParseTypeKind;
                    mIsArr := True;
                  end
                  else
                    mTk := ParseTypeKind;
                  { Default value: `n: Integer = 5` — mirror ParseSubroutine
                    (~13915). Constant-folded; a call omitting the trailing arg
                    supplies it (ctor fill at ~5609, general fill in ir.inc). }
                  if CurTok.Kind = tkEq then
                  begin
                    Next;
                    ParseParamDefaultValue(mTk, mDefaultVal, mDefaultIsStr, mDefaultIsFloat,
                                           mDefaultIsSet, mDefaultSOff, mDefaultSLen);
                    mHasDefault := True;
                  end;
                end;
                { A `const` record/variant param is passed by reference — must
                  match ParseSubroutine's rule, or a call lowered BEFORE the
                  implementation body uses the by-value convention while the
                  compiled body expects an address (silently truncating on
                  x86-64 only when RecSize<=8; a hard backend error on i386).
                  See bug-method-call-before-body-byvalue-small-record-arg. }
                if mSawConst and ((mTk = tyRecord) or (mTk = tyVariant)) and not mIsArr then
                  mIsByRef := True;
                for i := mStartIdx to mNParams-1 do
                begin
                  mPTypes[i] := mTk;
                  mPTypesRec[i] := LastTypeRecId;
                  mPArr[i] := mIsArr;
                  mPByRef[i] := mIsByRef;
                  mPConst[i] := mSawConst;
                  mPUntyped[i] := mIsUntyped;
                  mPDefault[i] := mHasDefault;
                  mPDefaultVal[i] := mDefaultVal;
                  mPDefaultIsStr[i] := mDefaultIsStr;
                  mPDefaultIsFloat[i] := mDefaultIsFloat;
                  mPDefaultIsSet[i] := mDefaultIsSet;
                  mPDefaultSOff[i] := mDefaultSOff;
                  mPDefaultSLen[i] := mDefaultSLen;
                end;
                if not Eat(tkSemicolon) then mDoneArgs := True;
              end;
              Expect(tkRParen, ')');
            end;

            mRetPtrElemTk := Ord(tyUnknown);
            mRetPtrElemRec := REC_NONE;
            if mIsFunc then
            begin
              Expect(tkColon, ':');
              mRetType := ParseTypeKind;
              mRetRecId := LastTypeRecId;   { see the twin site above }
              mRetPtrElemTk := Ord(LastTypePointerElemTk);
              mRetPtrElemRec := LastTypePointerElemRec;
            end
            else
              mRetRecId := REC_NONE;
            Eat(tkSemicolon);

            { The DECL side's twin of the impl-side Self injection: every method carries a
              Self at index 0, and a CLASS method's Self is the metaclass -- a class
              reference (tyPointer), not an instance. The two sides must agree or the
              impl never binds to its declaration ("unresolved forward"). }
            begin
              for i := mNParams downto 1 do
              begin
                mPNames[i] := mPNames[i-1];
                mPTypes[i] := mPTypes[i-1];
                mPTypesRec[i] := mPTypesRec[i-1];
                mPArr[i]   := mPArr[i-1];
                mPByRef[i] := mPByRef[i-1];
                mPConst[i] := mPConst[i-1];
                mPUntyped[i] := mPUntyped[i-1];
                mPDefault[i] := mPDefault[i-1];
                mPDefaultVal[i] := mPDefaultVal[i-1];
                mPDefaultIsStr[i] := mPDefaultIsStr[i-1];
                mPDefaultIsSet[i] := mPDefaultIsSet[i-1];
                mPDefaultSOff[i] := mPDefaultSOff[i-1];
                mPDefaultSLen[i] := mPDefaultSLen[i-1];
              end;
              mPNames[0] := 'Self';
              if isClassMethod then mPTypes[0] := tyPointer
              else mPTypes[0] := tyClass;
              mPTypesRec[0] := REC_NONE;   { must agree with the impl side's Self }
              mPArr[0]   := False;
              mPByRef[0] := False;
              mPConst[0] := False;
              mPUntyped[0] := False;
              mPDefault[0] := False;
              mPDefaultVal[0] := 0;
              mPDefaultIsStr[0] := False;
              mPDefaultIsSet[0] := False;
              mPDefaultSOff[0] := 0;
              mPDefaultSLen[0] := 0;
              mNParams := mNParams + 1;
            end;

            mFullName := tname;
            AppendChar(mFullName, '.');
            for i := 1 to Length(mname) do AppendChar(mFullName, mname[i]);

            { REC-AWARE decl lookup and registration: two same-arity overloads whose
              class/record param identities differ are DIFFERENT overloads. The
              rec-blind FindProcOverload found `Add(AnObject: TJSONObject)` when
              registering `Add(Item: TJSONData)`'s sibling, so both DECLS shared one
              proc and each IMPL body clobbered the other's — fpjson's
              `Add(TJSONData(AnObject))` then re-dispatched to Add(TJSONObject) and
              recursed to stack overflow (bug-pascal-overload-impl-decl-signature-match). }
            mpi := FindProcOverloadRec(mFullName, mNParams, mPTypes, mPTypesRec, mPArr, mPByRef);
            if mpi < 0 then
            begin
              mpi := RegisterProc(mFullName, mIsFunc, mRetType, mNParams, mPNames, mPTypes);
              Procs[mpi].BodyAddr := -1;
              for i := 0 to mNParams-1 do
                if (i < MAX_PROC_PARAMS) and
                   ((mPTypes[i] = tyClass) or (mPTypes[i] = tyRecord)) then
                  ProcParamRecId[mpi * MAX_PROC_PARAMS + i] := mPTypesRec[i];
              if (mRetType = tyClass) or (mRetType = tyRecord) then ProcRetRecId[mpi] := mRetRecId;
              if mIsFunc and (mRetType = tyPointer) then
              begin
                ProcRetPtrElemTk[mpi] := mRetPtrElemTk;
                ProcRetPtrElemRec[mpi] := mRetPtrElemRec;
              end;
              for i := 0 to mNParams-1 do
              begin
                if (i < MAX_PROC_PARAMS) then ProcParamUntyped[mpi * MAX_PROC_PARAMS + i] := mPUntyped[i];
                if (i < MAX_PROC_PARAMS) and mPDefault[i] then
                begin
                  ProcParamHasDefault[mpi * MAX_PROC_PARAMS + i] := True;
                  ProcParamDefaultVal[mpi * MAX_PROC_PARAMS + i] := mPDefaultVal[i];
                  ProcParamDefaultIsStr[mpi * MAX_PROC_PARAMS + i] := mPDefaultIsStr[i];
                  ProcParamDefaultIsFloat[mpi * MAX_PROC_PARAMS + i] := mPDefaultIsFloat[i];
                  ProcParamDefaultIsSet[mpi * MAX_PROC_PARAMS + i] := mPDefaultIsSet[i];
                  ProcParamDefaultSOff[mpi * MAX_PROC_PARAMS + i] := mPDefaultSOff[i];
                  ProcParamDefaultSLen[mpi * MAX_PROC_PARAMS + i] := mPDefaultSLen[i];
                end;
                Procs[mpi].Params[i].IsArray := mPArr[i];
                Procs[mpi].Params[i].IsRef := mPByRef[i];
                if i < MAX_PROC_PARAMS then ProcParamIsConst[mpi * MAX_PROC_PARAMS + i] := mPConst[i];
                if (mPTypes[i] = tyClass) or (mPTypes[i] = tyRecord) then
                  Procs[mpi].Params[i].SymIdx := -1;
              end;
            end;

            isVirtual := False;
            isOverride := False;
            isAbstract := False;
            { `overload` is a real TOKEN (tkOverload), every other directive is a
              plain identifier — so a tkIdent-only guard silently walked past it.
              A lone trailing `overload;` then got skipped by luck, but
              `reintroduce; overload; virtual;` left `virtual` to be read as a
              FIELD name, which demands ':' and died on the ';'
              (bug-pascal-class-body-overload-directive). }
            while ((CurTok.Kind = tkIdent) and
                  (CaseEqual(CurTok.SVal, 'virtual') or
                   CaseEqual(CurTok.SVal, 'override') or
                   CaseEqual(CurTok.SVal, 'abstract') or
                   CaseEqual(CurTok.SVal, 'dynamic') or
                   CaseEqual(CurTok.SVal, 'inline') or
                   CaseEqual(CurTok.SVal, 'static') or
                   CaseEqual(CurTok.SVal, 'reintroduce') or
                   { `final` — seals a virtual method against further override. pxx does
                     not enforce it (nothing else here is enforced either), so it is
                     parse-and-ignore like `reintroduce`. Unconsumed it desynced the
                     member loop. }
                   CaseEqual(CurTok.SVal, 'final') or
                   CaseEqual(CurTok.SVal, 'deprecated') or
                   CaseEqual(CurTok.SVal, 'platform') or
                   CaseEqual(CurTok.SVal, 'experimental'))) or
                  (CurTok.Kind = tkOverload) or IsCallConvDirectiveTok do
            begin
              { virtual/override/abstract drive dispatch; dynamic = virtual
                (FPC: same semantics, different table — pxx has one VMT).
                inline/overload/static/reintroduce + hint directives are
                parse-and-ignore: overload resolution is signature-keyed
                anyway, `class` already makes a method static, and
                reintroduce only silences an FPC hint. `deprecated` may
                carry a message string literal. }
              if CaseEqual(CurTok.SVal, 'virtual') or CaseEqual(CurTok.SVal, 'dynamic') then isVirtual := True;
              if CaseEqual(CurTok.SVal, 'override') then isOverride := True;
              if CaseEqual(CurTok.SVal, 'abstract') then
              begin
                isVirtual := True;   { abstract implies virtual }
                isAbstract := True;
                { An abstract method has no body and relies on a descendant to supply one.
                  A sealed class can never HAVE a descendant, so the method could never be
                  implemented and any call would dispatch into nothing (tsealed2). }
                if (ci >= 0) and UClsSealed[ci] then
                  Error('a sealed class cannot have an abstract method');
              end;
              if CaseEqual(CurTok.SVal, 'deprecated') and (TokPos < TokCount) and
                 (Tokens[TokPos].Kind = tkString) then
                Next; { skip the message literal (consumed by the Next below) }
              Next;
              Eat(tkSemicolon);
            end;

            AddUMeth(ci, mnOff, mnLen, mpi);
            mmi := UMthCount - 1;
            UMthIsStatic[mmi] := isClassMethod;
            UMthIsCtor[mmi] := isConstructor;
            UMthPub[mmi] := curPublished;
            UMthVis[mmi] := curVis;

            if isVirtual then
            begin
              slot := UClsVirtCount[ci];
              UClsVirtCount[ci] := UClsVirtCount[ci] + 1;
              UMthVirSlot[mmi] := slot;
            end
            else if isOverride then
            begin
              slot := FindParentVirtualSlot(parentCi, mname);
              { A root virtual has a slot number fixed at the ROOT, not one
                allocated per hierarchy — that is the whole point of reserving
                them, and it is what lets a static-TObject receiver dispatch.
                Checked before the materialisation hack below, so `Destroy`
                takes slot ROOT_VMT_DESTROY rather than a fresh one. }
              if slot < 0 then slot := RootVMTSlotOf(mname);
              if (slot < 0) and (CaseEqual(mname, 'Destroy') or CaseEqual(mname, 'Create')) then
              begin
                { FPC's TObject.Destroy (and TComponent-style virtual Create) are
                  virtual, but pxx's implicit root carries no method table, so
                  `override` finds no parent slot. Materialise the root virtual on
                  first override: allocate a fresh slot exactly as `virtual` would,
                  so `destructor Destroy; override;` compiles and dispatches
                  (Free's desugar already calls Destroy virtually). A descendant's
                  own `Destroy; override;` then finds THIS slot via
                  FindParentVirtualSlot and chains correctly. inherited Destroy /
                  Create at the root boundary is a no-op (ParseInheritedCallAST).
                  See bug-tobject-destroy-not-virtual-override.

                  STILL REACHED, and deliberately: `Create` is not one of the
                  reserved root virtuals (FPC's TObject.Create is not virtual —
                  the virtual-constructor idiom is TComponent's), and under
                  --compact-classes nothing is reserved at all, so this is the
                  compact path for `Destroy` too. }
                slot := UClsVirtCount[ci];
                UClsVirtCount[ci] := UClsVirtCount[ci] + 1;
                UMthVirSlot[mmi] := slot;
              end
              else
              begin
                if slot < 0 then
                begin
                  { …and the one place --compact-classes has to say so by name.
                    Overriding Equals/GetHashCode/ToString needs a reserved root
                    slot; without one there is nothing for a static-TObject call
                    to dispatch through, and silently allocating a fresh
                    per-hierarchy slot is exactly the wrong answer that got
                    option A rejected. }
                  if CompactClasses and (CaseEqual(mname, 'Equals') or
                     CaseEqual(mname, 'GetHashCode') or CaseEqual(mname, 'ToString')) then
                    Error('cannot override ' + mname +
                          ': --compact-classes reserves no root VMT slots, so there is' +
                          ' no TObject.' + mname + ' to override. Drop --compact-classes' +
                          ' (it is implied by --platform=esp) to enable the root methods');
                  Error('cannot override: no virtual method found in parent chain: ' + mname);
                end;
                UMthVirSlot[mmi] := slot;
              end;
            end;
          end
          else if CurTok.Kind = tkProperty then
          begin
            Next;
            if not IsMemberNameTok then Error('expected property name');
            propName := GetTokenStr(TokPos - 1);   { keyword-token names (ParamCount) carry no SVal }
            pnOff := Tokens[TokPos-1].SOffset;
            pnLen := Tokens[TokPos-1].SLen;
            Next;
            { Indexed (array) property: `property Items[i: TIdx]: T ...`. The index
              parameter's name/type are defined by the accessor signature, so the
              declaration clause is parsed and discarded; we only mark the property
              indexed so accesses pass the subscript as an extra accessor arg. }
            propIsIndexed := False;
            propIsDefault := False;

            { `property Items;` / `property Items; default;` -- a REDECLARATION of an
              INHERITED property. FPC lets a descendant re-expose an ancestor's property by
              naming it alone, optionally adding a directive (fpjson's TJSONArray does
              exactly `property Items;default;` to make the inherited indexed property the
              class's default one). No type, no accessors: everything comes from the
              ancestor.

              Re-register it on THIS class with the ancestor's accessors copied, rather
              than just letting FindUProp find the ancestor's entry -- because the point of
              the redeclaration is usually to CHANGE something (here, `default`), and that
              change must not be written onto the ancestor's row. }
            propRedecl := (CurTok.Kind = tkSemicolon);
            if propRedecl then
            begin
              Next;                                { the ';' after the name }
              if CurTok.Kind = tkDefault then
              begin
                propIsDefault := True;
                Next;
                Eat(tkSemicolon);
              end;
              while (CurTok.Kind = tkIdent) and
                    (CaseEqual(CurTok.SVal, 'deprecated') or
                     CaseEqual(CurTok.SVal, 'platform') or
                     CaseEqual(CurTok.SVal, 'experimental') or
                     CaseEqual(CurTok.SVal, 'unimplemented')) do
              begin
                if CaseEqual(CurTok.SVal, 'deprecated') and (TokPos < TokCount) and
                   (Tokens[TokPos].Kind = tkString) then
                  Next;
                Next;
                Eat(tkSemicolon);
              end;

              propBase := FindUProp(ci, propName);
              if propBase < 0 then
                Error('redeclared property has no ancestor declaration: ' + propName);
              i := AddUProperty(ci, pnOff, pnLen, UPropTk[propBase], UPropRec[propBase]);
              UPropReadFOff[i] := UPropReadFOff[propBase]; UPropReadFLen[i] := UPropReadFLen[propBase];
              UPropReadMOff[i] := UPropReadMOff[propBase]; UPropReadMLen[i] := UPropReadMLen[propBase];
              UPropWriteFOff[i] := UPropWriteFOff[propBase]; UPropWriteFLen[i] := UPropWriteFLen[propBase];
              UPropWriteMOff[i] := UPropWriteMOff[propBase]; UPropWriteMLen[i] := UPropWriteMLen[propBase];
              UPropPub[i] := curPublished;
              UPropEnumId[i] := UPropEnumId[propBase];
              UPropSetEnumId[i] := UPropSetEnumId[propBase];
              UPropIsIndexed[i] := UPropIsIndexed[propBase];
              UPropIsDefault[i] := propIsDefault or UPropIsDefault[propBase];
              UPropHasIndex[i] := UPropHasIndex[propBase];
              UPropIndexVal[i] := UPropIndexVal[propBase];
            end
            else
            begin
            if CurTok.Kind = tkLBrack then
            begin
              propIsIndexed := True;
              Next;
              while (CurTok.Kind <> tkRBrack) and (CurTok.Kind <> tkEOF) do Next;
              Expect(tkRBrack, ']');
            end;
            Expect(tkColon, ':');
            LastTypeSetEnumId := -1;
            propTk := ParseTypeKind;
            propRec := LastTypeRecId;
            propEnumId := LastTypeEnumId;
            propSetEnumId := LastTypeSetEnumId;

            { `index N` — a COMPILE-TIME constant handed to the accessor as its first
              argument, so several properties can share one getter/setter. Distinct from an
              indexed property, whose index is a runtime subscript. }
            propHasIndex := False;
            propIndexVal := 0;
            if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'index') then
            begin
              Next;
              propIndexVal := ConstEval;
              propHasIndex := True;
            end;

            rFOff := 0; rFLen := 0;
            rMOff := 0; rMLen := 0;
            wFOff := 0; wFLen := 0;
            wMOff := 0; wMLen := 0;

            if CurTok.Kind = tkRead then
            begin
              Next;
              if CurTok.Kind <> tkIdent then Error('expected read field or method name');
              readName := CurTok.SVal;
              rnOff := Tokens[TokPos-1].SOffset;
              rnLen := Tokens[TokPos-1].SLen;
              Next;
              if FindUField(ci, readName) >= 0 then
              begin
                rFOff := rnOff; rFLen := rnLen;
              end
              else
              begin
                rMOff := rnOff; rMLen := rnLen;
              end;
            end;

            if CurTok.Kind = tkwrite then
            begin
              Next;
              if CurTok.Kind <> tkIdent then Error('expected write field or method name');
              writeName := CurTok.SVal;
              wnOff := Tokens[TokPos-1].SOffset;
              wnLen := Tokens[TokPos-1].SLen;
              Next;
              if FindUField(ci, writeName) >= 0 then
              begin
                wFOff := wnOff; wFLen := wnLen;
              end
              else
              begin
                wMOff := wnOff; wMLen := wnLen;
              end;
            end;

            Eat(tkSemicolon);
            { Optional `default;` on an indexed property → obj[i] routes here. }
            if CurTok.Kind = tkDefault then
            begin
              propIsDefault := True;
              Next;
              Eat(tkSemicolon);
            end;
            { Trailing hint directives — `property Tests: TFPList read FTests;
              deprecated;` (fpcunit). Parse-and-ignore, like the method path: they
              only drive an FPC warning. Unconsumed, `deprecated` was read as the
              next FIELD name and demanded a ':'. `deprecated` may carry a message
              literal. }
            while (CurTok.Kind = tkIdent) and
                  (CaseEqual(CurTok.SVal, 'deprecated') or
                   CaseEqual(CurTok.SVal, 'platform') or
                   CaseEqual(CurTok.SVal, 'experimental') or
                   CaseEqual(CurTok.SVal, 'unimplemented')) do
            begin
              if CaseEqual(CurTok.SVal, 'deprecated') and (TokPos < TokCount) and
                 (Tokens[TokPos].Kind = tkString) then
                Next; { skip the message literal (consumed by the Next below) }
              Next;
              Eat(tkSemicolon);
            end;
            i := AddUProperty(ci, pnOff, pnLen, Ord(propTk), propRec);
            UPropReadFOff[i] := rFOff; UPropReadFLen[i] := rFLen;
            UPropReadMOff[i] := rMOff; UPropReadMLen[i] := rMLen;
            UPropWriteFOff[i] := wFOff; UPropWriteFLen[i] := wFLen;
            UPropWriteMOff[i] := wMOff; UPropWriteMLen[i] := wMLen;
            UPropPub[i] := curPublished;
            UPropEnumId[i] := propEnumId;
            UPropSetEnumId[i] := propSetEnumId;
            UPropIsIndexed[i] := propIsIndexed;
            UPropIsDefault[i] := propIsDefault;
            UPropHasIndex[i] := propHasIndex;
            UPropIndexVal[i] := propIndexVal;
            end;   { close the non-redeclaration branch }
          end
          else if CurTok.Kind = tkIdent then
          begin
            { comma-separated names share one type: `A, B: Integer` }
            fldNOffs[0] := Tokens[TokPos-1].SOffset;
            fldNLens[0] := Tokens[TokPos-1].SLen;
            nFldNames := 1;
            Next;
            while CurTok.Kind = tkComma do
            begin
              Next;
              if CurTok.Kind <> tkIdent then Error('expected field name after ","');
              fldNOffs[nFldNames] := Tokens[TokPos-1].SOffset;
              fldNLens[nFldNames] := Tokens[TokPos-1].SLen;
              Inc(nFldNames);
              Next;
            end;
            Expect(tkColon, ':');
            isArr := False;
            arrLen := 1;
            fIsDyn := False;
            fDynDepth := 0;
            fNDims := 0;
            if CurTok.Kind = tkArray then
            begin
              Next;
              if CurTok.Kind = tkLBrack then
              begin
                Next;
                { Bounds through ParseArrayDimBounds, the same helper the var
                  section and the named-array-type path use — const EXPRESSIONS
                  (`0..N - 1`, bug-inline-array-field-const-bound) and, since it
                  is shared, a whole ordinal TYPE as the index (`array[Byte]`,
                  `array[TTypeKind]`, rtl-generics' comparer tables). Inline
                  ConstEval here accepted only the `lo..hi` form, so an index
                  type that a var section took happily was `not a constant` in a
                  field — a second mechanism for one concept, which is the case
                  devdocs/dev/normalise-dont-special-case.md is about. }
                ParseArrayDimBounds(loVal, hiVal);
                arrLen := hiVal - loVal + 1;
                { N-D field: collect dim0 then any comma dims. }
                fNDims := 1; tdDimLo[0] := loVal; tdDimSpan[0] := hiVal - loVal + 1;
                while CurTok.Kind = tkComma do
                begin
                  Eat(tkComma);
                  ParseArrayDimBounds(tdLo, tdHi);
                  if fNDims >= MAX_ARR_DIMS then Error('too many array dimensions');
                  tdDimLo[fNDims] := tdLo; tdDimSpan[fNDims] := tdHi - tdLo + 1;
                  arrLen := arrLen * tdDimSpan[fNDims];
                  Inc(fNDims);
                end;
                Expect(tkRBrack, ']');
                Expect(tkOf, 'of');
                fTk := ParseTypeKind;
                fRec := LastTypeRecId;
                isArr := True;
              end
              else
              begin
                { Dynamic-array field: `array of T`, including nested. The slot is
                  a pointer-sized handle; fTk/fRec carry the base element type. }
                fIsDyn := True;
                fDynDepth := 1;
                Expect(tkOf, 'of');
                while CurTok.Kind = tkArray do
                begin
                  Next;
                  Inc(fDynDepth);
                  Expect(tkOf, 'of');
                end;
                fTk := ParseTypeKind;
                fRec := LastTypeRecId;
              end;
            end
            else
            begin
              { Named dynamic-array type field (`TDynArr = array of T`): mirror
                the inline `array of T` field so SetLength/Length/indexing see a
                real dynamic array. Without this the field's UFldDynDepth stayed
                0 and SetLength(Self.field, n) misrouted to the string path. }
              fAi := -1;
              if CurTok.Kind = tkIdent then fAi := FindArrayType(CurTok.SVal);
              if (fAi >= 0) and ArrTypeIsDyn[fAi] then
              begin
                fIsDyn := True;
                fDynDepth := ArrTypeDynDepth[fAi];
                fTk := IntToTypeKind(ArrTypeElemTk[fAi]);
                fRec := ArrTypeElemRec[fAi];
                LastTypePointerElemRec := ArrTypePtrElemRec[fAi];
                Next;   { consume the named array type }
              end
              else if (fAi >= 0) and (not ArrTypeIsDyn[fAi]) then
              begin
                { Named FIXED-array type field (`a: TG`, `TG = array[..] of T`):
                  make it a real array field (1-D or flattened N-D) so a.x[i]
                  indexes with the right stride. Without this ParseTypeKind drops
                  TG's dimension and the field collapses to a single base element
                  (corrupting r.field[i] and r.field passed as a var array arg). }
                isArr := True;
                fTk := IntToTypeKind(ArrTypeElemTk[fAi]);
                fRec := ArrTypeElemRec[fAi];
                LastTypePointerElemRec := ArrTypePtrElemRec[fAi];
                if ArrTypeNDims[fAi] >= 2 then
                begin
                  fNDims := ArrTypeNDims[fAi];
                  arrLen := 1;
                  for tdi := 0 to fNDims - 1 do
                  begin
                    tdDimLo[tdi]   := ArrTypeDimLo[fAi * MAX_ARR_DIMS + tdi];
                    tdDimSpan[tdi] := ArrTypeDimSpan[fAi * MAX_ARR_DIMS + tdi];
                    arrLen := arrLen * tdDimSpan[tdi];
                  end;
                end
                else
                begin
                  fNDims := 1;
                  tdDimLo[0]   := ArrTypeLo[fAi];
                  tdDimSpan[0] := ArrTypeHi[fAi] - ArrTypeLo[fAi] + 1;
                  arrLen := tdDimSpan[0];
                end;
                Next;   { consume the named array type }
              end
              else
              begin
                fTk := ParseTypeKind;
                fRec := LastTypeRecId;
              end;
            end;
            if fIsDyn then
            begin
              fSize := TARGET_PTR_SIZE;
              fAlign := TARGET_PTR_SIZE;
            end
            else if fTk = tyString then
            begin
              fSize := LOCAL_STR_CAP + 8;
              fAlign := TARGET_PTR_SIZE;
            end
            else if fTk = tyFixedString then
            begin
              { `string[N]` field: see ParseRecordFields — tyString layout,
                capacity N via UFldStrCap. }
              fStrCap := LastTypeStrCap;
              if fStrCap <= 0 then fStrCap := DEFAULT_STR_CAP;
              fSize := FrozenStrSlotSize(fTk, fStrCap);
              fAlign := TARGET_PTR_SIZE;
            end
            else if fTk = tyRecord then
            begin
              fSize := RecSize(fRec);
              fAlign := TARGET_PTR_SIZE;
            end
            else
            begin
              fSize := TypeSize(fTk);
              fAlign := TypeAlign(fTk);
            end;
            if isArr then
              fSize := fSize * arrLen;
            for fni := 0 to nFldNames - 1 do
            begin
              curFieldOff := AlignTo(curFieldOff, fAlign);
              if fTk = tyFixedString then
              begin
                AddUField(ci, fldNOffs[fni], fldNLens[fni], curFieldOff, Ord(tyString), fRec);
                UFldStrCap[UFldCount-1] := fStrCap;
              end
              else
                AddUField(ci, fldNOffs[fni], fldNLens[fni], curFieldOff, Ord(fTk), fRec);
              UFldIsArray[UFldCount-1] := isArr or fIsDyn;
              if fIsDyn then UFldArrLen[UFldCount-1] := -1
              else UFldArrLen[UFldCount-1] := arrLen;
              UFldDynDepth[UFldCount-1] := fDynDepth;
              if fNDims >= 2 then
              begin
                UFldArrNDims[UFldCount-1] := fNDims;
                for tdi := 0 to fNDims - 1 do
                begin
                  UFldArrDimLo[(UFldCount-1) * MAX_ARR_DIMS + tdi]   := tdDimLo[tdi];
                  UFldArrDimSpan[(UFldCount-1) * MAX_ARR_DIMS + tdi] := tdDimSpan[tdi];
                end;
              end
              else if isArr and (not fIsDyn) then
                { 1-D static array field: record its LOW BOUND in dim 0 of the same table.
                  UFldArrNDims deliberately stays 0 — nothing dispatches differently — this
                  is only where the index lowering reads a field array's `lo` from. Without
                  it the low was never subtracted: `array[1..3]` wrote one element past its
                  extent and `array[-2..2]` two before it, corrupting the neighbouring field
                  (or, on a class, the object header — Free then segfaulted).
                  bug-p-record-field-array-with-a-non-zero-low-bound-writes-out-of-bounds }
                UFldArrDimLo[(UFldCount-1) * MAX_ARR_DIMS] := tdDimLo[0];
              UFldPub[UFldCount-1] := curPublished;
              UFldVis[UFldCount-1] := curVis;
              curFieldOff := curFieldOff + fSize;
            end;
            if fAlign > classAlign then classAlign := fAlign;
            Eat(tkSemicolon);
          end
          else
            Next;
        end;
        Expect(tkEnd, 'end');
        ParsingClassBodyCi := savedPCB;
        end; { end of non-shorthand body block }
        UClsSize_[ci] := AlignTo(curFieldOff, classAlign);

        { Always reserve at least one slot so every class has a DISTINCT VMT
          address — that address is the per-class runtime identity used by is/as
          and stored at [instance+0]. Without this, classes with no virtual
          methods get 0-byte VMTs that all alias the same offset, so `obj is
          AnyClass` would match every class. The padding slot is never dispatched
          (the class has no virtuals), so it is harmless. }
        { RTTI backlink, one word IMMEDIATELY BEFORE the VMT (EmitRTTI patches it).
          [instance+0] holds the VMT address, and the RTTI blob points AT the VMT
          (+24) but nothing pointed back — so an INSTANCE could not find its own
          class RTTI, which is what published-method reflection needs. Putting it at
          VMT-8 keeps UClsVMTOffset on slot 0, so every virtual slot index is
          unchanged and is/as keep comparing VMT addresses exactly as before.
          Stays 0 for a class with no RTTI blob (no published members). }
        { ...and the LAYOUT backlink one word before THAT (VMT-16): points at the
          class's managed-field layout descriptor (EmitLayoutRTTI patches it), so
          PXXClassFinalize can release string/dynarray/record/COM-interface fields
          on Free by the instance's RUNTIME class. Stays 0 (nil = nothing to
          finalize) for classes with no managed fields
          (bug-a-class-managed-fields-not-finalized-on-destroy). }
        for i := 0 to 15 do
        begin
          if DataLen >= MAX_DATA then Error('data overflow');
          Data[DataLen] := 0;
          Inc(DataLen);
        end;
        UClsVMTOffset[ci] := DataLen;

        vmtSlots := UClsVirtCount[ci];
        if vmtSlots < 1 then vmtSlots := 1;
        for i := 0 to vmtSlots * 8 - 1 do
        begin
          if DataLen >= MAX_DATA then Error('data overflow');
          Data[DataLen] := 0;
          Inc(DataLen);
        end;
        { Fill every VMT slot from the effective method (own override or an
          inherited one). The per-override fixup loop only covers subclasses
          that already exist when the override is parsed, so a subclass
          declared later (or in a later unit) would leave inherited slots null
          and crash on dispatch. This makes each class's VMT self-contained. }
        for i := 0 to UClsVirtCount[ci] - 1 do
        begin
          slot := ResolveVMTSlotProc(ci, i);
          if slot >= 0 then
          begin
            if MethodFixCount >= MAX_METHFIX then Error('too many virtual method fixups');
            MethodFixups[MethodFixCount].DataPos := UClsVMTOffset[ci] + i * 8;
            MethodFixups[MethodFixCount].ProcIdx := slot;
            Inc(MethodFixCount);
          end;
        end;

        { Build one Interface Method Table per implemented interface: a Data[]
          array of code addresses, slot k = the class method implementing the
          interface's method k (matched by name), wired via MethodFixups like the
          VMT. A class->interface assignment captures the IMT address. }
        for ii := 0 to implCnt - 1 do
        begin
          tmpCi := implIntf[ii];
          if IMTCount >= MAX_IMT then Error('too many interface method tables');
          IMTClass[IMTCount] := ci;
          IMTIntf[IMTCount] := tmpCi;
          IMTOff[IMTCount] := DataLen;
          Inc(IMTCount);
          for imSlot := 0 to UClsMCount[tmpCi] - 1 do
          begin
            imName := '';
            for i := 0 to UMthNLen[UClsMBase[tmpCi] + imSlot] - 1 do
              AppendChar(imName, TokChars[UMthNOff[UClsMBase[tmpCi] + imSlot] + i]);
            { By SIGNATURE, not by name: an OVERLOADED interface method has one
              slot per signature, and FindUMeth answers the class's FIRST method
              of the name for every one of them -- so `IThing.Pick(x)` and
              `IThing.Pick(x, y)` both dispatched to TThing.Pick(x) and the extra
              argument was read as garbage. Silent, and only through the
              interface: the direct class call resolved correctly all along
              (bug-p-interface-method-overload-picks-the-first-slot). }
            mmi := FindUMethForSig(ci, imName, UMthProc_[UClsMBase[tmpCi] + imSlot]);
            if mmi < 0 then Error('class does not implement interface method: ' + imName);
            imProc := UMthProc_[mmi];
            if MethodFixCount >= MAX_METHFIX then Error('too many method fixups (IMT)');
            MethodFixups[MethodFixCount].DataPos := DataLen;
            MethodFixups[MethodFixCount].ProcIdx := imProc;
            Inc(MethodFixCount);
            for i := 0 to 7 do begin if DataLen >= MAX_DATA then Error('data overflow'); Data[DataLen] := 0; Inc(DataLen); end;
          end;
        end;
      end
      else if (CurTok.Kind = tkPacked) or (CurTok.Kind = tkRecord) then
      begin
        isPackedRecord := CurTok.Kind = tkPacked;
        if isPackedRecord then
        begin
          Next;
          Expect(tkRecord, 'record');
        end
        else
          Next;
        ci := AddClassLikeType(FindUClass(tname), tnOff, tnLen, tname);
        UClsParent[ci] := -1;
        UClsIsRecord[ci] := True;
        if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'helper') and
           (Tokens[TokPos].Kind = tkFor) then
        begin
          { `record helper for <type>` — a TYPE HELPER: methods dispatch on
            values of the TARGET type; Self (param 0) is the target BY
            REFERENCE. Parsed with the advanced-record member machinery; the
            helper marker forks Self's type on both the decl and impl sides
            (they must agree — the b321 lesson). }
          Next;                       { helper }
          Expect(tkFor, 'for');
          fTk := ParseTypeKind;
          UClsHelperTk[ci] := Ord(fTk);
          UClsHelperRec[ci] := LastTypeRecId;
        end;
        ParseRecordFields(ci, isPackedRecord);
      end
      else if (CurTok.Kind = tkType) and (Tokens[TokPos].Kind = tkIdent) and
              CaseEqual(GetTokenStrFromRaw(Tokens[TokPos].SOffset, Tokens[TokPos].SLen), 'helper') and
              (TokPos + 1 < TokCount) and (Tokens[TokPos + 1].Kind = tkFor) then
      begin
        { `type helper for <type>` — FPC's alternate spelling of `record helper
          for <type>`. Same machinery: a helper-marked class-like entry whose
          methods dispatch on values of the TARGET type, Self by reference. The
          `record`/`type` keyword is cosmetic in FPC; both build the same helper. }
        Next;                       { type }
        ci := AddUClass(tnOff, tnLen);
        UClsParent[ci] := -1;
        UClsIsRecord[ci] := True;
        Next;                       { helper }
        Expect(tkFor, 'for');
        fTk := ParseTypeKind;
        UClsHelperTk[ci] := Ord(fTk);
        UClsHelperRec[ci] := LastTypeRecId;
        ParseRecordFields(ci, False);
      end
      else if CurTok.Kind = tkCaret then
      begin
        { Named pointer type alias: PFoo = ^TFoo }
        Next;
        targetNOff := Tokens[TokPos-1].SOffset;
        targetNLen := Tokens[TokPos-1].SLen;
        Inc(PtrElemDepth);        { `PFoo = ^TFoo` may forward-reference TFoo }
        fTk := ParseTypeKind;
        Dec(PtrElemDepth);
        RegisterPtrAlias(tnOff, tnLen, Ord(fTk), LastTypeRecId, targetNOff, targetNLen);
        if fTk = tyPointer then
        begin
          AliasPtrDepth[AliasCount-1] := LastTypePointerDepth + 1;
          AliasPtrBaseTk[AliasCount-1] := LastTypePointerBaseTk;
          AliasPtrBaseRec[AliasCount-1] := LastTypePointerBaseRec;
        end
        else
        begin
          AliasPtrDepth[AliasCount-1] := 1;
          AliasPtrBaseTk[AliasCount-1] := Ord(fTk);
          AliasPtrBaseRec[AliasCount-1] := LastTypeRecId;
        end;
        Eat(tkSemicolon);
      end
      else if CaseEqual(CurTok.SVal, 'set') then
      begin
        { Named set type: TFooSet = set of TFoo }
        Next;
        Expect(tkOf, 'of');
        ParseSetElemSpec;
        RegisterSetAlias(tnOff, tnLen, LastTypeSetEnumId, LastTypeSetElemTk);
        while not (CurTok.Kind in [tkSemicolon,tkEOF]) do Next;
      end
      else if CurTok.Kind = tkArray then
      begin
        Next; { consume 'array' }
        if CurTok.Kind = tkLBrack then
        begin
          { Named fixed-array type `TA = array[a..b (, c..d, ...)] of T` —
            register it so a var/field/param of type TA becomes a real array
            (1-D or flattened N-D). An anonymous nested fixed array
            (`array[a] of array[b] of T`) is merged into `array[a,b] of T`
            (identical FPC layout). Previously skipped → TA was not an array. }
          tdCnt := 0;
          tMoreDims := True;
          while tMoreDims do
          begin
            Next;   { consume '[' }
            repeat
              ParseArrayDimBounds(tdLo, tdHi);
              if tdCnt >= MAX_ARR_DIMS then Error('too many array dimensions');
              tdDimLo[tdCnt] := tdLo; tdDimSpan[tdCnt] := tdHi - tdLo + 1; Inc(tdCnt);
            until not Eat(tkComma);
            Expect(tkRBrack, ']');
            Expect(tkOf, 'of');
            { Continue only for a FIXED nested array, not a dynamic `array of`. }
            tMoreDims := (CurTok.Kind = tkArray) and (Tokens[TokPos].Kind = tkLBrack);
            if tMoreDims then Next;   { consume 'array'; loop head consumes '[' }
          end;
          { A FIXED named-array type as the element (`array[a..b] of TG`,
            `TG = array[c..d] of T`) has the SAME flat layout as `array[a..b,
            c..d] of T` — merge TG's dimensions into the outer list, exactly as
            the anonymous-nested form above does. Without this, ParseTypeKind
            resolves TG to its bare base element and the inner dimension is lost
            (the element stride collapses to the base type's size, corrupting
            p[i][j]). TG is already flattened in its own ArrType entry, so one
            merge covers arbitrary nesting depth. }
          fAi := -1;
          aElemStrCap := 0;
          if CurTok.Kind = tkIdent then fAi := FindArrayType(CurTok.SVal);
          if (fAi >= 0) and (not ArrTypeIsDyn[fAi]) then
          begin
            aElemStrCap := ArrTypeElemStrCap[fAi];
            if ArrTypeNDims[fAi] >= 2 then
            begin
              for tdi := 0 to ArrTypeNDims[fAi] - 1 do
              begin
                if tdCnt >= MAX_ARR_DIMS then Error('too many array dimensions');
                tdDimLo[tdCnt]   := ArrTypeDimLo[fAi * MAX_ARR_DIMS + tdi];
                tdDimSpan[tdCnt] := ArrTypeDimSpan[fAi * MAX_ARR_DIMS + tdi];
                Inc(tdCnt);
              end;
            end
            else
            begin
              if tdCnt >= MAX_ARR_DIMS then Error('too many array dimensions');
              tdDimLo[tdCnt]   := ArrTypeLo[fAi];
              tdDimSpan[tdCnt] := ArrTypeHi[fAi] - ArrTypeLo[fAi] + 1;
              Inc(tdCnt);
            end;
            aElemTk := IntToTypeKind(ArrTypeElemTk[fAi]);
            LastTypeRecId := ArrTypeElemRec[fAi];
            Next;   { consume the named array type }
          end
          else
          begin
            aElemTk := ParseTypeKind;
            aElemStrCap := LastTypeStrCap;
          end;
          if tdCnt = 1 then
          begin aLo := tdDimLo[0]; aHi := tdDimLo[0] + tdDimSpan[0] - 1; end
          else
          begin
            tflatLen := 1;
            for tdi := 0 to tdCnt - 1 do tflatLen := tflatLen * tdDimSpan[tdi];
            aLo := 0; aHi := tflatLen - 1;
          end;
          if ArrTypeCount >= MAX_TYPEALIAS then Error('too many array types');
          ArrTypeName[ArrTypeCount] := tname;
          ArrTypeLo[ArrTypeCount] := aLo;
          ArrTypeHi[ArrTypeCount] := aHi;
          ArrTypeElemTk[ArrTypeCount] := Ord(aElemTk);
          ArrTypeElemRec[ArrTypeCount] := LastTypeRecId;
          ArrTypePtrElemRec[ArrTypeCount] := LastTypePointerElemRec;
          if tdCnt >= 2 then ArrTypeNDims[ArrTypeCount] := tdCnt
          else ArrTypeNDims[ArrTypeCount] := 0;
          for tdi := 0 to tdCnt - 1 do
          begin
            ArrTypeDimLo[ArrTypeCount * MAX_ARR_DIMS + tdi]   := tdDimLo[tdi];
            ArrTypeDimSpan[ArrTypeCount * MAX_ARR_DIMS + tdi] := tdDimSpan[tdi];
          end;
          ArrTypeIsDyn[ArrTypeCount] := False;
          ArrTypeElemRowLen[ArrTypeCount] := 0;
          ArrTypeElemRowLo[ArrTypeCount] := 0;
          if (aElemTk = tyFixedString) or (aElemTk = tyShortString) then
            ArrTypeElemStrCap[ArrTypeCount] := aElemStrCap
          else
            ArrTypeElemStrCap[ArrTypeCount] := 0;
          ArrTypeUnitIdx[ArrTypeCount] := CurrentUnitIdx; Inc(ArrTypeCount);
        end
        else
        begin
          { Dynamic-array type alias `TArr = array of T` (nested: array of array
            of T). Register it so `var a: TArr` becomes a real dynamic array. }
          Expect(tkOf, 'of');
          if ArrTypeCount >= MAX_TYPEALIAS then Error('too many array types');
          tdCnt := 1; { reuse as dyn depth }
          while CurTok.Kind = tkArray do
          begin Next; Inc(tdCnt); Expect(tkOf, 'of'); end;
          { Element that is a named FIXED array (`TDA = array of T`): record the
            row shape so vars of this alias get SymDynElemRowLen; ParseTypeKind
            would collapse T to its base scalar and lose the row stride
            (bug-pascal-openarray-of-array-param-marshal). Depth-1 only. }
          ArrTypeElemRowLen[ArrTypeCount] := 0;
          ArrTypeElemRowLo[ArrTypeCount] := 0;
          fAi := -1;
          aElemStrCap := 0;
          if CurTok.Kind = tkIdent then fAi := FindArrayType(CurTok.SVal);
          if (fAi >= 0) and ArrTypeIsDyn[fAi] then
          begin
            { A named DYNAMIC-array alias as the element (`TIA2 = array of TIA`
              where `TIA = array of Integer`) composes its depth, exactly as the
              var-declaration path already did for the same type spelled inline
              (`var m: array of TIA`). Without this the else-arm below reached
              ParseTypeKind, which resolves TIA to its BASE scalar -- array-type
              aliases live in the ArrType table, not the scalar alias table -- so
              the alias silently became `array of Integer`. `m[0][0]` then read a
              heap handle as an Integer and printed a different number every run,
              and Length(m[0]) did the same; only SetLength(m[0], n) was loud,
              and only because codegen refused a depth-1 target.
              bug-p-array-of-a-named-dynamic-array-alias-loses-a-dimension }
            if (ArrTypeElemRowLen[fAi] <> 0) then
              Error('array of array of <fixed array type> not supported');
            aElemTk := IntToTypeKind(ArrTypeElemTk[fAi]);
            aElemStrCap := ArrTypeElemStrCap[fAi];
            LastTypeRecId := ArrTypeElemRec[fAi];
            LastTypePointerElemRec := ArrTypePtrElemRec[fAi];
            tdCnt := tdCnt + ArrTypeDynDepth[fAi];
            Next;               { consume the alias name }
          end
          else if (fAi >= 0) and (not ArrTypeIsDyn[fAi]) then
          begin
            if tdCnt > 1 then
              Error('array of array of <fixed array type> not supported');
            aElemTk := IntToTypeKind(ArrTypeElemTk[fAi]);
            LastTypeRecId := ArrTypeElemRec[fAi];
            LastTypePointerElemRec := ArrTypePtrElemRec[fAi];
            if (aElemTk = tyAnsiString) or (aElemTk = tyString) or
               (aElemTk = tyFixedString) or (aElemTk = tyShortString) or
               ((aElemTk = tyRecord) and RecordHasManagedFields(LastTypeRecId)) then
              Error('array of <fixed array of managed elements> not supported');
            ArrTypeElemRowLen[ArrTypeCount] := ArrTypeHi[fAi] - ArrTypeLo[fAi] + 1;
            ArrTypeElemRowLo[ArrTypeCount]  := ArrTypeLo[fAi];
            Next;               { consume the named array type }
          end
          else
          begin
            aElemTk := ParseTypeKind;
            aElemStrCap := LastTypeStrCap;
          end;
          ArrTypeName[ArrTypeCount] := tname;
          ArrTypeElemTk[ArrTypeCount] := Ord(aElemTk);
          if (aElemTk = tyFixedString) or (aElemTk = tyShortString) then
            ArrTypeElemStrCap[ArrTypeCount] := aElemStrCap
          else
            ArrTypeElemStrCap[ArrTypeCount] := 0;
          ArrTypeElemRec[ArrTypeCount] := LastTypeRecId;
          ArrTypePtrElemRec[ArrTypeCount] := LastTypePointerElemRec;
          ArrTypeNDims[ArrTypeCount] := 0;
          ArrTypeIsDyn[ArrTypeCount] := True;
          ArrTypeDynDepth[ArrTypeCount] := tdCnt;
          ArrTypeUnitIdx[ArrTypeCount] := CurrentUnitIdx; Inc(ArrTypeCount);
        end;
      end
      else if (CurTok.Kind = tkProcedure) or (CurTok.Kind = tkFunction) then
      begin
        { Procedural type: `T = procedure(...)` / `function(...): R [of object]`.
          The signature is parsed into a body-less Procs[] entry; the alias keeps
          its index (AliasProcSig) so an indirect call `v(args)` through a var of
          this type marshals args/return via the same machinery as a direct call. }
        mpi := ParseProcTypeSignature;
        if CurTok.Kind = tkOf then
        begin
          { `of object` — a method pointer: a 16-byte {Code,Data} value. The
            signature drives arg marshalling; Self (Data) is injected at the call. }
          Next;
          if CurTok.Kind = tkIdent then Next;   { consume `object` }
          RegisterMethodPtrTypeAlias(tnOff, tnLen, mpi, EnsureMethodPtrRec);
        end
        else
          RegisterProcTypeAlias(tnOff, tnLen, mpi);
        EatProcTypeCdecl(mpi);
      end
      else if (CurTok.Kind = tkInteger) or (CurTok.Kind = tkMinus) or (CurTok.Kind = tkString) then
      begin
        { Named ordinal subrange type: `T = lo..hi` (1..10, 'a'..'z'). Modelled as
          an alias to the base ordinal (tyChar for a char-literal bound, else
          tyInteger) — same treatment as an inline `var x: lo..hi` subrange (the
          bounds are not retained). }
        if CurTok.Kind = tkString then fTk := tyChar else fTk := tyInteger;
        subLoVal := ConstEval;     { low bound }
        Expect(tkDotDot, '..');
        subHiVal := ConstEval;     { high bound }
        RegisterGeneralAlias(tnOff, tnLen, Ord(fTk), REC_NONE);
        { RETAIN the bounds ({$R+} checks stores against them —
          feature-pascal-range-checks-r-plus; they used to be dropped). }
        AliasIsSub[AliasCount - 1] := True;
        AliasSubLo[AliasCount - 1] := subLoVal;
        AliasSubHi[AliasCount - 1] := subHiVal;
      end
      else if (CurTok.Kind = tkIdent) and IsClassType(CurTok.SVal) and
              ((TokPos >= TokCount) or (Tokens[TokPos].Kind = tkSemicolon)) then
      begin
        { Class-name alias: `TOptionList = TList;` (blcksock). Registered in
          the UClass alias table so FindUClass resolves the new name to the
          SAME class row — var decls, X.Create, casts and is/as all see it. }
        ci := FindUClass(CurTok.SVal);
        RegisterUClassAlias(tnOff, tnLen, ci);
        Next;
      end
      else if QualClassAliasCi >= 0 then
      begin
        { Unit-QUALIFIED class alias: `TThread = palthreadobj.TThread;` — the
          re-export a unit writes so its own importers can name a class it got
          from elsewhere, which pxx's non-transitive `uses` makes mandatory
          rather than a convenience. Same UClass alias row as the unqualified
          form above; only the lookahead differs. See QualClassAliasCi. }
        ci := QualClassAliasCi;
        RegisterUClassAlias(tnOff, tnLen, ci);
        Next;                        { the unit name }
        while CurTok.Kind = tkDot do
        begin
          Next;                      { '.' }
          Next;                      { the next name component }
        end;
      end
      else
      begin
        { Named simple type alias: PFoo = BaseType }
        fTk := ParseTypeKind;
        RegisterGeneralAlias(tnOff, tnLen, Ord(fTk), LastTypeRecId);
      end;
      SkipHintDirectives;   { type T = BaseType deprecated; }
      Eat(tkSemicolon);
    end;
  end;
  { Materialise deferred class-specialization methods after the section. The
    loop exited with the terminating token already loaded into CurTok (TokPos
    points past it); un-read it so the streamed methods are inserted before it,
    then reload CurTok from the first streamed token (or the terminator again if
    nothing was streamed). }
  { NOT from a nested class-local type section: flushing there would splice
    the pending method impls into the middle of the enclosing class body. }
  if (PendingSpecCount > 0) and (TypeSectionDepth = 0) then
  begin
    Dec(TokPos);
    FlushPendingClassSpecializations;
    Next;
  end;
  ResolvePendingPointerAliases;
end;

{ ===== Nested routines (Approach B: lambda-lifting) =====

  A procedure/function declared inside another routine's declaration section is
  NOT emitted in place (single-pass emission would drop its body into the middle
  of the enclosing routine's code). Instead, at the declaration point we:
    1. stash the nested routine's full token stream (PendNestTok), and
    2. rewrite the in-place copy into a FORWARD declaration so the enclosing
       body's calls to it resolve via the existing forward-completion path.
  When the enclosing routine finishes (end of ParseSubroutine),
  FlushPendingNestedProcs re-injects the stashed tokens after it, where the
  top-level driver parses them as ordinary sibling routines that complete the
  forward decl. This reuses the by-ref param ABI and forward machinery already
  byte-identical on all targets — no new per-target codegen.

  Slice 1: flatten only (own params/locals + globals).
  Slice 2a (this code): Self/field CAPTURE for a routine nested in a method. The
  lifted proc gains a trailing by-value param `__nestself: <EnclosingClass>`;
  implicit field/method references (and explicit `Self`) in the body are
  rewritten to go through it (`Rooms` -> `__nestself.Rooms`); call sites in the
  enclosing body get `Self` appended as the extra actual. Capture of an
  enclosing local/parameter is detected and rejected with a diagnostic (Slice 2b).

  PERFORMANCE: lifted nested routines are not speed-optimized — a captured field
  goes through the passed Self pointer rather than the enclosing frame's direct
  access. Correct and fully functional, just one extra indirection. }

{ Append s to TokChars and return its start offset (a fresh slice usable as a
  token's SOffset; SLen = Length(s)). }
function NestStrOff(const s: AnsiString): Integer;
var j: Integer;
begin
  Result := TokCharLen;
  if TokCharLen + Length(s) > STRING_CAP then Error('token char pool overflow');
  for j := 1 to Length(s) do
  begin
    TokChars[TokCharLen] := s[j];
    Inc(TokCharLen);
  end;
end;

{ Decimal of a non-negative integer (no IntToStr in the compiler's own RTL). }
function MangleSuffix(n: Integer): AnsiString;
var d: array[0..15] of Char; c, m: Integer; s: AnsiString;
begin
  if n <= 0 then begin Result := '0'; Exit; end;
  c := 0; m := n;
  while m > 0 do begin d[c] := Chr(Ord('0') + (m mod 10)); Inc(c); m := m div 10; end;
  s := '';
  while c > 0 do begin Dec(c); AppendChar(s, d[c]); end;
  Result := s;
end;

{ Lambda-lift descriptor lookup by (mangled, unique) routine name. }
function FindLiftDesc(const nm: AnsiString): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to LiftCount - 1 do
    if StrEqual(LiftName[i], nm) then begin Result := i; Exit; end;
end;

{ Re-scan a nested routine's header ';' (paren-depth 0), its 'begin', and its end
  starting at nestedStart, after token edits may have shifted positions. (Kept a
  top-level helper, not a nested routine, so the compiler can self-host without
  needing nested-routine capture for its own source.) }
{ Index-driven mirrors of PreScanSkipRoutineBody (which walks CurTok/Next). The
  nested-routine lifter rewrites Tokens[] directly, so it must locate a routine's
  OWN `begin` and its end without being fooled by an INNER routine's begin..end.
  Taking the first `begin` after the header is what mis-spanned every doubly
  nested routine — the lifter then cut the enclosing routine in half at the inner
  one's `end;` (bug-a-two-level-nested-routine-cannot-capture-anything). }

function NestIsRoutineDecl(idx: Integer): Boolean;
{ True for a routine DECLARATION at idx. A procedural TYPE (`= procedure(x: T)`,
  `: procedure of object`) never has an identifier straight after the keyword,
  which is exactly what separates the two here. }
begin
  NestIsRoutineDecl := (idx + 1 < TokCount) and
                       ((Tokens[idx].Kind = tkProcedure) or (Tokens[idx].Kind = tkFunction)) and
                       (Tokens[idx + 1].Kind = tkIdent);
end;

function NestRoutineEndAt(startIdx: Integer): Integer; forward;

function NestBodyBeginAt(hdrEnd: Integer): Integer;
{ hdrEnd = index of the `;` closing a routine header. Returns the index of that
  routine's own `begin`/`asm`, stepping OVER any inner routine declaration in the
  declaration part. Returns the `forward` token for a bodyless declaration. }
var cur: Integer;
begin
  cur := hdrEnd;
  while cur < TokCount do
  begin
    if (Tokens[cur].Kind = tkBegin) or (Tokens[cur].Kind = tkAsm) or
       (Tokens[cur].Kind = tkForward) then Break;
    if NestIsRoutineDecl(cur) then cur := NestRoutineEndAt(cur) else Inc(cur);
  end;
  NestBodyBeginAt := cur;
end;

function NestRoutineEndAt(startIdx: Integer): Integer;
{ startIdx = a routine declaration's `procedure`/`function` keyword. Returns the
  index just past its terminating `;`. Recurses through inner routines. }
var cur, depth, bb: Integer;
begin
  depth := 0; cur := startIdx;
  while cur < TokCount do
  begin
    if Tokens[cur].Kind = tkLParen then Inc(depth)
    else if Tokens[cur].Kind = tkRParen then Dec(depth)
    else if (Tokens[cur].Kind = tkSemicolon) and (depth = 0) then Break;
    Inc(cur);
  end;
  bb := NestBodyBeginAt(cur);
  if bb >= TokCount then begin NestRoutineEndAt := TokCount; Exit; end;
  if Tokens[bb].Kind = tkForward then
  begin
    cur := bb;
    while (cur < TokCount) and (Tokens[cur].Kind <> tkSemicolon) do Inc(cur);
    if cur < TokCount then Inc(cur);
    NestRoutineEndAt := cur;
    Exit;
  end;
  depth := 1; cur := bb + 1;
  while (cur < TokCount) and (depth > 0) do
  begin
    if (Tokens[cur].Kind = tkBegin) or (Tokens[cur].Kind = tkCase) or
       (Tokens[cur].Kind = tkTry) or (Tokens[cur].Kind = tkAsm) then Inc(depth)
    else if Tokens[cur].Kind = tkEnd then Dec(depth);
    Inc(cur);
  end;
  if (cur < TokCount) and (Tokens[cur].Kind = tkSemicolon) then Inc(cur);
  NestRoutineEndAt := cur;
end;

function NestRoutineDeclares(startIdx: Integer; const nm: AnsiString): Boolean;
{ Does the routine declared at startIdx have a param, local, const or type of
  its own named `nm`? Used to exempt a SIBLING routine from the call-site rename
  below: inside a routine that declares `helper`, the name means its own
  declaration, not a sibling routine of that name.
  bug-p-a-const-named-like-its-nested-routine-binds-the-routine }
var cur, depth, hdrE, bodyB: Integer; beforeColon: Boolean;
begin
  Result := False;
  depth := 0; cur := startIdx;
  while cur < TokCount do
  begin
    if Tokens[cur].Kind = tkLParen then Inc(depth)
    else if Tokens[cur].Kind = tkRParen then Dec(depth)
    else if (Tokens[cur].Kind = tkSemicolon) and (depth = 0) then Break;
    Inc(cur);
  end;
  hdrE := cur;
  if (startIdx + 2 < TokCount) and (Tokens[startIdx + 2].Kind = tkLParen) then
  begin
    beforeColon := True;
    for cur := startIdx + 3 to hdrE - 1 do
    begin
      if Tokens[cur].Kind = tkColon then beforeColon := False
      else if Tokens[cur].Kind = tkSemicolon then beforeColon := True
      else if (Tokens[cur].Kind = tkIdent) and beforeColon and
              CaseEqual(GetTokenStrFromRaw(Tokens[cur].SOffset, Tokens[cur].SLen), nm) then
      begin Result := True; Exit; end;
    end;
  end;
  bodyB := NestBodyBeginAt(hdrE);
  beforeColon := True; cur := hdrE + 1;
  while cur < bodyB do
  begin
    if NestIsRoutineDecl(cur) then begin cur := NestRoutineEndAt(cur); beforeColon := True; Continue; end;
    if (Tokens[cur].Kind = tkColon) or (Tokens[cur].Kind = tkEq) then beforeColon := False
    else if Tokens[cur].Kind = tkSemicolon then beforeColon := True
    else if (Tokens[cur].Kind = tkVar) or (Tokens[cur].Kind = tkConst) or (Tokens[cur].Kind = tkType) then beforeColon := True
    else if (Tokens[cur].Kind = tkIdent) and beforeColon and
            CaseEqual(GetTokenStrFromRaw(Tokens[cur].SOffset, Tokens[cur].SLen), nm) then
    begin Result := True; Exit; end;
    Inc(cur);
  end;
end;

procedure NestScanSpans(nestedStart: Integer; var hdrEnd, bodyBegin, finalCur: Integer);
var cur, depth: Integer;
begin
  depth := 0; cur := nestedStart;
  while cur < TokCount do
  begin
    if Tokens[cur].Kind = tkLParen then Inc(depth)
    else if Tokens[cur].Kind = tkRParen then Dec(depth)
    else if (Tokens[cur].Kind = tkSemicolon) and (depth = 0) then Break;
    Inc(cur);
  end;
  if cur >= TokCount then Error('nested routine: malformed header');
  hdrEnd := cur;
  cur := NestBodyBeginAt(hdrEnd);
  if (cur >= TokCount) or (Tokens[cur].Kind = tkForward) then
    Error('nested routine: expected begin');
  bodyBegin := cur;
  depth := 1; Inc(cur);
  while (cur < TokCount) and (depth > 0) do
  begin
    if (Tokens[cur].Kind = tkBegin) or (Tokens[cur].Kind = tkCase) or
       (Tokens[cur].Kind = tkTry) or (Tokens[cur].Kind = tkAsm) then Inc(depth)
    else if Tokens[cur].Kind = tkEnd then Dec(depth);
    Inc(cur);
  end;
  if (cur < TokCount) and (Tokens[cur].Kind = tkSemicolon) then Inc(cur);
  finalCur := cur;
end;

procedure ParseNestedRoutine;
const MAX_NEST_REFS = 4096; MAX_NEST_CAPS = 64; MAX_NEST_DEPTH = 32;
      MAX_NEST_SKIPS = 64;
var
  nestedStart, nameTokIdx, hdrEnd, bodyBegin, finalCur, cur, depth, i, j, remCount: Integer;
  parenOpen, parenClose: Integer;
  ci, descIdx: Integer;
  needSelf, beforeColon, isOwnName, found: Boolean;
  nsOff, nsLen, selfOff, mOff, mLen: Integer;
  ownN: array[0..127] of AnsiString;
  ownCount: Integer;
  fieldPos: array[0..MAX_NEST_REFS-1] of Integer;  { implicit field/method refs to prefix with __nestself. }
  fieldCnt: Integer;
  selfPos: array[0..MAX_NEST_REFS-1] of Integer;   { explicit `Self` tokens to rename to __nestself }
  selfCnt: Integer;
  namePos: array[0..MAX_NEST_REFS-1] of Integer;   { body refs to the routine's own name (result-var / recursion) -> mangled }
  nameCnt: Integer;
  nm, nestedName, mangled: AnsiString;
  sidx: Integer;
  ins: array[0..7] of TRawToken;
  parentBegin, parentEnd: Integer;
  k: Integer;
  shift, tmpPos: Integer;
  { captured enclosing locals/params (snapshot at the capture site) }
  capNm: array[0..MAX_NEST_CAPS-1] of AnsiString;
  capTk: array[0..MAX_NEST_CAPS-1] of TTypeKind;
  capRec, capDyn, capPtrRec, capProcSig: array[0..MAX_NEST_CAPS-1] of Integer;
  capPtrTk: array[0..MAX_NEST_CAPS-1] of TTypeKind;
  capArr: array[0..MAX_NEST_CAPS-1] of Boolean;
  capActOff: array[0..MAX_NEST_CAPS-1] of Integer;
  capCount: Integer;
  core: array[0..2*MAX_NEST_CAPS+3] of TRawToken;
  coreCount, nact, emitted: Integer;
  coreSelf: array[0..2*MAX_NEST_CAPS+3] of TRawToken;
  coreSelfCount: Integer;
  nestSelfOff, nestSelfLen: Integer;
  ins2: array[0..2*MAX_NEST_CAPS+7] of TRawToken;
  ins2Count, rp: Integer;
  { shadow stack for the transitive free-variable scan: while inside an inner
    nested routine's span, its own names are appended to ownN and ownCount is
    rolled back to shOwn[] when the scan leaves at shEnd[] }
  shEnd: array[0..MAX_NEST_DEPTH-1] of Integer;
  shOwn: array[0..MAX_NEST_DEPTH-1] of Integer;
  shTop, ihdrEnd, ibodyBegin: Integer;
  { spans in the parent's range where a sibling routine declares this routine's
    name of its own, so the call-site rename must not touch them }
  skipLo, skipHi: array[0..MAX_NEST_SKIPS-1] of Integer;
  skipCount, sk: Integer;
  skipped: Boolean;
begin
  nestedStart := TokPos - 1;   { the 'procedure'/'function' token (= CurTok) }
  nameTokIdx := nestedStart + 1;
  if Tokens[nameTokIdx].Kind <> tkIdent then Error('nested routine: expected name');
  nestedName := GetTokenStrFromRaw(Tokens[nameTokIdx].SOffset, Tokens[nameTokIdx].SLen);

  NestScanSpans(nestedStart, hdrEnd, bodyBegin, finalCur);

  { Param-list parens (if any). }
  parenOpen := -1; parenClose := -1;
  if Tokens[nameTokIdx + 1].Kind = tkLParen then
  begin
    parenOpen := nameTokIdx + 1;
    depth := 0; cur := parenOpen;
    while cur < hdrEnd do
    begin
      if Tokens[cur].Kind = tkLParen then Inc(depth)
      else if Tokens[cur].Kind = tkRParen then
      begin Dec(depth); if depth = 0 then begin parenClose := cur; Break; end; end;
      Inc(cur);
    end;
  end;

  ci := -1;
  if CurSelfClass >= REC_UCLASS_BASE then ci := CurSelfClass - REC_UCLASS_BASE;

  { Own names: the routine's own param names (idents before ':' inside the param
    parens) and decl-section local names (idents before ':'/'=' between the
    header and 'begin'). These shadow enclosing scope and must never be captured. }
  ownCount := 0;
  if parenOpen >= 0 then
  begin
    beforeColon := True;
    for i := parenOpen + 1 to parenClose - 1 do
    begin
      if Tokens[i].Kind = tkColon then beforeColon := False
      else if Tokens[i].Kind = tkSemicolon then beforeColon := True
      else if (Tokens[i].Kind = tkIdent) and beforeColon and (ownCount < 128) then
      begin ownN[ownCount] := GetTokenStrFromRaw(Tokens[i].SOffset, Tokens[i].SLen); Inc(ownCount); end;
    end;
  end;
  beforeColon := True;
  i := hdrEnd + 1;
  while i < bodyBegin do
  begin
    { An inner routine's own params/locals are NOT ours — stepping over its whole
      declaration is what keeps `procedure C(k: Integer)` from making `k` look
      like a local of ours and silently suppressing our capture of an enclosing
      `k`. Its own free variables are collected by the scan below instead. }
    if NestIsRoutineDecl(i) then begin i := NestRoutineEndAt(i); beforeColon := True; Continue; end;
    if (Tokens[i].Kind = tkColon) or (Tokens[i].Kind = tkEq) then beforeColon := False
    else if Tokens[i].Kind = tkSemicolon then beforeColon := True
    else if (Tokens[i].Kind = tkVar) or (Tokens[i].Kind = tkConst) or (Tokens[i].Kind = tkType) then beforeColon := True
    else if (Tokens[i].Kind = tkIdent) and beforeColon and (ownCount < 128) then
    begin ownN[ownCount] := GetTokenStrFromRaw(Tokens[i].SOffset, Tokens[i].SLen); Inc(ownCount); end;
    Inc(i);
  end;

  { Free-variable analysis over the body. Classify each non-selector ident:
    own (skip) / explicit Self (rename) / enclosing local-or-param (capture by
    ref) / implicit Self field-or-method (capture Self) / global-or-other (skip).

    The scan is TRANSITIVE: an inner nested routine is walked, not skipped, and
    its free variables become OUR captures too. Nothing else can thread an
    enclosing frame down to it — when the inner routine is itself lifted (during
    our own top-level re-parse) the only scope it can reach is ours, so a
    variable two levels up has to arrive as a parameter of ours first. Skipping
    inner routines is what made capture at depth 2 impossible in every direction
    (bug-a-two-level-nested-routine-cannot-capture-anything). Depth 3+ then falls
    out by construction: each level threads through what the levels below need.

    An inner routine's own name, params and locals shadow ours for the length of
    its span, pushed on shOwn/shEnd and popped when the scan leaves it. }
  needSelf := False; fieldCnt := 0; selfCnt := 0; capCount := 0; nameCnt := 0;
  shTop := 0;
  i := hdrEnd;
  while i < finalCur do
  begin
    while (shTop > 0) and (i >= shEnd[shTop - 1]) do
    begin Dec(shTop); ownCount := shOwn[shTop]; end;
    if NestIsRoutineDecl(i) then
    begin
      if shTop >= MAX_NEST_DEPTH then Error('nested routine: nesting too deep');
      shEnd[shTop] := NestRoutineEndAt(i); shOwn[shTop] := ownCount; Inc(shTop);
      { the inner routine's own name (its result var inside its own body), then
        its params, then its declaration-part locals }
      if ownCount < 128 then
      begin ownN[ownCount] := GetTokenStrFromRaw(Tokens[i+1].SOffset, Tokens[i+1].SLen); Inc(ownCount); end;
      depth := 0; ihdrEnd := i;
      while ihdrEnd < TokCount do
      begin
        if Tokens[ihdrEnd].Kind = tkLParen then Inc(depth)
        else if Tokens[ihdrEnd].Kind = tkRParen then Dec(depth)
        else if (Tokens[ihdrEnd].Kind = tkSemicolon) and (depth = 0) then Break;
        Inc(ihdrEnd);
      end;
      if Tokens[i + 2].Kind = tkLParen then
      begin
        beforeColon := True;
        for j := i + 3 to ihdrEnd - 1 do
        begin
          if Tokens[j].Kind = tkColon then beforeColon := False
          else if Tokens[j].Kind = tkSemicolon then beforeColon := True
          else if (Tokens[j].Kind = tkIdent) and beforeColon and (ownCount < 128) then
          begin ownN[ownCount] := GetTokenStrFromRaw(Tokens[j].SOffset, Tokens[j].SLen); Inc(ownCount); end;
        end;
      end;
      ibodyBegin := NestBodyBeginAt(ihdrEnd);
      beforeColon := True; j := ihdrEnd + 1;
      while j < ibodyBegin do
      begin
        if NestIsRoutineDecl(j) then begin j := NestRoutineEndAt(j); beforeColon := True; Continue; end;
        if (Tokens[j].Kind = tkColon) or (Tokens[j].Kind = tkEq) then beforeColon := False
        else if Tokens[j].Kind = tkSemicolon then beforeColon := True
        else if (Tokens[j].Kind = tkVar) or (Tokens[j].Kind = tkConst) or (Tokens[j].Kind = tkType) then beforeColon := True
        else if (Tokens[j].Kind = tkIdent) and beforeColon and (ownCount < 128) then
        begin ownN[ownCount] := GetTokenStrFromRaw(Tokens[j].SOffset, Tokens[j].SLen); Inc(ownCount); end;
        Inc(j);
      end;
      Inc(i); Continue;
    end;
    { our own declaration part carries no references to classify — only the
      inner routines inside it (handled above) and our body do }
    if (i < bodyBegin) and (shTop = 0) then begin Inc(i); Continue; end;
    if Tokens[i].Kind = tkIdent then
    begin
      if (i > 0) and (Tokens[i-1].Kind = tkDot) then begin Inc(i); Continue; end;
      nm := GetTokenStrFromRaw(Tokens[i].SOffset, Tokens[i].SLen);
      { Own params/locals/consts FIRST: a declaration inside the routine shadows
        the routine's own name, so `procedure Inner; const inner: integer = 0;`
        means the const in the body, not the routine. This test used to run
        AFTER the own-name test below, which rewrote every such reference to the
        mangled routine name and failed with `undefined variable (Inner$13)` —
        for a const, a var and a parameter alike, and only in a NESTED routine,
        because the mangle is the one thing the non-nested path does not do.
        bug-p-a-const-named-like-its-nested-routine-binds-the-routine }
      isOwnName := False;
      for j := 0 to ownCount - 1 do
        if CaseEqual(ownN[j], nm) then begin isOwnName := True; Break; end;
      if isOwnName then begin Inc(i); Continue; end;
      { the routine's own name in its body = the function-result variable
        (FuncName := expr) or a recursive self-call; both must follow the mangle.
        A function's result variable is NOT in ownN — it is the routine name
        itself — so reordering above cannot swallow it. }
      if CaseEqual(nm, nestedName) then
      begin
        if nameCnt < MAX_NEST_REFS then begin namePos[nameCnt] := i; Inc(nameCnt); end;
        Inc(i); Continue;
      end;
      if CaseEqual(nm, 'Self') then
      begin
        needSelf := True;
        if selfCnt < MAX_NEST_REFS then begin selfPos[selfCnt] := i; Inc(selfCnt); end;
      end
      else
      begin
        sidx := FindSym(nm);
        if (sidx >= 0) and ((Syms[sidx].Kind = skLocal) or (Syms[sidx].Kind = skParam)) then
        begin
          { Capture an enclosing local/param by reference. Snapshot its type now —
            the enclosing Syms slot is recycled before the lifted body is parsed.
            The lifted param keeps the same name so body refs resolve to it. }
          found := False;
          for j := 0 to capCount - 1 do
            if CaseEqual(capNm[j], nm) then begin found := True; Break; end;
          if not found then
          begin
            if capCount >= MAX_NEST_CAPS then Error('nested routine: too many captured variables');
            capNm[capCount] := Syms[sidx].Name;
            if Syms[sidx].IsArray and (SymDynDepth[sidx] > 0) then
            begin
              capTk[capCount] := Syms[sidx].ElemType;
              capRec[capCount] := Syms[sidx].ElemRecName;
              capArr[capCount] := True;
              capDyn[capCount] := SymDynDepth[sidx];
            end
            else if Syms[sidx].IsArray then
              Error('nested routine: capture of fixed-size array ''' + nm + ''' not yet supported')
            else
            begin
              capTk[capCount] := Syms[sidx].TypeKind;
              capRec[capCount] := Syms[sidx].RecName;
              capArr[capCount] := False;
              capDyn[capCount] := 0;
            end;
            capPtrTk[capCount] := Syms[sidx].PtrElemTk;
            capPtrRec[capCount] := Syms[sidx].PtrElemRec;
            capProcSig[capCount] := SymProcSig[sidx];
            Inc(capCount);
          end;
        end
        else if (sidx < 0) and (ci >= 0) and
                ((FindUField(ci, nm) >= 0) or (FindUMeth(ci, nm) >= 0)) then
        begin
          needSelf := True;
          if fieldCnt < MAX_NEST_REFS then begin fieldPos[fieldCnt] := i; Inc(fieldCnt); end;
        end;
      end;
    end;
    Inc(i);
  end;

  if needSelf and (ci < 0) then
    Error('nested routine: Self/field used but enclosing routine is not a method');

  { Mangle the routine to a unique name so the lift descriptor and forward-
    completion can't collide with another routine (the in-place forward decl and
    the stashed definition share this single rewritten name token). }
  mangled := nestedName;
  AppendChar(mangled, '$');
  mangled := mangled + MangleSuffix(nestedStart);
  mOff := NestStrOff(mangled); mLen := Length(mangled);
  Tokens[nameTokIdx].SOffset := mOff;
  Tokens[nameTokIdx].SLen := mLen;
  { Body refs to the own name (result var / recursion) are handled below,
    AFTER the field-prefix inserts (needSelf block) -- a self-referencing
    call may need the same extra actuals (Self/captures) a sibling call
    gets, which requires knowing whether the field-prefix pass shifted this
    occurrence's token position first (bug-nested-proc-sibling-call-
    unresolved symptom 2: a capturing nested routine's self-recursive call
    was missing its hidden captured-frame argument). }

  { Record the lift descriptor consumed by ParseSubroutine to inject the captured
    params (Self + by-ref enclosing vars). }
  if LiftCount >= MAX_LIFTS then Error('too many lifted nested routines');
  if LiftCapTot + capCount >= MAX_LIFT_CAPS then Error('too many nested captures');
  descIdx := LiftCount;
  LiftName[descIdx] := mangled;
  LiftNeedSelf[descIdx] := needSelf;
  LiftSelfCi[descIdx] := ci;
  LiftCapStart[descIdx] := LiftCapTot;
  LiftCapCount[descIdx] := capCount;
  for k := 0 to capCount - 1 do
  begin
    LiftCapName[LiftCapTot]   := capNm[k];
    LiftCapTk[LiftCapTot]     := capTk[k];
    LiftCapRec[LiftCapTot]    := capRec[k];
    LiftCapArr[LiftCapTot]    := capArr[k];
    LiftCapDyn[LiftCapTot]    := capDyn[k];
    LiftCapPtrTk[LiftCapTot]  := capPtrTk[k];
    LiftCapPtrRec[LiftCapTot] := capPtrRec[k];
    LiftCapProcSig[LiftCapTot]:= capProcSig[k];
    Inc(LiftCapTot);
  end;
  Inc(LiftCount);

  { Build the comma-separated actual list `Self, cap0, cap1, ...` (no outer
    parens) for external call sites (enclosing body / sibling routines,
    below). A self-recursive call site needs the same captured-var actuals
    but CANNOT use the literal `Self` -- that identifier isn't in scope
    inside the now-lifted, top-level routine body; the routine's own hidden
    parameter is named `__nestself` instead (captured vars, by contrast, use
    the SAME name either way, since the lifted routine's by-ref param shares
    the captured var's original name). `coreSelf` mirrors `core` with that
    one substitution, built alongside it so both are ready before the
    needSelf block runs. Moved earlier than the original single use site so
    both this and the self-splice below can share them. }
  selfOff := NestStrOff('Self');
  nestSelfOff := NestStrOff('__nestself'); nestSelfLen := 10;
  for k := 0 to capCount - 1 do
    capActOff[k] := NestStrOff(capNm[k]);
  coreCount := 0; emitted := 0;
  if needSelf then
  begin
    core[coreCount].Kind := tkIdent; core[coreCount].IVal := 0; core[coreCount].Line := 0;
    core[coreCount].SOffset := selfOff; core[coreCount].SLen := 4; Inc(coreCount); Inc(emitted);
  end;
  for k := 0 to capCount - 1 do
  begin
    if emitted > 0 then
    begin
      core[coreCount].Kind := tkComma; core[coreCount].IVal := 0; core[coreCount].Line := 0;
      core[coreCount].SOffset := 0; core[coreCount].SLen := 0; Inc(coreCount);
    end;
    core[coreCount].Kind := tkIdent; core[coreCount].IVal := 0; core[coreCount].Line := 0;
    core[coreCount].SOffset := capActOff[k]; core[coreCount].SLen := Length(capNm[k]); Inc(coreCount); Inc(emitted);
  end;
  nact := emitted;

  coreSelfCount := 0; emitted := 0;
  if needSelf then
  begin
    coreSelf[coreSelfCount].Kind := tkIdent; coreSelf[coreSelfCount].IVal := 0; coreSelf[coreSelfCount].Line := 0;
    coreSelf[coreSelfCount].SOffset := nestSelfOff; coreSelf[coreSelfCount].SLen := nestSelfLen; Inc(coreSelfCount); Inc(emitted);
  end;
  for k := 0 to capCount - 1 do
  begin
    if emitted > 0 then
    begin
      coreSelf[coreSelfCount].Kind := tkComma; coreSelf[coreSelfCount].IVal := 0; coreSelf[coreSelfCount].Line := 0;
      coreSelf[coreSelfCount].SOffset := 0; coreSelf[coreSelfCount].SLen := 0; Inc(coreSelfCount);
    end;
    coreSelf[coreSelfCount].Kind := tkIdent; coreSelf[coreSelfCount].IVal := 0; coreSelf[coreSelfCount].Line := 0;
    coreSelf[coreSelfCount].SOffset := capActOff[k]; coreSelf[coreSelfCount].SLen := Length(capNm[k]); Inc(coreSelfCount); Inc(emitted);
  end;

  { Body rewrites for Self capture: rename explicit `Self`, prefix `__nestself .`
    on each implicit field/method ref. Captured locals need no body rewrite — the
    injected by-ref param shares their name. }
  if needSelf then
  begin
    nsOff := NestStrOff('__nestself'); nsLen := 10;
    for k := 0 to selfCnt - 1 do
    begin
      Tokens[selfPos[k]].SOffset := nsOff;
      Tokens[selfPos[k]].SLen := nsLen;
    end;
    for k := fieldCnt - 1 downto 0 do
    begin
      ins[0].Kind := tkIdent; ins[0].IVal := 0; ins[0].Line := Tokens[fieldPos[k]].Line;
      ins[0].SOffset := nsOff; ins[0].SLen := nsLen;
      ins[1].Kind := tkDot; ins[1].IVal := 0; ins[1].Line := Tokens[fieldPos[k]].Line;
      ins[1].SOffset := 0; ins[1].SLen := 0;
      InsertTokens(fieldPos[k], ins, 2);
    end;
    NestScanSpans(nestedStart, hdrEnd, bodyBegin, finalCur);   { field prefixes shifted positions }
  end;

  { Body refs to the own name (result-var write, or a self-recursive call):
    rename to the mangled name; a genuine recursive CALL (not a result-var
    write, detected by NOT being followed by `:=`) also needs the same extra
    actuals (Self/captures) spliced in when this routine captures anything
    (nact > 0) -- the lifted routine's own by-ref capture params share the
    captured var's original name, so re-passing e.g. `acc` from inside a
    recursive call correctly forwards the same by-ref binding transitively.
    Without this, a capturing routine's self-call kept the OLD (pre-lift)
    arity, one hidden arg short (bug-nested-proc-sibling-call-unresolved
    symptom 2).

    namePos[] positions were captured during the free-variable scan, in the
    SAME pass as fieldPos[] -- and the needSelf block above may have already
    inserted 2 tokens at each fieldPos[] location. Any namePos[k] whose
    ORIGINAL position was past a given fieldPos[] entry has silently shifted
    by +2 for it (insertions preserve relative order, so the total shift for
    a stationary point is exactly 2 * count(fieldPos[j] < namePos[k]),
    independent of processing order). Correct for that, then splice in
    descending corrected-position order (mirroring fieldPos[]'s own pattern)
    so each insertion doesn't invalidate a not-yet-processed lower position. }
  for k := 0 to nameCnt - 1 do
  begin
    shift := 0;
    for j := 0 to fieldCnt - 1 do
      if fieldPos[j] < namePos[k] then Inc(shift, 2);
    namePos[k] := namePos[k] + shift;
  end;
  for k := 1 to nameCnt - 1 do
  begin
    tmpPos := namePos[k]; j := k - 1;
    while (j >= 0) and (namePos[j] < tmpPos) do
    begin
      namePos[j + 1] := namePos[j]; Dec(j);
    end;
    namePos[j + 1] := tmpPos;
  end;
  for k := 0 to nameCnt - 1 do
  begin
    Tokens[namePos[k]].SOffset := mOff;
    Tokens[namePos[k]].SLen := mLen;
    if (nact > 0) and (Tokens[namePos[k] + 1].Kind <> tkAssign) then
    begin
      if Tokens[namePos[k] + 1].Kind = tkLParen then
      begin
        depth := 0; rp := namePos[k] + 1;
        while rp < TokCount do
        begin
          if Tokens[rp].Kind = tkLParen then Inc(depth)
          else if Tokens[rp].Kind = tkRParen then begin Dec(depth); if depth = 0 then Break; end;
          Inc(rp);
        end;
        ins2Count := 0;
        if Tokens[namePos[k] + 2].Kind <> tkRParen then
        begin
          ins2[0].Kind := tkComma; ins2[0].IVal := 0; ins2[0].Line := Tokens[namePos[k]].Line; ins2[0].SOffset := 0; ins2[0].SLen := 0;
          ins2Count := 1;
        end;
        for j := 0 to coreSelfCount - 1 do begin ins2[ins2Count] := coreSelf[j]; ins2[ins2Count].Line := Tokens[namePos[k]].Line; Inc(ins2Count); end;
        InsertTokens(rp, ins2, ins2Count);
      end
      else
      begin
        { bare self-call `name;` -> `name( __nestself, ... )` }
        ins2[0].Kind := tkLParen; ins2[0].IVal := 0; ins2[0].Line := Tokens[namePos[k]].Line; ins2[0].SOffset := 0; ins2[0].SLen := 0;
        ins2Count := 1;
        for j := 0 to coreSelfCount - 1 do begin ins2[ins2Count] := coreSelf[j]; ins2[ins2Count].Line := Tokens[namePos[k]].Line; Inc(ins2Count); end;
        ins2[ins2Count].Kind := tkRParen; ins2[ins2Count].IVal := 0; ins2[ins2Count].Line := Tokens[namePos[k]].Line; ins2[ins2Count].SOffset := 0; ins2[ins2Count].SLen := 0; Inc(ins2Count);
        InsertTokens(namePos[k] + 1, ins2, ins2Count);
      end;
    end;
  end;
  if (nact > 0) and (nameCnt > 0) then
    NestScanSpans(nestedStart, hdrEnd, bodyBegin, finalCur);   { self-call splices may have shifted positions }

  i := finalCur; parentBegin := -1;
  while i < TokCount do
  begin
    if NestIsRoutineDecl(i) then i := NestRoutineEndAt(i)
    else if Tokens[i].Kind = tkBegin then begin parentBegin := i; Break; end
    else Inc(i);
  end;
  if parentBegin >= 0 then
  begin
    depth := 1; i := parentBegin + 1;
    while (i < TokCount) and (depth > 0) do
    begin
      if (Tokens[i].Kind = tkBegin) or (Tokens[i].Kind = tkCase) or
         (Tokens[i].Kind = tkTry) or (Tokens[i].Kind = tkAsm) then Inc(depth)
      else if Tokens[i].Kind = tkEnd then Dec(depth);
      Inc(i);
    end;
    parentEnd := i;
    { Lower bound is finalCur (not parentBegin): also rewrite call sites inside
      not-yet-lifted SIBLING nested routines declared between this routine and
      the enclosing 'begin' (skipped above only to locate parentBegin, not to
      exempt them) -- otherwise a sibling calling this routine (e.g. `b` calling
      `a`, both nested in the same `outer`) keeps the unmangled name and fails
      to resolve once this routine's own declaration is rewritten to `forward`
      (bug-nested-proc-sibling-call-unresolved). }
    { …but a sibling that declares a param/local/const of this routine's name
      means ITS OWN declaration by that name, not this routine. Renaming there
      produced `var Helper$357: Integer` — a parse error naming a routine the
      program never wrote. Collect those spans first (walking token by token
      also reaches routines nested inside a sibling), then skip them below. Same
      rule as the own-name test in the free-variable scan, at the one site that
      rewrites OTHER routines' bodies.
      bug-p-a-const-named-like-its-nested-routine-binds-the-routine }
    skipCount := 0;
    i := finalCur;
    while i < parentEnd do
    begin
      if NestIsRoutineDecl(i) and NestRoutineDeclares(i, nestedName) then
      begin
        j := NestRoutineEndAt(i);
        if skipCount < MAX_NEST_SKIPS then
        begin skipLo[skipCount] := i; skipHi[skipCount] := j; Inc(skipCount); end;
        i := j;                { anything nested inside it is shadowed too }
      end
      else
        Inc(i);
    end;

    for i := parentEnd - 1 downto finalCur do
    begin
      skipped := False;
      for sk := 0 to skipCount - 1 do
        if (i >= skipLo[sk]) and (i < skipHi[sk]) then begin skipped := True; Break; end;
      if (not skipped) and (Tokens[i].Kind = tkIdent) and
         CaseEqual(GetTokenStrFromRaw(Tokens[i].SOffset, Tokens[i].SLen), nestedName) and
         ((i = 0) or (Tokens[i-1].Kind <> tkDot)) then
      begin
        Tokens[i].SOffset := mOff; Tokens[i].SLen := mLen;   { rename call -> mangled }
        if nact > 0 then
        begin
          if Tokens[i+1].Kind = tkLParen then
          begin
            depth := 0; rp := i + 1;
            while rp < TokCount do
            begin
              if Tokens[rp].Kind = tkLParen then Inc(depth)
              else if Tokens[rp].Kind = tkRParen then begin Dec(depth); if depth = 0 then Break; end;
              Inc(rp);
            end;
            ins2Count := 0;
            if Tokens[i+2].Kind <> tkRParen then   { non-empty arg list: prepend a comma }
            begin
              ins2[0].Kind := tkComma; ins2[0].IVal := 0; ins2[0].Line := Tokens[i].Line; ins2[0].SOffset := 0; ins2[0].SLen := 0;
              ins2Count := 1;
            end;
            for k := 0 to coreCount - 1 do begin ins2[ins2Count] := core[k]; ins2[ins2Count].Line := Tokens[i].Line; Inc(ins2Count); end;
            InsertTokens(rp, ins2, ins2Count);
          end
          else
          begin
            { bare call `name;` -> `name( Self, ... )` }
            ins2[0].Kind := tkLParen; ins2[0].IVal := 0; ins2[0].Line := Tokens[i].Line; ins2[0].SOffset := 0; ins2[0].SLen := 0;
            ins2Count := 1;
            for k := 0 to coreCount - 1 do begin ins2[ins2Count] := core[k]; ins2[ins2Count].Line := Tokens[i].Line; Inc(ins2Count); end;
            ins2[ins2Count].Kind := tkRParen; ins2[ins2Count].IVal := 0; ins2[ins2Count].Line := Tokens[i].Line; ins2[ins2Count].SOffset := 0; ins2[ins2Count].SLen := 0; Inc(ins2Count);
            InsertTokens(i + 1, ins2, ins2Count);
          end;
        end;
      end;
    end;
  end;

  { Stash the (possibly rewritten) full routine [nestedStart, finalCur) for
    top-level re-parse. Token SOffsets index TokChars (never shifted). Record this
    routine's start offset within the buffer so the flush emits one DeclItem span
    per routine (a body may stash several back to back). }
  if PendNestCount + (finalCur - nestedStart) >= MAX_NESTED_TOKENS then
    Error('nested routine token buffer overflow');
  if PendNestRtnCount >= MAX_LIFTS then Error('too many nested routines in one body');
  PendNestRtnStart[PendNestRtnCount] := PendNestCount;
  Inc(PendNestRtnCount);
  for i := nestedStart to finalCur - 1 do
  begin
    PendNestTok[PendNestCount] := Tokens[i];
    Inc(PendNestCount);
  end;

  { Rewrite the in-place copy to `<header>; forward;` by replacing the body range
    (hdrEnd+1 .. finalCur-1) with the two tokens `forward ;`. }
  Tokens[hdrEnd + 1].Kind := tkForward;
  Tokens[hdrEnd + 1].IVal := 0; Tokens[hdrEnd + 1].Line := Tokens[nestedStart].Line;
  Tokens[hdrEnd + 1].SOffset := 0; Tokens[hdrEnd + 1].SLen := 0;
  Tokens[hdrEnd + 2].Kind := tkSemicolon;
  Tokens[hdrEnd + 2].IVal := 0; Tokens[hdrEnd + 2].Line := Tokens[nestedStart].Line;
  Tokens[hdrEnd + 2].SOffset := 0; Tokens[hdrEnd + 2].SLen := 0;
  remCount := finalCur - (hdrEnd + 3);
  if remCount > 0 then
  begin
    for i := finalCur to TokCount - 1 do
      Tokens[i - remCount] := Tokens[i];
    TokCount := TokCount - remCount;
    { The removed inner body shifts every later token down by remCount — keep the
      body pass's still-pending DeclItem spans and body-begin marker in sync. }
    AdjustPass2Spans(finalCur, -remCount);
  end;

  { CurTok is still the 'procedure'/'function' token; parse the forward decl now
    (registers the signature, then Exits without emitting a body). }
  ParseSubroutine;
end;

{ Re-inject any nested routines stashed during this routine's body so they parse
  as top-level siblings that complete the forward decls left in place by
  ParseNestedRoutine. APPENDED at end-of-stream (not spliced mid-stream): the
  body pass replays fixed DeclItem spans, so a mid-stream insert would shift the
  remaining spans + the body-begin marker out from under it. Each stashed routine
  becomes its own DeclItem span; the body-pass driver loops `while i < DeclItemCount`
  so these appended items are parsed in turn (and may themselves append deeper
  nested routines). Outside the body pass (single-pass legacy path) the same append
  works: the driver there also consumes trailing DeclItems. }
procedure FlushPendingNestedProcs;
var appendStart, i, r, rtnStart, rtnEnd: Integer;
begin
  if PendNestCount = 0 then Exit;
  appendStart := TokCount;
  for i := 0 to PendNestCount - 1 do
  begin
    EnsureTokCapacity(TokCount + 1);
    Tokens[TokCount] := PendNestTok[i];
    Inc(TokCount); EnsureTokCapacity(TokCount+1);
  end;
  { One DeclItem span per stashed routine (boundaries recorded at stash time), so
    the body-pass driver parses each as its own sibling. }
  for r := 0 to PendNestRtnCount - 1 do
  begin
    if DeclItemCount >= MAX_DECL_ITEMS then Error('too many declarations (nested routine flush)');
    rtnStart := appendStart + PendNestRtnStart[r];
    if r + 1 < PendNestRtnCount then
      rtnEnd := appendStart + PendNestRtnStart[r + 1]
    else
      rtnEnd := TokCount;
    DeclItemStart[DeclItemCount] := rtnStart;
    DeclItemEnd[DeclItemCount]   := rtnEnd;
    Inc(DeclItemCount);
  end;
  PendNestCount := 0;
  PendNestRtnCount := 0;
end;

{ `label a, b;` — a declaration section like var/const/type, and reachable from
  two places (a program/unit's decl block and a routine's). It was written out
  twice; the routine copy sat AFTER the var/const/type loop, so the canonical
  ISO order (label first) parsed the labels and then met `var` where the caller
  expected `begin`. One body, called from both.
  bug-a-a-label-section-must-come-last-in-a-routine }
procedure ParseLabelSection;
{ `label a, b;` and `label 1, 2;` alike. NUMERIC labels are the traditional
  Pascal spelling and were refused outright -- the loop below only accepted
  tkIdent, so `label 1;` died with "Expected: begin". LabelSpanOfTok gives a
  numeric token the same kind of span an identifier already has. }
begin
  Next;                             { 'label' }
  while (CurTok.Kind = tkIdent) or (CurTok.Kind = tkInteger) do
  begin
    if GotoLabelCount >= MAX_GOTO_LABELS then Error('too many labels');
    LabelSpanOfTok(TokPos-1, GotoLabelNOff[GotoLabelCount], GotoLabelNLen[GotoLabelCount]);
    GotoLabelCodePos[GotoLabelCount] := -1;
    Inc(GotoLabelCount);
    Next;
    if not Eat(tkComma) then Break;
  end;
  Eat(tkSemicolon);
end;
