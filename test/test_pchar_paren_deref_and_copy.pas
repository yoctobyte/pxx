program test_pchar_paren_deref_and_copy;
{ Two boundaries where a PChar was unrecognised, both found by re-running this
  ticket's acceptance cross product with new source shapes.

  `(qa[0])^` -- a PARENTHESISED index-then-deref -- lost the pointer shape that
  the identical `qa[0]^`, one character to the left, keeps. There were FOUR
  copies of the deref walk; the parenthesised tail was the small one, resolving
  the immediate pointee through NodePtrElem and stamping no remaining-depth and
  no ultimate base at all. So WriteLn printed the address, concat produced '',
  Length answered the pointer and `=` compared pointers. The walk is now one
  procedure (ResolveDerefShape) that both callers share, which also gave the
  parenthesised spelling the typed-cast arm it never had.

  `Copy(p, 2, 3)` over a PChar was refused outright -- "dynamic-array Copy needs
  a dynamic-array first argument" -- for EVERY PChar spelling at once: a var,
  `q^`, `q[0]`, an array element, a record field, a function result, a
  `const PChar` parameter, an `out` parameter. That spread is the tell: the
  BOUNDARY was unrecognised, not one shape. Fixed by normalising the operand at
  the Copy site, beside the Char promotion already there.

  Every expected line is fpc 3.2.2's own output. }
type
  PPC = ^PChar;
  PPPC = ^PPC;
  TR = record f: PChar; end;
var
  gpc: PChar;
function GetP: PChar; begin Result := gpc; end;
function Ident(const q: PChar): PChar; begin Result := q; end;
procedure SetOut(out o: PChar); begin o := gpc; end;
procedure Show(const t: AnsiString); begin WriteLn(t); end;
var
  base, s: AnsiString;
  p, p2: PChar;
  q: PPC;
  t: PPPC;
  qa: array[0..1] of PPC;
  qd: array of PPC;
  r: TR;
begin
  base := 'alpha';
  p := PChar(base);
  gpc := p;
  q := @p;
  t := @q;
  qa[0] := q; qa[1] := q;
  SetLength(qd, 2); qd[0] := q; qd[1] := q;
  r.f := p;

  { the parenthesised deref, every context the unparenthesised one covers }
  WriteLn('paren wr  : ', (qa[0])^);
  s := (qa[0])^;              WriteLn('paren asg : ', s);
  s := 'x' + (qa[0])^;        WriteLn('paren catL: ', s);
  s := (qa[0])^ + 'y';        WriteLn('paren catR: ', s);
  s := AnsiString((qa[1])^);  WriteLn('paren cast: ', s);
  WriteLn('paren len : ', Length((qa[0])^));
  WriteLn('paren eq  : ', ((qa[0])^) = 'alpha');
  WriteLn('paren ne  : ', ((qa[0])^) <> 'alpha');
  WriteLn('paren dyn : ', (qd[0])^);
  WriteLn('paren deep: ', (t^)^);
  WriteLn('paren arit: ', (p + 1)^);

  { Copy over every PChar spelling }
  WriteLn('copy var  : ', Copy(p, 2, 3));
  WriteLn('copy dref : ', Copy(q^, 2, 3));
  WriteLn('copy idx  : ', Copy(q[0], 2, 3));
  WriteLn('copy paren: ', Copy((qa[0])^, 2, 3));
  WriteLn('copy triple: ', Copy(t^^, 2, 3));
  WriteLn('copy fld  : ', Copy(r.f, 2, 3));
  WriteLn('copy call : ', Copy(GetP, 2, 3));
  WriteLn('copy const: ', Copy(Ident(p), 2, 3));
  SetOut(p2);
  WriteLn('copy out  : ', Copy(p2, 2, 3));
  WriteLn('copy arith: ', Copy(p + 1, 1, 2));
  Show(Copy(p, 3, 3));
end.
