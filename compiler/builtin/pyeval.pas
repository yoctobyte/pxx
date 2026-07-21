{ pyeval — a real exec()/eval() for the Python subset uforth's PYTHON-bodied
  words are written in (feature-lib-pyexec, engine 1: the reflective
  tree-walker). Correctness reference; a JIT drops in later over the same
  grammar.

  MILESTONE 1 (this unit's initial scope): the 60 "pure-stack" corpus blocks —
  the ones that touch only push/pop/fpush/fpop and NO other vm.* member. That is
  exactly the set of PYTHON-bodied stdlib words (SWAP, OVER, ROT, /, MOD, bit
  ops, ternary min/max, …) that SEGFAULT today because pyexec is a stub.

  Grammar: statements separated by `;`/newline, plus COMPOUND blocks with Python
  indentation — if/elif/else, while (+break), for-in over range()/lists.
  Assignment + augassign, expression statements. Full expression grammar:
  ternary, boolean and/or/not, comparisons (incl. chains), |^& bit ops, <<>>
  shifts, +-*/ // %, unary -/+/~, calls, int/float/hex literals, names,
  True/False/None. Locals live in pyeval's own name/value arrays (LclSet) —
  TPyDict keyed by an AnsiString-boxed Variant is unreliable (see LclSet note).

  Still out of scope (M2/M3, or the bignum tail): attribute access (vm.here),
  subscripts (vm.memory[i]), method calls (vm.define_word), def, arbitrary-
  precision ints (`x & 0xFFFFFFFFFFFFFFFF` as unsigned), f-strings. Rejected with
  a clear error rather than misbehaving.

  Host bridge (M1 convention): a bare call `push(x)` / `pop()` / `fpush(x)` /
  `fpop()` dispatches through PyHostCall(g["vm"], name, args) — the trampoline
  reflects the method on vm's class (case-insensitively) and calls its code
  pointer through a typed proc-pointer cast whose shape matches (RetKind, Arity,
  float-ness). pxx's own codegen supplies each target's ABI; no hand asm. See
  test/test_pyeval_m1.pas for the standalone driver.

  IMPLEMENTATION NOTE — every node evaluator is a PROCEDURE returning through a
  `var res: Variant`, never a Variant-returning function. A Variant function whose
  Result is assigned from another Variant call corrupts the value under the
  current codegen (NRVO/hidden-dest aliasing — see
  project_variant_fn_return_forward_nrvo_corruption / a filed Track A ticket).
  var-out procedures sidestep it entirely. Helpers that BUILD a variant via
  pointer writes (Make*, pyadd_v, …) are safe as functions.

  NOT auto-used by NilPy yet: build + test standalone first so a parse error here
  cannot break every NilPy compile. Wiring exec()->EvalPyStmts is the last step
  of the arc (feature-lib-pyexec build plan step 5). }
unit pyeval;

interface

uses pylib, typinfo;

{ Run a statement sequence `src` with globals g / locals l (Python's explicit
  exec form; uforth always passes both). Assignments write locals; name reads
  try locals then globals. }
procedure EvalPyStmts(const src: AnsiString; g: TPyDict; l: TPyDict);

{ Reflect `name` on vm's class and call it with the variant args held in the
  TPyList `args` (args.at(0..count-1)); the boxed result comes back in `res`.
  Args ride in a TPyList rather than an `array of Variant`: an OPEN array of
  Variant silently miscompiles (indexing/Length reads only the first element —
  Track A ticket), and a class value is just a pointer that lowers cleanly.
  Public so the eventual bound-method path (M3) and tests can share it. }
procedure PyHostCall(vmobj: Pointer; const name: AnsiString;
                     args: TPyList; var res: Variant);

implementation

const
  { Ord(TTypeKind) codes (defs.inc); the enum itself is compiler-internal and not
    visible to a builtin unit, so the reflection blob's numeric kinds are used raw. }
  TK_DOUBLE  = 19;
  TK_VARIANT = 22;

  { Token kinds — plain integer consts (not an enum) so they are valid `case`
    labels; pxx rejects Ord(enumconst) as a case label. }
  PK_EOF    = 0;
  PK_NAME   = 1;
  PK_INT    = 2;
  PK_FLOAT  = 3;
  PK_STR    = 4;
  PK_OP     = 5;
  PK_NL     = 6;
  PK_INDENT = 7;
  PK_DEDENT = 8;

type
  PPyRec = ^TPyRec;
  TPyRec = record
    VType:   Int64;
    Payload: Int64;
  end;

  { pointer types for boxing/unboxing reflected fields by TTypeKind }
  PLongInt = ^LongInt;
  PByte    = ^Byte;
  PSingle  = ^Single;
  PVariant = ^Variant;

  { Trampoline thunk shapes the M1 host methods use (Self = leading Pointer). }
  TPushFn  = procedure(self: Pointer; const v: Variant);
  TPopFn   = function(self: Pointer): Variant;
  TFpushFn = procedure(self: Pointer; v: Double);
  TFpopFn  = function(self: Pointer): Double;

{ ---- variant makers (build via pointer writes -> safe as functions) ---- }

function MakeFloat(d: Double): Variant;
var r: PPyRec;
begin
  r := PPyRec(@Result);
  r^.VType := 3;               { VT_DOUBLE }
  PDouble(@r^.Payload)^ := d;
end;

function MakeStr(const s: AnsiString): Variant;
var r: PPyRec;
begin
  r := PPyRec(@Result);
  r^.VType := 6;               { VT_STRING }
  PAnsiString(@r^.Payload)^ := s;
end;

function MakeNone: Variant;
var r: PPyRec;
begin
  r := PPyRec(@Result);
  r^.VType := 0; r^.Payload := 0;
end;

{ ---- host-call trampoline ---- }

{ Case-insensitive method lookup over the class hierarchy. GetMethInfoByName is
  case-SENSITIVE, but Pascal identifiers are case-insensitive and the Python
  corpus spells calls lowercase (`pop`) against methods RTTI records as declared
  (`Pop`), so the bridge must fold case. }
function PyLowerStr(const s: AnsiString): AnsiString;
var i: Integer; c: Char;
begin
  Result := s;
  for i := 1 to Length(Result) do
  begin
    c := Result[i];
    if (c >= 'A') and (c <= 'Z') then Result[i] := Chr(Ord(c) + 32);
  end;
end;

function PyFindMethCI(cls: PClassRTTI; const name: AnsiString): PMethInfo;
var curr: PClassRTTI; meths: PMethInfo; i: Integer; lname: AnsiString;
begin
  PyFindMethCI := nil;
  lname := PyLowerStr(name);
  curr := cls;
  while curr <> nil do
  begin
    if curr^.MethCount > 0 then
    begin
      meths := curr^.MethsPtr;
      for i := 0 to Integer(curr^.MethCount) - 1 do
        if PyLowerStr(meths[i].NamePtr^) = lname then
        begin
          PyFindMethCI := @meths[i];
          Exit;
        end;
    end;
    curr := PClassRTTI(curr^.ParentRTTI);
  end;
end;

procedure PyHostCall(vmobj: Pointer; const name: AnsiString;
                     args: TPyList; var res: Variant);
var
  cls: PClassRTTI;
  mi:  PMethInfo;
  pushfn: TPushFn; popfn: TPopFn; fpushfn: TFpushFn; fpopfn: TFpopFn;
  a0: Variant;
begin
  cls := GetInstanceRTTI(vmobj);
  if cls = nil then
  begin
    writeln('pyeval: no RTTI on vm for host call ', name);
    Halt(1);
  end;
  mi := PyFindMethCI(cls, name);
  if mi = nil then
  begin
    writeln('pyeval: vm has no method ', name);
    Halt(1);
  end;

  { M1 dispatch: the four stack shapes, keyed on (RetKind, Arity, float-ness).
    Arity counts Self, so a 1-arg method has Arity 2. }
  if (mi^.RetKind = 0) and (mi^.Arity = 2) then
  begin
    { procedure(const Variant) vs procedure(Double) — float param? }
    a0 := args.at(0);
    if PInt64(mi^.ParamKinds)[1] = TK_DOUBLE then
    begin
      fpushfn := TFpushFn(mi^.Code);
      fpushfn(vmobj, pyvar_to_float(a0));
    end
    else
    begin
      pushfn := TPushFn(mi^.Code);
      pushfn(vmobj, a0);
    end;
    res := MakeNone;
  end
  else if (mi^.RetKind = TK_VARIANT) and (mi^.Arity = 1) then
  begin
    popfn := TPopFn(mi^.Code);
    res := popfn(vmobj);
  end
  else if (mi^.RetKind = TK_DOUBLE) and (mi^.Arity = 1) then
  begin
    fpopfn := TFpopFn(mi^.Code);
    res := MakeFloat(fpopfn(vmobj));
  end
  else
  begin
    writeln('pyeval: unsupported host-call shape for ', name,
            ' (RetKind=', mi^.RetKind, ' Arity=', mi^.Arity, ')');
    Halt(1);
  end;
end;

{ ---- field (attribute) reflection: M2 ---- }

{ Read field `name` on `obj` and box it by its TTypeKind. Scalar kinds unbox to
  int/bool/float; a string field to a str variant; anything else (a class-valued
  field like memory/stack) is boxed as VT_OBJECT holding the field's stored
  pointer, so a following subscript / method call can reach it. }
procedure PyFieldGet(obj: Pointer; const name: AnsiString; var res: Variant);
var
  cls: PClassRTTI;
  kind: Int64;
  p: Pointer;
  r: PPyRec;
begin
  cls := GetInstanceRTTI(obj);
  if cls = nil then begin writeln('pyeval: no RTTI for attribute ', name); Halt(1); end;
  p := GetFieldPtr(obj, cls, name, kind);
  if p = nil then begin writeln('pyeval: object has no attribute ', name); Halt(1); end;
  r := PPyRec(@res);
  case kind of
    1: res := pyvar_of_int(PLongInt(p)^);        { tyInteger — 4-byte }
    2: res := pyvar_of_bool(PByte(p)^ <> 0);     { tyBoolean }
    3: res := pyvar_of_int(PByte(p)^);           { tyChar }
    13: res := pyvar_of_int(PInt64(p)^);         { tyInt64 }
    18: res := MakeFloat(PSingle(p)^);           { tySingle }
    19: res := MakeFloat(PDouble(p)^);           { tyDouble }
    22: res := PVariant(p)^;                      { tyVariant — copy the slot }
    23: res := MakeStr(PAnsiString(p)^);          { tyAnsiString }
  else
    { class / aggregate field: the slot holds an object pointer; expose it as a
      VT_OBJECT so subscripts and method calls can reach the container }
    r^.VType := 7; r^.Payload := PInt64(p)^;
  end;
end;

{ Write `val` into scalar/string field `name` on `obj`, coercing to the field's
  kind. Object-typed fields are not writable this way in M2 (would need lifetime
  handling); rejected. }
procedure PyFieldSet(obj: Pointer; const name: AnsiString; const val: Variant);
var
  cls: PClassRTTI;
  kind: Int64;
  p: Pointer;
begin
  cls := GetInstanceRTTI(obj);
  if cls = nil then begin writeln('pyeval: no RTTI for attribute ', name); Halt(1); end;
  p := GetFieldPtr(obj, cls, name, kind);
  if p = nil then begin writeln('pyeval: object has no attribute ', name); Halt(1); end;
  case kind of
    1: PLongInt(p)^ := pyvar_to_int(val);
    2: if pyvar_to_bool(val) then PByte(p)^ := 1 else PByte(p)^ := 0;
    3: PByte(p)^ := pyvar_to_int(val) and $FF;
    13: PInt64(p)^ := pyvar_to_int(val);
    18: PSingle(p)^ := pyvar_to_float(val);
    19: PDouble(p)^ := pyvar_to_float(val);
    22: PVariant(p)^ := val;
    23: PAnsiString(p)^ := pystr_of(val);
  else
    begin writeln('pyeval: cannot assign to object-typed attribute ', name); Halt(1); end;
  end;
end;

{ container[index] read. `container` is a VT_OBJECT variant; a list yields the
  element (Python negative indexing), a bytes object an int, a dict the value at
  the key. Slices are not handled here (M2b). }
procedure PySubscriptGet(const container: Variant; const index: Variant;
                         var res: Variant);
var o: TObject; li: TPyList; by: TPyBytes; di: TPyDict; i, n: Int64;
begin
  if PPyRec(@container)^.VType <> 7 then
  begin writeln('pyeval: cannot subscript a non-container'); Halt(1); end;
  o := TObject(Pointer(PPyRec(@container)^.Payload));
  if o is TPyList then
  begin
    li := TPyList(o); n := li.count; i := pyvar_to_int(index);
    if i < 0 then i := i + n;
    if (i < 0) or (i >= n) then begin writeln('pyeval: list index out of range'); Halt(1); end;
    res := li.at(i);
  end
  else if o is TPyBytes then
  begin
    by := TPyBytes(o); n := by.count; i := pyvar_to_int(index);
    if i < 0 then i := i + n;
    if (i < 0) or (i >= n) then begin writeln('pyeval: index out of range'); Halt(1); end;
    res := pyvar_of_int(by.at(i));
  end
  else if o is TPyDict then
  begin
    di := TPyDict(o);
    res := di.fetch(index);
  end
  else
    begin writeln('pyeval: unsupported subscript target'); Halt(1); end;
end;

{ container[index] = val }
procedure PySubscriptSet(const container: Variant; const index: Variant;
                         const val: Variant);
var o: TObject; li: TPyList; by: TPyBytes; di: TPyDict; i, n: Int64;
begin
  if PPyRec(@container)^.VType <> 7 then
  begin writeln('pyeval: cannot subscript-assign a non-container'); Halt(1); end;
  o := TObject(Pointer(PPyRec(@container)^.Payload));
  if o is TPyList then
  begin
    li := TPyList(o); n := li.count; i := pyvar_to_int(index);
    if i < 0 then i := i + n;
    if (i < 0) or (i >= n) then begin writeln('pyeval: list assignment index out of range'); Halt(1); end;
    li.put(i, val);
  end
  else if o is TPyBytes then
  begin
    by := TPyBytes(o); n := by.count; i := pyvar_to_int(index);
    if i < 0 then i := i + n;
    if (i < 0) or (i >= n) then begin writeln('pyeval: index out of range'); Halt(1); end;
    by.put(i, pyvar_to_int(val) and $FF);
  end
  else if o is TPyDict then
  begin
    di := TPyDict(o);
    di.store(index, val);
  end
  else
    begin writeln('pyeval: unsupported subscript-assign target'); Halt(1); end;
end;

{ ---- tokenizer ---- }

var
  { token arrays (module-global; EvalPyStmts is not reentrant across a single
    source, which is fine — uforth runs one block body at a time) }
  TkKind:  array of Integer;
  TkText:  array of AnsiString;
  TkInt:   array of Int64;
  TkFloat: array of Double;
  TkN:     Integer;

  Src:  AnsiString;
  SLen: Integer;
  Pos:  Integer;      { 1-based cursor into Src during tokenize }
  Cur:  Integer;      { current token index during eval }

  EnvG: TPyDict;   { host-provided globals (read-only here); holds "vm" etc. }

  { Local scope kept as parallel arrays rather than a TPyDict: TPyDict keyed by a
    Variant boxed from an AnsiString is unreliable (store/indexof box the string
    inconsistently, and a heap key's bytes go stale — see the boxing landmine in
    pylib). Owned AnsiString names compared with `=` are exact and stable. }
  LclNames: array of AnsiString;
  LclVals:  array of Variant;
  LclN:     Integer;

  { Control-flow state. `Executing` gates side effects: while walking a
    not-taken branch (if/elif/else, or a while/for that skips its body once to
    advance past it) the grammar is still consumed but calls don't dispatch,
    stores don't write, and undefined names resolve to None instead of erroring.
    `BreakFlag` unwinds the innermost loop. }
  Executing: Boolean;
  BreakFlag: Boolean;
  { set by ExecStatement when the statement was a compound block (if/while/for):
    such a statement self-terminates at its DEDENT, so no `;`/NL separator follows. }
  StmtWasCompound: Boolean;

procedure AddTok(kind: Integer; const text: AnsiString; iv: Int64; fv: Double);
begin
  if TkN >= Length(TkKind) then
  begin
    if Length(TkKind) = 0 then SetLength(TkKind, 64)
    else SetLength(TkKind, Length(TkKind) * 2);
    SetLength(TkText, Length(TkKind));
    SetLength(TkInt, Length(TkKind));
    SetLength(TkFloat, Length(TkKind));
  end;
  TkKind[TkN] := kind;
  TkText[TkN] := text;
  TkInt[TkN] := iv;
  TkFloat[TkN] := fv;
  TkN := TkN + 1;
end;

function IsDigit(c: Char): Boolean;
begin
  IsDigit := (c >= '0') and (c <= '9');
end;

function IsHexDigit(c: Char): Boolean;
begin
  IsHexDigit := IsDigit(c) or ((c >= 'a') and (c <= 'f')) or
                ((c >= 'A') and (c <= 'F'));
end;

function IsIdentStart(c: Char): Boolean;
begin
  IsIdentStart := ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z'))
                  or (c = '_');
end;

function IsIdentChar(c: Char): Boolean;
begin
  IsIdentChar := IsIdentStart(c) or IsDigit(c);
end;

function HexVal(c: Char): Int64;
begin
  if IsDigit(c) then HexVal := Ord(c) - Ord('0')
  else if (c >= 'a') and (c <= 'f') then HexVal := Ord(c) - Ord('a') + 10
  else HexVal := Ord(c) - Ord('A') + 10;
end;

procedure TokError(const msg: AnsiString);
begin
  writeln('pyeval tokenizer: ', msg);
  Halt(1);
end;

procedure Tokenize(const s: AnsiString);
var
  c, c2: Char;
  start: Integer;
  ident, op, str: AnsiString;
  iv: Int64;
  fv, scale: Double;
  isFloat: Boolean;
  atLineStart: Boolean;
  col, sp: Integer;
  indent: array of Integer;   { indentation stack; indent[0] = 0 }
  nInd: Integer;
begin
  Src := s; SLen := Length(s); Pos := 1; TkN := 0;
  SetLength(indent, 64); indent[0] := 0; nInd := 1;
  atLineStart := True;
  while Pos <= SLen do
  begin
    { Python offside rule: at the start of each logical (non-blank, non-comment)
      line, compare leading-whitespace width to the indent stack and emit
      INDENT / DEDENT tokens. Blank and comment-only lines never change indent. }
    if atLineStart then
    begin
      sp := Pos; col := 0;
      while (sp <= SLen) and ((Src[sp] = ' ') or (Src[sp] = #9)) do
      begin col := col + 1; sp := sp + 1; end;
      { blank line or comment-only line: consume through its newline, no change }
      if (sp > SLen) or (Src[sp] = #10) or (Src[sp] = #13) or (Src[sp] = '#') then
      begin
        while (Pos <= SLen) and (Src[Pos] <> #10) do Pos := Pos + 1;
        if Pos <= SLen then Pos := Pos + 1;   { the newline }
        continue;   { still atLineStart }
      end;
      Pos := sp;   { skip the leading whitespace }
      if col > indent[nInd-1] then
      begin
        if nInd >= Length(indent) then SetLength(indent, Length(indent) * 2);
        indent[nInd] := col; nInd := nInd + 1;
        AddTok(PK_INDENT, '', 0, 0);
      end
      else
        while (nInd > 1) and (col < indent[nInd-1]) do
        begin nInd := nInd - 1; AddTok(PK_DEDENT, '', 0, 0); end;
      atLineStart := False;
    end;
    c := Src[Pos];
    if c = #10 then
    begin
      AddTok(PK_NL, '', 0, 0);
      Pos := Pos + 1;
      atLineStart := True;
      continue;
    end;
    { whitespace (not newline) }
    if (c = ' ') or (c = #9) or (c = #13) then
    begin
      Pos := Pos + 1;
      continue;
    end;
    { comment (to end of line; the newline is handled at the top of the loop) }
    if c = '#' then
    begin
      while (Pos <= SLen) and (Src[Pos] <> #10) do Pos := Pos + 1;
      continue;
    end;
    { number }
    if IsDigit(c) then
    begin
      { hex }
      if (c = '0') and (Pos + 1 <= SLen) and
         ((Src[Pos+1] = 'x') or (Src[Pos+1] = 'X')) then
      begin
        Pos := Pos + 2;
        iv := 0;
        if (Pos > SLen) or (not IsHexDigit(Src[Pos])) then
          TokError('malformed hex literal');
        while (Pos <= SLen) and (IsHexDigit(Src[Pos]) or (Src[Pos] = '_')) do
        begin
          if Src[Pos] <> '_' then iv := iv * 16 + HexVal(Src[Pos]);
          Pos := Pos + 1;
        end;
        AddTok(PK_INT, '', iv, 0);
        continue;
      end;
      { decimal int or float }
      start := Pos;
      iv := 0; isFloat := False;
      while (Pos <= SLen) and (IsDigit(Src[Pos]) or (Src[Pos] = '_')) do
      begin
        if Src[Pos] <> '_' then iv := iv * 10 + (Ord(Src[Pos]) - Ord('0'));
        Pos := Pos + 1;
      end;
      fv := iv;
      if (Pos <= SLen) and (Src[Pos] = '.') then
      begin
        isFloat := True;
        Pos := Pos + 1;
        scale := 0.1;
        while (Pos <= SLen) and IsDigit(Src[Pos]) do
        begin
          fv := fv + (Ord(Src[Pos]) - Ord('0')) * scale;
          scale := scale * 0.1;
          Pos := Pos + 1;
        end;
      end;
      if (Pos <= SLen) and ((Src[Pos] = 'e') or (Src[Pos] = 'E')) then
        TokError('float exponent literals not supported in M1');
      if isFloat then AddTok(PK_FLOAT, '', 0, fv)
      else AddTok(PK_INT, '', iv, 0);
      continue;
    end;
    { identifier / keyword }
    if IsIdentStart(c) then
    begin
      { reject f-strings up front (M1-rest) }
      if ((c = 'f') or (c = 'F')) and (Pos + 1 <= SLen) and
         ((Src[Pos+1] = '''') or (Src[Pos+1] = '"')) then
        TokError('f-strings not supported in M1');
      start := Pos;
      while (Pos <= SLen) and IsIdentChar(Src[Pos]) do Pos := Pos + 1;
      ident := Copy(Src, start, Pos - start);
      AddTok(PK_NAME, ident, 0, 0);
      continue;
    end;
    { string literal }
    if (c = '''') or (c = '"') then
    begin
      c2 := c;
      Pos := Pos + 1;
      str := '';
      while (Pos <= SLen) and (Src[Pos] <> c2) do
      begin
        if (Src[Pos] = '\') and (Pos + 1 <= SLen) then
        begin
          Pos := Pos + 1;
          case Src[Pos] of
            'n': str := str + #10;
            't': str := str + #9;
            'r': str := str + #13;
            '\': str := str + '\';
            '''': str := str + '''';
            '"': str := str + '"';
            '0': str := str + #0;
          else
            str := str + Src[Pos];
          end;
        end
        else
          str := str + Src[Pos];
        Pos := Pos + 1;
      end;
      if Pos > SLen then TokError('unterminated string');
      Pos := Pos + 1;   { closing quote }
      AddTok(PK_STR, str, 0, 0);
      continue;
    end;
    { operators / punctuation — longest match first }
    c2 := #0;
    if Pos + 1 <= SLen then c2 := Src[Pos+1];
    { 3-char: //= <<= >>= }
    if ((c = '/') and (c2 = '/') and (Pos+2 <= SLen) and (Src[Pos+2] = '=')) then
    begin AddTok(PK_OP, '//=', 0, 0); Pos := Pos + 3; continue; end;
    if ((c = '<') and (c2 = '<') and (Pos+2 <= SLen) and (Src[Pos+2] = '=')) then
    begin AddTok(PK_OP, '<<=', 0, 0); Pos := Pos + 3; continue; end;
    if ((c = '>') and (c2 = '>') and (Pos+2 <= SLen) and (Src[Pos+2] = '=')) then
    begin AddTok(PK_OP, '>>=', 0, 0); Pos := Pos + 3; continue; end;
    { 2-char }
    op := '';
    if (c = '/') and (c2 = '/') then op := '//'
    else if (c = '*') and (c2 = '*') then op := '**'
    else if (c = '<') and (c2 = '<') then op := '<<'
    else if (c = '>') and (c2 = '>') then op := '>>'
    else if (c = '<') and (c2 = '=') then op := '<='
    else if (c = '>') and (c2 = '=') then op := '>='
    else if (c = '=') and (c2 = '=') then op := '=='
    else if (c = '!') and (c2 = '=') then op := '!='
    else if (c = '+') and (c2 = '=') then op := '+='
    else if (c = '-') and (c2 = '=') then op := '-='
    else if (c = '*') and (c2 = '=') then op := '*='
    else if (c = '%') and (c2 = '=') then op := '%='
    else if (c = '&') and (c2 = '=') then op := '&='
    else if (c = '|') and (c2 = '=') then op := '|='
    else if (c = '^') and (c2 = '=') then op := '^=';
    if op <> '' then
    begin AddTok(PK_OP, op, 0, 0); Pos := Pos + 2; continue; end;
    { 1-char }
    case c of
      '+', '-', '*', '/', '%', '&', '|', '^', '~',
      '<', '>', '=', '(', ')', '[', ']', ',', ':', '.', ';':
        begin
          AddTok(PK_OP, Copy(Src, Pos, 1), 0, 0);
          Pos := Pos + 1;
        end;
    else
      TokError('unexpected character ' + Copy(Src, Pos, 1));
    end;
  end;
  { close any open blocks at end of input }
  if (TkN > 0) and (TkKind[TkN-1] <> PK_NL) then AddTok(PK_NL, '', 0, 0);
  while nInd > 1 do begin nInd := nInd - 1; AddTok(PK_DEDENT, '', 0, 0); end;
  AddTok(PK_EOF, '', 0, 0);
end;

{ ---- evaluator (recursive descent; every node returns via a var-out param) ---- }

procedure EvalError(const msg: AnsiString);
begin
  writeln('pyeval: ', msg);
  Halt(1);
end;

function CurKind: Integer;
begin
  CurKind := TkKind[Cur];
end;

function CurText: AnsiString;
begin
  CurText := TkText[Cur];
end;

function IsOp(const s: AnsiString): Boolean;
begin
  IsOp := (TkKind[Cur] = PK_OP) and (TkText[Cur] = s);
end;

function IsKw(const s: AnsiString): Boolean;
begin
  IsKw := (TkKind[Cur] = PK_NAME) and (TkText[Cur] = s);
end;

procedure Advance;
begin
  if TkKind[Cur] <> PK_EOF then Cur := Cur + 1;
end;

procedure ExpectOp(const s: AnsiString);
begin
  if not IsOp(s) then EvalError('expected ' + s);
  Advance;
end;

function LclFind(const name: AnsiString): Integer;
var i: Integer;
begin
  LclFind := -1;
  for i := 0 to LclN - 1 do
    if LclNames[i] = name then begin LclFind := i; Exit; end;
end;

procedure LclSet(const name: AnsiString; const v: Variant);
var i: Integer;
begin
  i := LclFind(name);
  if i >= 0 then begin LclVals[i] := v; Exit; end;
  if LclN >= Length(LclNames) then
  begin
    if Length(LclNames) = 0 then SetLength(LclNames, 16)
    else SetLength(LclNames, Length(LclNames) * 2);
    SetLength(LclVals, Length(LclNames));
  end;
  LclNames[LclN] := name;
  LclVals[LclN] := v;
  LclN := LclN + 1;
end;

procedure EnvGet(const name: AnsiString; var res: Variant);
var i: Integer;
begin
  i := LclFind(name);
  if i >= 0 then
    res := LclVals[i]
  else if (EnvG <> nil) and (EnvG.indexof(name) >= 0) then
    res := EnvG.fetch(name)
  else if not Executing then
    res := MakeNone      { walking a skipped branch — names may be undefined }
  else
  begin
    EvalError('name not defined: ' + name);
    res := MakeNone;
  end;
end;

procedure ParseExpr(var res: Variant); forward;   { conditional/ternary — lowest }
procedure ParseCall(const callee: AnsiString; var res: Variant); forward;
procedure ParseMethodCall(const recv: Variant; const mname: AnsiString;
                          var res: Variant); forward;

{ atom, then a postfix chain of `.attr` (field read) and `[index]` (subscript). }
procedure ParsePrimary(var res: Variant);
var name, fld: AnsiString; recv, idx, elem: Variant; li: TPyList;
begin
  { ---- atom ---- }
  if TkKind[Cur] = PK_INT then
  begin res := pyvar_of_int(TkInt[Cur]); Advance; end
  else if TkKind[Cur] = PK_FLOAT then
  begin res := MakeFloat(TkFloat[Cur]); Advance; end
  else if TkKind[Cur] = PK_STR then
  begin res := MakeStr(TkText[Cur]); Advance; end
  else if IsOp('[') then
  begin
    { list literal }
    Advance;
    li := TPyList.Create;
    while not IsOp(']') do
    begin
      ParseExpr(elem);
      li.append(elem);
      if IsOp(',') then Advance
      else if not IsOp(']') then EvalError('expected , or ] in list literal');
    end;
    ExpectOp(']');
    PPyRec(@res)^.VType := 7; PPyRec(@res)^.Payload := Int64(Pointer(li));
  end
  else if TkKind[Cur] = PK_NAME then
  begin
    name := TkText[Cur];
    if name = 'True' then begin Advance; res := pyvar_of_bool(True); end
    else if name = 'False' then begin Advance; res := pyvar_of_bool(False); end
    else if name = 'None' then begin Advance; res := MakeNone; end
    else
    begin
      Advance;
      if IsOp('(') then ParseCall(name, res)
      else EnvGet(name, res);
    end;
  end
  else if IsOp('(') then
  begin Advance; ParseExpr(res); ExpectOp(')'); end
  else
  begin EvalError('unexpected token in expression: "' + TkText[Cur] + '"'); res := MakeNone; end;

  { ---- postfix chain ---- }
  while IsOp('.') or IsOp('[') do
  begin
    if IsOp('.') then
    begin
      Advance;
      if TkKind[Cur] <> PK_NAME then EvalError('expected attribute name after "."');
      fld := TkText[Cur]; Advance;
      recv := res;
      if IsOp('(') then
        ParseMethodCall(recv, fld, res)
      else if Executing then PyFieldGet(pyvarobj(recv), fld, res)
      else res := MakeNone;
    end
    else
    begin
      Advance;
      ParseExpr(idx);
      ExpectOp(']');
      recv := res;
      if Executing then PySubscriptGet(recv, idx, res) else res := MakeNone;
    end;
  end;
end;

procedure ParseUnary(var res: Variant);
var t: Variant;
begin
  if IsOp('-') then
  begin Advance; ParseUnary(t); res := pyneg_v(t); Exit; end;
  if IsOp('+') then
  begin Advance; ParseUnary(res); Exit; end;
  if IsOp('~') then
  begin Advance; ParseUnary(t); res := pyinvert_v(t); Exit; end;
  ParsePrimary(res);
end;

procedure ParseMul(var res: Variant);
var a, b: Variant;
begin
  ParseUnary(a);
  while IsOp('*') or IsOp('/') or IsOp('//') or IsOp('%') do
  begin
    if IsOp('*') then begin Advance; ParseUnary(b); a := pymul_v(a, b); end
    else if IsOp('//') then begin Advance; ParseUnary(b); a := pyfloordiv_v(a, b); end
    else if IsOp('%') then begin Advance; ParseUnary(b); a := pymod_v(a, b); end
    else begin Advance; ParseUnary(b);
      a := MakeFloat(pyvar_to_float(a) / pyvar_to_float(b)); end;
  end;
  res := a;
end;

procedure ParseAdd(var res: Variant);
var a, b: Variant;
begin
  ParseMul(a);
  while IsOp('+') or IsOp('-') do
  begin
    if IsOp('+') then begin Advance; ParseMul(b); a := pyadd_v(a, b); end
    else begin Advance; ParseMul(b); a := pysub_v(a, b); end;
  end;
  res := a;
end;

procedure ParseShift(var res: Variant);
var a, b: Variant;
begin
  ParseAdd(a);
  while IsOp('<<') or IsOp('>>') do
  begin
    if IsOp('<<') then begin Advance; ParseAdd(b); a := pyshl_v(a, b); end
    else begin Advance; ParseAdd(b); a := pyshr_v(a, b); end;
  end;
  res := a;
end;

procedure ParseBitAnd(var res: Variant);
var a, b: Variant;
begin
  ParseShift(a);
  while IsOp('&') do begin Advance; ParseShift(b); a := pybitand_v(a, b); end;
  res := a;
end;

procedure ParseBitXor(var res: Variant);
var a, b: Variant;
begin
  ParseBitAnd(a);
  while IsOp('^') do begin Advance; ParseBitAnd(b); a := pybitxor_v(a, b); end;
  res := a;
end;

procedure ParseBitOr(var res: Variant);
var a, b: Variant;
begin
  ParseBitXor(a);
  while IsOp('|') do begin Advance; ParseBitXor(b); a := pybitor_v(a, b); end;
  res := a;
end;

procedure ParseCompare(var res: Variant);
var a, b: Variant; c: Int64; ok: Boolean;
begin
  ParseBitOr(a);
  if not (IsOp('<') or IsOp('>') or IsOp('<=') or IsOp('>=')
          or IsOp('==') or IsOp('!=')) then
  begin res := a; Exit; end;
  { Python chains: a < b < c == (a<b) and (b<c). }
  ok := True;
  while IsOp('<') or IsOp('>') or IsOp('<=') or IsOp('>=')
        or IsOp('==') or IsOp('!=') do
  begin
    if IsOp('==') then begin Advance; ParseBitOr(b); ok := ok and pyeq_v(a, b); end
    else if IsOp('!=') then begin Advance; ParseBitOr(b); ok := ok and (not pyeq_v(a, b)); end
    else if IsOp('<') then begin Advance; ParseBitOr(b); c := pycmp_v(a, b); ok := ok and (c < 0); end
    else if IsOp('>') then begin Advance; ParseBitOr(b); c := pycmp_v(a, b); ok := ok and (c > 0); end
    else if IsOp('<=') then begin Advance; ParseBitOr(b); c := pycmp_v(a, b); ok := ok and (c <= 0); end
    else begin Advance; ParseBitOr(b); c := pycmp_v(a, b); ok := ok and (c >= 0); end;
    a := b;
  end;
  res := pyvar_of_bool(ok);
end;

procedure ParseNot(var res: Variant);
var t: Variant;
begin
  if IsKw('not') then
  begin Advance; ParseNot(t); res := pyvar_of_bool(not pyvar_to_bool(t)); Exit; end;
  ParseCompare(res);
end;

procedure ParseAnd(var res: Variant);
var a, b: Variant;
begin
  ParseNot(a);
  while IsKw('and') do
  begin
    Advance; ParseNot(b);
    { value semantics: a and b -> b if a truthy else a }
    if pyvar_to_bool(a) then a := b;
  end;
  res := a;
end;

procedure ParseOr(var res: Variant);
var a, b: Variant;
begin
  ParseAnd(a);
  while IsKw('or') do
  begin
    Advance; ParseAnd(b);
    if not pyvar_to_bool(a) then a := b;
  end;
  res := a;
end;

{ ternary — lowest precedence. `A if C else B`. M1 evaluates all three eagerly
  and selects (the corpus branches are side-effect-free); a documented deviation
  mirroring pyor_v/pyand_v. }
procedure ParseExpr(var res: Variant);
var a, b, cond: Variant;
begin
  ParseOr(a);
  if IsKw('if') then
  begin
    Advance;
    ParseOr(cond);
    if not IsKw('else') then EvalError('ternary missing else');
    Advance;
    ParseExpr(b);
    if pyvar_to_bool(cond) then res := a else res := b;
    Exit;
  end;
  res := a;
end;

{ ---- builtins ---- }

{ range(...) materialised into a TPyList, boxed as a VT_OBJECT variant. }
function pyrange_list(args: TPyList): Variant;
var lo, hi, step, i: Int64; n: Integer; r: TPyList; ro: PPyRec;
begin
  n := args.count;
  if n = 1 then begin lo := 0; hi := pyvar_to_int(args.at(0)); step := 1; end
  else if n = 2 then
    begin lo := pyvar_to_int(args.at(0)); hi := pyvar_to_int(args.at(1)); step := 1; end
  else
    begin lo := pyvar_to_int(args.at(0)); hi := pyvar_to_int(args.at(1));
          step := pyvar_to_int(args.at(2)); end;
  r := TPyList.Create;
  if step > 0 then
  begin i := lo; while i < hi do begin r.append(pyvar_of_int(i)); i := i + step; end; end
  else if step < 0 then
  begin i := lo; while i > hi do begin r.append(pyvar_of_int(i)); i := i + step; end; end;
  ro := PPyRec(@Result); ro^.VType := 7; ro^.Payload := Int64(Pointer(r));
end;

procedure CallBuiltin(const name: AnsiString; args: TPyList;
                      const endKw, sepKw: AnsiString;
                      haveEnd, haveSep: Boolean; var res: Variant);
var i, nargs: Integer; s, sep, endc: AnsiString; cand, e: Variant;
begin
  nargs := args.count;
  if name = 'int' then
  begin
    if nargs <> 1 then EvalError('int() expects 1 arg in M1');
    res := pyint_v(args.at(0)); Exit;
  end;
  if name = 'float' then
  begin
    if nargs <> 1 then EvalError('float() expects 1 arg');
    res := MakeFloat(pyvar_to_float(args.at(0))); Exit;
  end;
  if name = 'abs' then
  begin
    if nargs <> 1 then EvalError('abs() expects 1 arg');
    res := pyabs_v(args.at(0)); Exit;
  end;
  if name = 'bool' then
  begin
    if nargs <> 1 then EvalError('bool() expects 1 arg');
    res := pyvar_of_bool(pyvar_to_bool(args.at(0))); Exit;
  end;
  if name = 'len' then
  begin
    if nargs <> 1 then EvalError('len() expects 1 arg');
    res := pyvar_of_int(pylen_v(args.at(0))); Exit;
  end;
  if name = 'ord' then
  begin
    if nargs <> 1 then EvalError('ord() expects 1 arg');
    res := pyvar_of_int(pyord_v(args.at(0))); Exit;
  end;
  if name = 'chr' then
  begin
    if nargs <> 1 then EvalError('chr() expects 1 arg');
    res := MakeStr(pystr_ofchar(Chr(pyvar_to_int(args.at(0)) and $FF))); Exit;
  end;
  if name = 'str' then
  begin
    if nargs <> 1 then EvalError('str() expects 1 arg');
    res := MakeStr(pystr_of(args.at(0))); Exit;
  end;
  if name = 'hex' then
  begin
    if nargs <> 1 then EvalError('hex() expects 1 arg');
    res := MakeStr(hex(pyvar_to_int(args.at(0)))); Exit;
  end;
  if name = 'min' then
  begin
    if nargs < 1 then EvalError('min() needs args');
    cand := args.at(0);
    for i := 1 to nargs - 1 do
    begin e := args.at(i); if pycmp_v(e, cand) < 0 then cand := e; end;
    res := cand; Exit;
  end;
  if name = 'max' then
  begin
    if nargs < 1 then EvalError('max() needs args');
    cand := args.at(0);
    for i := 1 to nargs - 1 do
    begin e := args.at(i); if pycmp_v(e, cand) > 0 then cand := e; end;
    res := cand; Exit;
  end;
  if name = 'range' then
  begin
    { range(stop) | range(start,stop) | range(start,stop,step) -> a materialised
      TPyList of ints (correctness-first; a lazy iterator can come later). }
    res := pyrange_list(args);
    Exit;
  end;
  if name = 'print' then
  begin
    s := '';
    if haveSep then sep := sepKw else sep := ' ';
    if haveEnd then endc := endKw else endc := #10;
    for i := 0 to nargs - 1 do
    begin
      if i > 0 then s := s + sep;
      s := s + pystr_of(args.at(i));
    end;
    write(s); write(endc);
    res := MakeNone; Exit;
  end;
  EvalError('unknown call: ' + name + '()');
  res := MakeNone;
end;

function IsHostName(const name: AnsiString): Boolean;
begin
  IsHostName := (name = 'push') or (name = 'pop')
             or (name = 'fpush') or (name = 'fpop');
end;

procedure ParseCall(const callee: AnsiString; var res: Variant);
var
  args: TPyList;
  v, vmv: Variant;
  kwname, endKw, sepKw: AnsiString;
  haveEnd, haveSep: Boolean;
  vmobj: Pointer;
begin
  ExpectOp('(');
  args := TPyList.Create;
  haveEnd := False; haveSep := False;
  endKw := ''; sepKw := '';
  while not IsOp(')') do
  begin
    { keyword arg?  NAME '=' expr  (but not '==') }
    if (TkKind[Cur] = PK_NAME) and (TkKind[Cur+1] = PK_OP)
       and (TkText[Cur+1] = '=') then
    begin
      kwname := TkText[Cur];
      Advance; Advance;   { name '=' }
      ParseExpr(v);
      if kwname = 'end' then begin endKw := pystr_of(v); haveEnd := True; end
      else if kwname = 'sep' then begin sepKw := pystr_of(v); haveSep := True; end
      else if kwname = 'flush' then { ignore }
      else EvalError('unsupported keyword arg: ' + kwname);
    end
    else
    begin
      ParseExpr(v);
      args.append(v);
    end;
    if IsOp(',') then Advance
    else if not IsOp(')') then EvalError('expected , or ) in call');
  end;
  ExpectOp(')');

  { skipped branch: consume the call but do not dispatch (no side effects) }
  if not Executing then begin res := MakeNone; Exit; end;

  if IsHostName(callee) then
  begin
    if (EnvG = nil) or (EnvG.indexof('vm') < 0) then
      EvalError('host call ' + callee + ' but no "vm" in globals');
    vmv := EnvG.fetch('vm');
    vmobj := pyvarobj(vmv);
    PyHostCall(vmobj, callee, args, res);
    Exit;
  end;
  CallBuiltin(callee, args, endKw, sepKw, haveEnd, haveSep, res);
end;

{ positional-only `( expr, ... )` into `args` }
procedure ParseArgs(args: TPyList);
var v: Variant;
begin
  ExpectOp('(');
  while not IsOp(')') do
  begin
    ParseExpr(v);
    args.append(v);
    if IsOp(',') then Advance
    else if not IsOp(')') then EvalError('expected , or ) in method call');
  end;
  ExpectOp(')');
end;

{ recv.mname(args). Dispatches str / list / bytes / dict methods to pylib; any
  other VT_OBJECT receiver is treated as a reflected HOST object and routed
  through the trampoline (PyHostCall). Method coverage is the corpus subset;
  unsupported names error clearly. }
procedure ParseMethodCall(const recv: Variant; const mname: AnsiString;
                          var res: Variant);
var
  args: TPyList;
  o: TObject; li: TPyList; by: TPyBytes;
  s: AnsiString; b2: TPyBytes;
begin
  args := TPyList.Create;
  ParseArgs(args);
  if not Executing then begin res := MakeNone; Exit; end;

  { string methods }
  if PPyRec(@recv)^.VType = 6 then
  begin
    s := PAnsiString(@PPyRec(@recv)^.Payload)^;
    if mname = 'upper' then res := MakeStr(pystr_upper(s))
    else if mname = 'lower' then res := MakeStr(pystr_lower(s))
    else if mname = 'strip' then
    begin
      if args.count = 0 then res := MakeStr(pystr_strip(s))
      else res := MakeStr(pystr_strip_chars(s, pystr_of(args.at(0))));
    end
    else if mname = 'join' then
      res := MakeStr(pystr_join(s, TPyList(pyvarobj(args.at(0)))))
    else if mname = 'startswith' then
      res := pyvar_of_bool(pystr_startswith(s, pystr_of(args.at(0))))
    else if mname = 'endswith' then
      res := pyvar_of_bool(pystr_endswith(s, pystr_of(args.at(0))))
    else if mname = 'find' then
      res := pyvar_of_int(pystr_find(s, pystr_of(args.at(0))))
    else if mname = 'encode' then
    begin
      b2 := pystr_encode(s);
      PPyRec(@res)^.VType := 7; PPyRec(@res)^.Payload := Int64(Pointer(b2));
    end
    else
      EvalError('str method not supported: ' + mname);
    Exit;
  end;

  if PPyRec(@recv)^.VType = 7 then
  begin
    o := TObject(Pointer(PPyRec(@recv)^.Payload));
    if o is TPyList then
    begin
      li := TPyList(o);
      if mname = 'append' then begin li.append(args.at(0)); res := MakeNone; end
      else if mname = 'insert' then
        begin li.insert(pyvar_to_int(args.at(0)), args.at(1)); res := MakeNone; end
      else if mname = 'pop' then
      begin
        if args.count = 0 then res := li.pop
        else res := li.pop(pyvar_to_int(args.at(0)));
      end
      else if mname = 'clear' then begin li.clear; res := MakeNone; end
      else if mname = 'extend' then
        begin li.extend(TPyList(pyvarobj(args.at(0)))); res := MakeNone; end
      else
        EvalError('list method not supported: ' + mname);
      Exit;
    end;
    if o is TPyBytes then
    begin
      by := TPyBytes(o);
      if mname = 'append' then begin by.append(pyvar_to_int(args.at(0))); res := MakeNone; end
      else if mname = 'decode' then
      begin
        if args.count = 0 then res := MakeStr(by.decode('utf-8'))
        else res := MakeStr(by.decode(pystr_of(args.at(0))));
      end
      else if mname = 'extend' then
        begin by.extend(TPyBytes(pyvarobj(args.at(0)))); res := MakeNone; end
      else
        EvalError('bytes method not supported: ' + mname);
      Exit;
    end;
    { otherwise: a reflected host object (vm) — dispatch through the trampoline }
    PyHostCall(Pointer(PPyRec(@recv)^.Payload), mname, args, res);
    Exit;
  end;

  EvalError('cannot call method ' + mname + ' on this value');
end;

{ ---- statements ---- }

procedure SkipSeparators;
begin
  while IsOp(';') or (CurKind = PK_NL) do Advance;
end;

procedure ExecStatement; forward;

{ Execute (or, if `doEval` is False, merely skip) the suite that follows a `:`.
  A suite is either INLINE — simple statements to end of line — or a BLOCK:
  NEWLINE INDENT statement+ DEDENT. Skipping walks the same grammar with
  Executing off so the token cursor lands past the suite either way. }
procedure ExecSuite(doEval: Boolean);
var saved: Boolean;
begin
  saved := Executing;
  Executing := saved and doEval;
  if CurKind = PK_NL then
  begin
    { block form }
    while CurKind = PK_NL do Advance;
    if CurKind <> PK_INDENT then
    begin Executing := saved; EvalError('expected an indented block'); end;
    Advance;   { INDENT }
    while (CurKind <> PK_DEDENT) and (CurKind <> PK_EOF) do
    begin
      if BreakFlag then
      begin
        { unwinding a loop: fast-skip the rest of the block with eval off }
        Executing := False;
      end;
      ExecStatement;
      SkipSeparators;
    end;
    if CurKind = PK_DEDENT then Advance;
  end
  else
  begin
    { inline form: simple statements until newline / dedent / eof }
    while (CurKind <> PK_NL) and (CurKind <> PK_DEDENT) and (CurKind <> PK_EOF) do
    begin
      if BreakFlag then Executing := False;
      ExecStatement;
      while IsOp(';') do Advance;
    end;
  end;
  Executing := saved;
end;

procedure ExecIf;
var cond: Variant; done: Boolean;
begin
  Advance;   { if }
  ParseExpr(cond);
  ExpectOp(':');
  done := Executing and pyvar_to_bool(cond);
  ExecSuite(done);
  while IsKw('elif') do
  begin
    Advance;
    ParseExpr(cond);
    ExpectOp(':');
    if (not done) and Executing and pyvar_to_bool(cond) then
    begin ExecSuite(True); done := True; end
    else
      ExecSuite(False);
  end;
  if IsKw('else') then
  begin
    Advance; ExpectOp(':');
    ExecSuite(Executing and (not done));
  end;
end;

procedure ExecWhile;
var cond: Variant; condPos: Integer; guard: Int64;
begin
  Advance;   { while }
  condPos := Cur;
  guard := 0;
  while True do
  begin
    Cur := condPos;
    ParseExpr(cond);
    ExpectOp(':');
    if Executing and pyvar_to_bool(cond) then
    begin
      ExecSuite(True);
      if BreakFlag then begin BreakFlag := False; Break; end;
      guard := guard + 1;
      if guard > 100000000 then EvalError('while: iteration guard tripped');
    end
    else
    begin
      ExecSuite(False);   { skip body once to advance past it }
      Break;
    end;
  end;
end;

procedure ExecFor;
var
  varName: AnsiString;
  iter: Variant;
  lst: TPyList;
  bodyPos, i, n: Integer;
begin
  Advance;   { for }
  if CurKind <> PK_NAME then EvalError('for: expected a loop variable');
  varName := TkText[Cur]; Advance;
  if not IsKw('in') then EvalError('for: expected "in"');
  Advance;
  ParseExpr(iter);
  ExpectOp(':');
  bodyPos := Cur;
  if not Executing then begin ExecSuite(False); Exit; end;
  if PPyRec(@iter)^.VType <> 7 then
    EvalError('for: M1/M2 iterate over a list/range only');
  lst := TPyList(Pointer(PPyRec(@iter)^.Payload));
  n := lst.count;
  if n = 0 then begin ExecSuite(False); Exit; end;
  for i := 0 to n - 1 do
  begin
    LclSet(varName, lst.at(i));
    Cur := bodyPos;
    ExecSuite(True);
    if BreakFlag then begin BreakFlag := False; Exit; end;
  end;
  { after the last real iteration Cur is already past the suite }
end;

function IsAssignOp(const s: AnsiString): Boolean;
begin
  IsAssignOp := (s = '=') or (s = '+=') or (s = '-=') or (s = '*=')
    or (s = '//=') or (s = '%=') or (s = '&=') or (s = '|=') or (s = '^=')
    or (s = '<<=') or (s = '>>=');
end;

{ Token-only scan: does a NAME (.attr | [expr])* chain from Cur end at an assign
  op? Decides assignment vs expression statement without evaluating anything. }
function AssignmentAhead: Boolean;
var p, depth: Integer;
begin
  AssignmentAhead := False;
  p := Cur;
  if TkKind[p] <> PK_NAME then Exit;
  p := p + 1;
  while True do
  begin
    if (TkKind[p] = PK_OP) and (TkText[p] = '.') then
    begin
      p := p + 1;
      if TkKind[p] <> PK_NAME then Exit;
      p := p + 1;
    end
    else if (TkKind[p] = PK_OP) and (TkText[p] = '[') then
    begin
      depth := 1; p := p + 1;
      while (depth > 0) and (TkKind[p] <> PK_EOF) do
      begin
        if (TkKind[p] = PK_OP) and (TkText[p] = '[') then depth := depth + 1
        else if (TkKind[p] = PK_OP) and (TkText[p] = ']') then depth := depth - 1;
        p := p + 1;
      end;
    end
    else
      Break;
  end;
  AssignmentAhead := (TkKind[p] = PK_OP) and IsAssignOp(TkText[p]);
end;

{ Assignment to a local, an attribute (obj.field), or a subscript
  (container[index]) — plain and augmented. The receiver chain is walked and
  intermediate steps read normally; only the final step is the lvalue. }
procedure DoAssignment;
var
  base, aug, fld: AnsiString;
  recv, idx, rhs, cur, v, tcont, tindex: Variant;
  tkind: Integer;   { 0 local, 1 attribute, 2 subscript }
  tname: AnsiString;
  tobj: Pointer;
begin
  base := TkText[Cur]; Advance;
  tkind := 0; tname := base; tobj := nil;
  if IsOp('.') or IsOp('[') then
  begin
    EnvGet(base, recv);
    while True do
    begin
      if IsOp('.') then
      begin
        Advance;
        fld := TkText[Cur]; Advance;
        if (TkKind[Cur] = PK_OP) and IsAssignOp(TkText[Cur]) then
        begin tkind := 1; tobj := pyvarobj(recv); tname := fld; Break; end;
        if Executing then PyFieldGet(pyvarobj(recv), fld, recv) else recv := MakeNone;
      end
      else if IsOp('[') then
      begin
        Advance; ParseExpr(idx); ExpectOp(']');
        if (TkKind[Cur] = PK_OP) and IsAssignOp(TkText[Cur]) then
        begin tkind := 2; tcont := recv; tindex := idx; Break; end;
        if Executing then PySubscriptGet(recv, idx, recv) else recv := MakeNone;
      end
      else
        EvalError('invalid assignment target');
    end;
  end;

  aug := TkText[Cur]; Advance;
  ParseExpr(rhs);
  if not Executing then Exit;

  if aug = '=' then v := rhs
  else
  begin
    if tkind = 0 then EnvGet(tname, cur)
    else if tkind = 1 then PyFieldGet(tobj, tname, cur)
    else PySubscriptGet(tcont, tindex, cur);
    if aug = '+=' then v := pyadd_v(cur, rhs)
    else if aug = '-=' then v := pysub_v(cur, rhs)
    else if aug = '*=' then v := pymul_v(cur, rhs)
    else if aug = '//=' then v := pyfloordiv_v(cur, rhs)
    else if aug = '%=' then v := pymod_v(cur, rhs)
    else if aug = '&=' then v := pybitand_v(cur, rhs)
    else if aug = '|=' then v := pybitor_v(cur, rhs)
    else if aug = '^=' then v := pybitxor_v(cur, rhs)
    else if aug = '<<=' then v := pyshl_v(cur, rhs)
    else v := pyshr_v(cur, rhs);
  end;

  if tkind = 0 then LclSet(tname, v)
  else if tkind = 1 then PyFieldSet(tobj, tname, v)
  else PySubscriptSet(tcont, tindex, v);
end;

procedure ExecStatement;
var v: Variant;
begin
  StmtWasCompound := False;
  { compound statements (self-terminating at DEDENT). Set the flag AFTER the call
    returns — the nested statements inside the block reset it. }
  if IsKw('if') then begin ExecIf; StmtWasCompound := True; Exit; end;
  if IsKw('while') then begin ExecWhile; StmtWasCompound := True; Exit; end;
  if IsKw('for') then begin ExecFor; StmtWasCompound := True; Exit; end;
  if IsKw('break') then begin Advance; if Executing then BreakFlag := True; Exit; end;
  if IsKw('pass') then begin Advance; Exit; end;
  if IsKw('def') or IsKw('return') or IsKw('raise') or IsKw('del')
     or IsKw('import') or IsKw('continue') or IsKw('elif') or IsKw('else') then
    EvalError('statement "' + CurText + '" is not supported yet');

  if (TkKind[Cur] = PK_NAME) and AssignmentAhead then
  begin DoAssignment; Exit; end;

  { expression statement (e.g. push(x), pop()) — value discarded }
  ParseExpr(v);
end;

procedure EvalPyStmts(const src: AnsiString; g: TPyDict; l: TPyDict);
begin
  EnvG := g;
  { locals live in pyeval's own arrays (see LclSet); the `l` dict argument is
    accepted for API compatibility with Python's exec(src, g, l) but is not the
    backing store — uforth's block locals are function-internal and never read
    back by the host. }
  LclN := 0;
  Executing := True;
  BreakFlag := False;
  Tokenize(src);
  Cur := 0;
  SkipSeparators;
  while (CurKind <> PK_EOF) and (CurKind <> PK_DEDENT) do
  begin
    ExecStatement;
    if (not StmtWasCompound) and (CurKind <> PK_EOF) and (CurKind <> PK_DEDENT)
       and not (IsOp(';') or (CurKind = PK_NL)) then
      EvalError('expected end of statement, got "' + CurText + '"');
    SkipSeparators;
  end;
end;

end.
