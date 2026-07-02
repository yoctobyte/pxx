{ SPDX-License-Identifier: 0BSD }
program LispDemo;
{ A small Lisp: S-expression reader, environment-based evaluator with closures,
  core special forms (quote/if/define/lambda/let/begin) and integer builtins.
  Track B demo + deterministic oracle (integer core, byte-identical output).

  Values live in a flat CELL ARENA addressed by Integer handles (parallel global
  arrays), not records-with-pointer-fields -- robust and idiomatic for this RTL,
  same approach as the zlib/sat units. A value is a handle; its tag is cKind[h].

  Recursion (Eval/Read/Print) always calls with parentheses, as the dialect
  requires for self/forward calls. }

uses sysutils;

const
  { cell kinds }
  K_NIL   = 0;
  K_NUM   = 1;
  K_SYM   = 2;
  K_CONS  = 3;
  K_PRIM  = 4;
  K_CLO   = 5;
  { primitive opcodes }
  P_ADD=1; P_SUB=2; P_MUL=3; P_DIV=4; P_MOD=5;
  P_EQ=6; P_LT=7; P_GT=8; P_CONS=9; P_CAR=10; P_CDR=11;
  P_LIST=12; P_NULL=13; P_NOT=14; P_EQP=15;
  MAXCELLS = 400000;

var
  cKind: array of Integer;
  cA:    array of Integer;   { car / sym-id / prim-op / closure params }
  cB:    array of Integer;   { cdr / closure body }
  cC:    array of Integer;   { closure captured env }
  cNum:  array of Int64;     { NUM value }
  nCells: Integer;

  symNames: array of AnsiString;
  nSyms: Integer;

  gNil, gTrue: Integer;
  gEnv: Integer;             { top-level environment (assoc list) }

  { interned special-form symbol ids }
  sQuote, sIf, sDefine, sLambda, sLet, sBegin: Integer;

  src: AnsiString;           { reader input + cursor }
  pos: Integer;

  ok: Boolean;

{ ---------- arena ---------- }

function NewCell(kind: Integer): Integer;
begin
  cKind[nCells] := kind;
  cA[nCells] := 0; cB[nCells] := 0; cC[nCells] := 0; cNum[nCells] := 0;
  NewCell := nCells;
  nCells := nCells + 1;
end;

function MkNum(v: Int64): Integer;
var h: Integer;
begin
  h := NewCell(K_NUM);
  cNum[h] := v;
  MkNum := h;
end;

function InternSym(const name: AnsiString): Integer;
var i, h: Integer;
begin
  for i := 0 to nSyms - 1 do
    if symNames[i] = name then begin InternSym := i; Exit; end;
  symNames[nSyms] := name;
  InternSym := nSyms;
  nSyms := nSyms + 1;
end;

function MkSym(const name: AnsiString): Integer;
var h: Integer;
begin
  h := NewCell(K_SYM);
  cA[h] := InternSym(name);
  MkSym := h;
end;

function Cons(a, b: Integer): Integer;
var h: Integer;
begin
  h := NewCell(K_CONS);
  cA[h] := a;
  cB[h] := b;
  Cons := h;
end;

function Car(h: Integer): Integer;
begin
  if cKind[h] = K_CONS then Car := cA[h] else Car := gNil;
end;

function Cdr(h: Integer): Integer;
begin
  if cKind[h] = K_CONS then Cdr := cB[h] else Cdr := gNil;
end;

function MkPrim(op: Integer): Integer;
var h: Integer;
begin
  h := NewCell(K_PRIM);
  cA[h] := op;
  MkPrim := h;
end;

{ ---------- reader ---------- }

procedure SkipWS;
var c: Char;
begin
  while pos <= Length(src) do
  begin
    c := src[pos];
    if (c = ' ') or (c = #9) or (c = #10) or (c = #13) then pos := pos + 1
    else if c = ';' then
    begin
      while (pos <= Length(src)) and (src[pos] <> #10) do pos := pos + 1;
    end
    else Break;
  end;
end;

function ReadExpr: Integer; forward;

function ReadList: Integer;
var head, tail, node, e: Integer;
begin
  head := gNil; tail := gNil;
  while True do
  begin
    SkipWS;
    if pos > Length(src) then Break;
    if src[pos] = ')' then begin pos := pos + 1; Break; end;
    e := ReadExpr();
    node := Cons(e, gNil);
    if head = gNil then begin head := node; tail := node; end
    else begin cB[tail] := node; tail := node; end;
  end;
  ReadList := head;
end;

function ReadAtom: Integer;
var start: Integer; tok: AnsiString; c: Char; neg, allDigit: Boolean; i: Integer; v: Int64;
begin
  start := pos;
  while pos <= Length(src) do
  begin
    c := src[pos];
    if (c = ' ') or (c = #9) or (c = #10) or (c = #13) or (c = '(') or (c = ')') then Break;
    pos := pos + 1;
  end;
  tok := Copy(src, start, pos - start);

  { integer? optional leading - }
  allDigit := Length(tok) > 0;
  neg := False; i := 1;
  if (Length(tok) >= 1) and (tok[1] = '-') then
  begin
    if Length(tok) = 1 then allDigit := False else begin neg := True; i := 2; end;
  end;
  while (i <= Length(tok)) and allDigit do
  begin
    if (tok[i] < '0') or (tok[i] > '9') then allDigit := False;
    i := i + 1;
  end;

  if allDigit then
  begin
    v := 0;
    i := 1; if neg then i := 2;
    while i <= Length(tok) do begin v := v * 10 + (Ord(tok[i]) - Ord('0')); i := i + 1; end;
    if neg then v := -v;
    ReadAtom := MkNum(v);
  end
  else
    ReadAtom := MkSym(tok);
end;

function ReadExpr: Integer;
begin
  SkipWS;
  if pos > Length(src) then begin ReadExpr := gNil; Exit; end;
  if src[pos] = '(' then
  begin
    pos := pos + 1;
    ReadExpr := ReadList();
  end
  else if src[pos] = '''' then
  begin
    pos := pos + 1;
    ReadExpr := Cons(MkSym('quote'), Cons(ReadExpr(), gNil));
  end
  else
    ReadExpr := ReadAtom();
end;

{ ---------- environment (assoc list of (sym-id . value)) ---------- }

function EnvLookup(env, symId: Integer): Integer;
var p, pair: Integer;
begin
  p := env;
  while cKind[p] = K_CONS do
  begin
    pair := cA[p];
    if cA[pair] = symId then begin EnvLookup := cB[pair]; Exit; end;
    p := cB[p];
  end;
  EnvLookup := -1;          { not found }
end;

function EnvBind(env, symId, val: Integer): Integer;
var pair: Integer;
begin
  pair := NewCell(K_CONS);
  cA[pair] := symId; cB[pair] := val;
  EnvBind := Cons(pair, env);
end;

{ ---------- evaluator ---------- }

function Eval(expr, env: Integer): Integer; forward;

function EvalArgs(list, env: Integer): Integer;
var head, tail, node, v: Integer;
begin
  head := gNil; tail := gNil;
  while cKind[list] = K_CONS do
  begin
    v := Eval(cA[list], env);
    node := Cons(v, gNil);
    if head = gNil then begin head := node; tail := node; end
    else begin cB[tail] := node; tail := node; end;
    list := cB[list];
  end;
  EvalArgs := head;
end;

function ApplyPrim(op, args: Integer): Integer;
var a, b: Integer; acc: Int64;
begin
  a := Car(args);
  b := Car(Cdr(args));
  case op of
    P_ADD: ApplyPrim := MkNum(cNum[a] + cNum[b]);
    P_SUB: ApplyPrim := MkNum(cNum[a] - cNum[b]);
    P_MUL: ApplyPrim := MkNum(cNum[a] * cNum[b]);
    P_DIV: ApplyPrim := MkNum(cNum[a] div cNum[b]);
    P_MOD: ApplyPrim := MkNum(cNum[a] mod cNum[b]);
    P_EQ:  if cNum[a] = cNum[b] then ApplyPrim := gTrue else ApplyPrim := gNil;
    P_LT:  if cNum[a] < cNum[b] then ApplyPrim := gTrue else ApplyPrim := gNil;
    P_GT:  if cNum[a] > cNum[b] then ApplyPrim := gTrue else ApplyPrim := gNil;
    P_CONS: ApplyPrim := Cons(a, b);
    P_CAR:  ApplyPrim := Car(a);
    P_CDR:  ApplyPrim := Cdr(a);
    P_LIST: ApplyPrim := args;
    P_NULL: if cKind[a] = K_NIL then ApplyPrim := gTrue else ApplyPrim := gNil;
    P_NOT:  if cKind[a] = K_NIL then ApplyPrim := gTrue else ApplyPrim := gNil;
    P_EQP:  if a = b then ApplyPrim := gTrue
            else if (cKind[a] = K_NUM) and (cKind[b] = K_NUM) and (cNum[a] = cNum[b]) then ApplyPrim := gTrue
            else if (cKind[a] = K_SYM) and (cKind[b] = K_SYM) and (cA[a] = cA[b]) then ApplyPrim := gTrue
            else ApplyPrim := gNil;
  else
    ApplyPrim := gNil;
  end;
end;

function Apply(fn, args: Integer): Integer;
var env, params, p, a: Integer;
begin
  if cKind[fn] = K_PRIM then
  begin
    Apply := ApplyPrim(cA[fn], args);
    Exit;
  end;
  if cKind[fn] = K_CLO then
  begin
    env := cC[fn];
    params := cA[fn];
    p := params; a := args;
    while (cKind[p] = K_CONS) and (cKind[a] = K_CONS) do
    begin
      env := EnvBind(env, cA[cA[p]], cA[a]);   { param sym-id -> arg value }
      p := cB[p]; a := cB[a];
    end;
    Apply := Eval(cB[fn], env);                { closure body }
    Exit;
  end;
  Apply := gNil;
end;

function Eval(expr, env: Integer): Integer;
var head, hid, t, e, args, fn, v, body, bindings, b, nenv: Integer;
begin
  if cKind[expr] = K_NUM then begin Eval := expr; Exit; end;
  if cKind[expr] = K_NIL then begin Eval := expr; Exit; end;
  if cKind[expr] = K_SYM then
  begin
    v := EnvLookup(env, cA[expr]);
    if v < 0 then v := EnvLookup(gEnv, cA[expr]);   { globals (incl. recursive
                                                      defines) always visible }
    if v < 0 then Eval := gNil else Eval := v;
    Exit;
  end;
  if cKind[expr] <> K_CONS then begin Eval := expr; Exit; end;

  head := cA[expr];
  if cKind[head] = K_SYM then
  begin
    hid := cA[head];
    if hid = sQuote then begin Eval := Car(Cdr(expr)); Exit; end;
    if hid = sIf then
    begin
      t := Eval(Car(Cdr(expr)), env);
      if cKind[t] <> K_NIL then Eval := Eval(Car(Cdr(Cdr(expr))), env)
      else Eval := Eval(Car(Cdr(Cdr(Cdr(expr)))), env);
      Exit;
    end;
    if hid = sLambda then
    begin
      e := NewCell(K_CLO);
      cA[e] := Car(Cdr(expr));          { params }
      cB[e] := Car(Cdr(Cdr(expr)));     { body }
      cC[e] := env;                     { captured env }
      Eval := e;
      Exit;
    end;
    if hid = sDefine then
    begin
      v := Eval(Car(Cdr(Cdr(expr))), env);
      gEnv := EnvBind(gEnv, cA[Car(Cdr(expr))], v);   { define mutates top env }
      Eval := Car(Cdr(expr));
      Exit;
    end;
    if hid = sLet then
    begin
      bindings := Car(Cdr(expr));
      nenv := env;
      b := bindings;
      while cKind[b] = K_CONS do
      begin
        v := Eval(Car(Cdr(cA[b])), env);
        nenv := EnvBind(nenv, cA[Car(cA[b])], v);
        b := cB[b];
      end;
      Eval := Eval(Car(Cdr(Cdr(expr))), nenv);
      Exit;
    end;
    if hid = sBegin then
    begin
      t := cB[expr]; v := gNil;
      while cKind[t] = K_CONS do begin v := Eval(cA[t], env); t := cB[t]; end;
      Eval := v;
      Exit;
    end;
  end;

  fn := Eval(head, env);
  args := EvalArgs(cB[expr], env);
  Eval := Apply(fn, args);
end;

{ ---------- printer ---------- }

function PrintVal(h: Integer): AnsiString; forward;

function PrintList(h: Integer): AnsiString;
var s: AnsiString; first: Boolean;
begin
  s := '(';
  first := True;
  while cKind[h] = K_CONS do
  begin
    if not first then s := s + ' ';
    s := s + PrintVal(cA[h]);
    first := False;
    h := cB[h];
  end;
  if cKind[h] <> K_NIL then s := s + ' . ' + PrintVal(h);
  PrintList := s + ')';
end;

function PrintVal(h: Integer): AnsiString;
begin
  case cKind[h] of
    K_NIL:  PrintVal := '()';
    K_NUM:  PrintVal := IntToStr(cNum[h]);
    K_SYM:  PrintVal := symNames[cA[h]];
    K_CONS: PrintVal := PrintList(h);
    K_PRIM: PrintVal := '<prim>';
    K_CLO:  PrintVal := '<closure>';
  else
    PrintVal := '<?>';
  end;
end;

{ ---------- setup + oracle ---------- }

procedure DefPrim(const name: AnsiString; op: Integer);
begin
  gEnv := EnvBind(gEnv, InternSym(name), MkPrim(op));
end;

function EvalString(const s: AnsiString): AnsiString;
var e, v, last: Integer;
begin
  src := s; pos := 1;
  last := gNil;
  while True do
  begin
    SkipWS;
    if pos > Length(src) then Break;
    e := ReadExpr();
    last := Eval(e, gEnv);
  end;
  EvalString := PrintVal(last);
end;

procedure Run(const name, prog, want: AnsiString);
var got: AnsiString;
begin
  got := EvalString(prog);
  if got = want then writeln('  ok   ', name, ' => ', got)
  else begin ok := False; writeln('  FAIL ', name, ' => ', got, '  want ', want); end;
end;

begin
  SetLength(cKind, MAXCELLS); SetLength(cA, MAXCELLS); SetLength(cB, MAXCELLS);
  SetLength(cC, MAXCELLS); SetLength(cNum, MAXCELLS);
  SetLength(symNames, 4096);
  nCells := 0; nSyms := 0;

  gNil := NewCell(K_NIL);
  gTrue := MkSym('t');
  gEnv := gNil;

  sQuote  := InternSym('quote');
  sIf     := InternSym('if');
  sDefine := InternSym('define');
  sLambda := InternSym('lambda');
  sLet    := InternSym('let');
  sBegin  := InternSym('begin');

  DefPrim('+', P_ADD); DefPrim('-', P_SUB); DefPrim('*', P_MUL);
  DefPrim('/', P_DIV); DefPrim('mod', P_MOD);
  DefPrim('=', P_EQ);  DefPrim('<', P_LT);  DefPrim('>', P_GT);
  DefPrim('cons', P_CONS); DefPrim('car', P_CAR); DefPrim('cdr', P_CDR);
  DefPrim('list', P_LIST); DefPrim('null?', P_NULL); DefPrim('not', P_NOT);
  DefPrim('eq?', P_EQP);

  ok := True;

  writeln('-- arithmetic / core --');
  Run('add',      '(+ 1 2)', '3');
  Run('nested',   '(+ (* 2 3) (- 10 4))', '12');
  Run('compare',  '(if (< 3 5) (quote yes) (quote no))', 'yes');
  Run('quote',    '(quote (a b c))', '(a b c)');
  Run('list',     '(list 1 2 3)', '(1 2 3)');
  Run('cons',     '(cons 1 (cons 2 (quote ())))', '(1 2)');
  Run('car/cdr',  '(car (cdr (list 10 20 30)))', '20');

  writeln('-- define / lambda / closures --');
  Run('define',   '(define x 42) x', '42');
  Run('lambda',   '((lambda (n) (* n n)) 9)', '81');
  Run('let',      '(let ((a 3) (b 4)) (+ (* a a) (* b b)))', '25');
  Run('factorial',
    '(define fact (lambda (n) (if (< n 2) 1 (* n (fact (- n 1)))))) (fact 6)',
    '720');
  Run('fib',
    '(define fib (lambda (n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))) (fib 10)',
    '55');
  { closure captures state }
  Run('counter-adder',
    '(define adder (lambda (k) (lambda (x) (+ x k)))) (define add5 (adder 5)) (add5 100)',
    '105');
  { recursive list length }
  Run('length',
    '(define len (lambda (xs) (if (null? xs) 0 (+ 1 (len (cdr xs)))))) (len (list 1 2 3 4))',
    '4');
  { higher-order map (function passed as value) }
  Run('map',
    '(define map (lambda (f xs) (if (null? xs) (quote ()) (cons (f (car xs)) (map f (cdr xs))))))'
    + ' (map (lambda (x) (* x x)) (list 1 2 3 4))',
    '(1 4 9 16)');

  writeln;
  writeln('cells used: ', nCells);
  if ok then writeln('ALL OK') else writeln('FAILURES');
end.
