program test_soft_keyword_length;
{ All 13 former hard-keyword intrinsics are soft keywords (lex as plain
  identifiers; ParseFactor / ParseStatementAST dispatch on the name) —
  bug-hard-keyword-intrinsics-block-identifier-use: Length, Ord, Chr, Low,
  High, Inc, Dec, Exit, Halt, Break, Continue, GetMem, FreeMem. FPC-parity
  pinned here: all are declarable as variable/param/field names; the
  intrinsic/statement forms are untouched where the name is not shadowed (a
  shadowing symbol disables the intrinsic in that scope, like FPC). }
type TE = (eA, eB, eC);
var
  okCount: Integer;
  s: string;
  a: array of Integer;
  f: array[0..4] of Integer;

procedure Chk(n: Integer; cond: Boolean);
begin
  if cond then begin writeln('ok ', n); okCount := okCount + 1; end
  else writeln('FAIL ', n);
end;

{ param named Length: legal, reads as a plain value inside }
function ParamShadow(Length: Integer): Integer;
begin ParamShadow := Length * 2; end;

{ local var named length: legal; shadows the intrinsic only in this scope }
function LocalShadow: Integer;
var length: Integer;
begin length := 21; LocalShadow := length + 21; end;

{ record field named Length }
type TBuf = record Length: Integer; end;

{ user function named Length shadows the intrinsic at its call sites }
function UserArea: Integer;
begin UserArea := 0; end;

type TPt = record x, y: Integer; end;
var r: TBuf;
var p: Pointer; q: ^Integer; r2: TPt;

{ ord/chr/low/high declarable and usable as plain locals }
function OrdChrLowHighVars: Integer;
var ord, chr, low, high: Integer;
begin
  ord := 1; chr := 2; low := 3; high := 4;
  OrdChrLowHighVars := ord + chr + low + high;
end;

{ the statement-context names as plain locals }
function StmtNamesAsVars: Integer;
var inc, dec, halt, break, continue, exit, getmem, freemem: Integer;
begin
  inc := 1; dec := 2; halt := 3; break := 4;
  continue := 5; exit := 6; getmem := 7; freemem := 8;
  StmtNamesAsVars := inc + dec + halt + break + continue + exit + getmem + freemem;
end;

{ Exit forms: bare and with a value }
function EarlyExit(x: Integer): Integer;
begin
  if x > 5 then Exit(99);
  EarlyExit := x;
end;

{ Break / Continue / Inc / Dec statement semantics }
function LoopSemantics: Integer;
var i, n: Integer;
begin
  n := 0;
  for i := 1 to 10 do
  begin
    if i = 3 then Continue;
    if i = 8 then Break;
    Inc(n);
  end;
  Inc(n, 10);
  Dec(n, 2);
  LoopSemantics := n;   { 6 counted + 10 - 2 = 14 }
end;

begin
  okCount := 0;
  Chk(1, Length('hello') = 5);            { literal fold }
  s := 'worlds';
  Chk(2, Length(s) = 6);                  { string lvalue }
  SetLength(a, 3);
  Chk(3, Length(a) = 3);                  { dyn array }
  Chk(4, Length(f) = 5);                  { static array fold }
  Chk(5, LENGTH('abc') = 3);              { any casing }
  Chk(6, ParamShadow(7) = 14);
  Chk(7, LocalShadow = 42);
  r.Length := 9;
  Chk(8, r.Length = 9);
  Chk(9, Length(s + '!') = 7);            { r-value (concat result) }
  Chk(10, OrdChrLowHighVars = 10);        { ord/chr/low/high as variables }
  Chk(11, (Ord('A') = 65) and (Chr(66) = 'B') and (Ord(eC) = 2));
  Chk(12, (Low(f) = 0) and (High(f) = 4) and (High(Byte) = 255));
  Chk(13, (Low(a) = 0) and (High(a) = 2));
  Chk(14, (Low(TE) = eA) and (High(TE) = eC));
  Chk(15, StmtNamesAsVars = 36);
  Chk(16, (EarlyExit(2) = 2) and (EarlyExit(9) = 99));
  Chk(17, LoopSemantics = 14);
  GetMem(p, 64);                          { statement form }
  q := GetMem(8);                         { function form }
  q^ := 77;
  Chk(18, q^ = 77);
  FreeMem(p);
  FreeMem(q, 8);                          { two-arg form }
  r2.x := 5; Inc(r2.x);                   { record-field lvalue }
  Chk(19, r2.x = 6);
  writeln('total ok ', okCount, ' / 19');
  Halt(0);                                { Halt itself, explicit success }
  writeln('unreachable after Halt');
end.
