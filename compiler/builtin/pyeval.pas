{ pyeval — a real exec()/eval() for the Python subset uforth's PYTHON-bodied
  words are written in (feature-lib-pyexec, engine 1: the reflective
  tree-walker). Correctness reference; a JIT drops in later over the same
  grammar.

  MILESTONE 1 (this unit's initial scope): the 60 "pure-stack" corpus blocks —
  the ones that touch only push/pop/fpush/fpop and NO other vm.* member. That is
  exactly the set of PYTHON-bodied stdlib words (SWAP, OVER, ROT, /, MOD, bit
  ops, ternary min/max, …) that SEGFAULT today because pyexec is a stub.

  M1 grammar: a sequence of SIMPLE statements separated by `;` or newline —
  assignment, augmented assignment, and expression statements. Full expression
  grammar: ternary, boolean and/or/not, comparisons, |^& bit ops, <<>> shifts,
  +-*/ // %, unary -/+/~, calls, int/float/hex literals, names, True/False/None.
  Compound blocks (if/while/for/def with indentation), attribute access, and
  subscripts are M1-rest / M2 / M3 — this unit rejects them with a clear error
  rather than misbehaving.

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
  PK_EOF   = 0;
  PK_NAME  = 1;
  PK_INT   = 2;
  PK_FLOAT = 3;
  PK_STR   = 4;
  PK_OP    = 5;
  PK_NL    = 6;

type
  PPyRec = ^TPyRec;
  TPyRec = record
    VType:   Int64;
    Payload: Int64;
  end;

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

  EnvG, EnvL: TPyDict;

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
begin
  Src := s; SLen := Length(s); Pos := 1; TkN := 0;
  while Pos <= SLen do
  begin
    c := Src[Pos];
    { whitespace (not newline) }
    if (c = ' ') or (c = #9) or (c = #13) then
    begin
      Pos := Pos + 1;
      continue;
    end;
    if c = #10 then
    begin
      AddTok(PK_NL, '', 0, 0);
      Pos := Pos + 1;
      continue;
    end;
    { comment }
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

procedure EnvGet(const name: AnsiString; var res: Variant);
begin
  if (EnvL <> nil) and (EnvL.indexof(name) >= 0) then
    res := EnvL.fetch(name)
  else if (EnvG <> nil) and (EnvG.indexof(name) >= 0) then
    res := EnvG.fetch(name)
  else
  begin
    EvalError('name not defined: ' + name);
    res := MakeNone;
  end;
end;

procedure ParseExpr(var res: Variant); forward;   { conditional/ternary — lowest }
procedure ParseCall(const callee: AnsiString; var res: Variant); forward;

procedure ParsePrimary(var res: Variant);
var name: AnsiString;
begin
  case TkKind[Cur] of
    PK_INT:
      begin res := pyvar_of_int(TkInt[Cur]); Advance; Exit; end;
    PK_FLOAT:
      begin res := MakeFloat(TkFloat[Cur]); Advance; Exit; end;
    PK_STR:
      begin res := MakeStr(TkText[Cur]); Advance; Exit; end;
    PK_NAME:
      begin
        name := TkText[Cur];
        if name = 'True' then begin Advance; res := pyvar_of_bool(True); Exit; end;
        if name = 'False' then begin Advance; res := pyvar_of_bool(False); Exit; end;
        if name = 'None' then begin Advance; res := MakeNone; Exit; end;
        Advance;
        if IsOp('(') then begin ParseCall(name, res); Exit; end;
        if IsOp('.') then
          EvalError('attribute access (' + name + '.x) is M2/M3, not M1');
        if IsOp('[') then
          EvalError('subscripting is M2, not M1');
        EnvGet(name, res);
        Exit;
      end;
  end;
  if IsOp('(') then
  begin
    Advance;
    ParseExpr(res);
    ExpectOp(')');
    Exit;
  end;
  EvalError('unexpected token in expression: "' + TkText[Cur] + '"');
  res := MakeNone;
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

{ ---- statements ---- }

procedure SkipSeparators;
begin
  while IsOp(';') or (CurKind = PK_NL) do Advance;
end;

procedure ParseStatement;
var
  target, aug: AnsiString;
  rhs, cur, v: Variant;
begin
  { assignment / augassign?  NAME (=|op=) ...  — lookahead. }
  if (TkKind[Cur] = PK_NAME) and (TkKind[Cur+1] = PK_OP) then
  begin
    target := TkText[Cur];
    aug := TkText[Cur+1];
    if aug = '=' then
    begin
      Advance; Advance;
      ParseExpr(rhs);
      EnvL.store(target, rhs);
      Exit;
    end;
    if (aug = '+=') or (aug = '-=') or (aug = '*=') or (aug = '//=')
       or (aug = '%=') or (aug = '&=') or (aug = '|=') or (aug = '^=')
       or (aug = '<<=') or (aug = '>>=') then
    begin
      Advance; Advance;
      ParseExpr(rhs);
      EnvGet(target, cur);
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
      EnvL.store(target, v);
      Exit;
    end;
  end;
  { compound-statement keywords we do not support in M1 }
  if IsKw('if') or IsKw('elif') or IsKw('else') or IsKw('while')
     or IsKw('for') or IsKw('def') or IsKw('return') or IsKw('raise')
     or IsKw('del') or IsKw('import') or IsKw('pass') or IsKw('break')
     or IsKw('continue') then
    EvalError('statement "' + CurText +
              '" is not supported in M1 (pure-stack subset only)');
  { expression statement (e.g. push(x), pop()) — value discarded }
  ParseExpr(v);
end;

procedure EvalPyStmts(const src: AnsiString; g: TPyDict; l: TPyDict);
begin
  EnvG := g;
  EnvL := l;
  if EnvL = nil then EnvL := g;
  Tokenize(src);
  Cur := 0;
  SkipSeparators;
  while CurKind <> PK_EOF do
  begin
    ParseStatement;
    if (CurKind <> PK_EOF) and not (IsOp(';') or (CurKind = PK_NL)) then
      EvalError('expected end of statement, got "' + CurText + '"');
    SkipSeparators;
  end;
end;

end.
