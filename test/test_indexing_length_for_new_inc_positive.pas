program test_indexing_length_for_new_inc_positive;
{ The other side of test_scalar_misuse_is_refused_fail: every LEGAL spelling of
  the five constructs that test refuses. Five guards were added at once, and a
  guard that is one shape too wide is a compiler that rejects valid Pascal --
  which is worse than the laxness it replaced. So each guard gets its whole
  legal surface here, and .expected IS fpc 3.2.2's own output on this source.
  bug-p-ten-constructs-fpc-rejects-are-accepted-and-silently-wrong }
type
  TE = (eA, eB, eC);
  TR = record arr: array[0..3] of Integer; end;
  PRec = ^TRec;
  TRec = record a: Integer; end;
  TCls = class
    n: Integer;
    procedure Show;
  end;

procedure TCls.Show; begin WriteLn(n); end;
procedure ShowOpenArray(const a: array of Integer); begin WriteLn('oa    : ', Length(a)); end;

var
  i, j: Integer; c: Char; b: Boolean; e: TE; q: Int64; w: Word; sub: 1..9;
  s: AnsiString; fs: string[10]; ca: array[0..7] of Char;
  sa: array[0..3] of Integer; da: array of Integer;
  jag: array of array of Integer; m: array[0..2, 0..4] of Integer;
  p: PChar; pi: ^Integer; pr: PRec; r: TR;
  sl: array of AnsiString; str: AnsiString;
  wr: TRec; wo: TCls;
begin
  { counted for over every ordinal kind, and for-in }
  Write('for   : ');
  for i := 1 to 2 do Write(i);
  for c := 'a' to 'c' do Write(c);
  for b := False to True do Write(b:1);
  for e := eA to eC do Write(Ord(e));
  for q := 1 to 2 do Write(q);
  for w := 1 to 2 do Write(w);
  for sub := 1 to 2 do Write(sub);
  for i := 3 downto 1 do Write(i);
  SetLength(sl, 2); sl[0] := 'x'; sl[1] := 'y';
  for str in sl do Write(str);
  for c in 'hi' do Write(c);
  WriteLn;

  { indexing every indexable shape }
  s := 'hello'; fs := 'world'; ca := 'abc';
  sa[1] := 7; SetLength(da, 3); da[1] := 8;
  SetLength(jag, 2); SetLength(jag[0], 2); jag[0][1] := 9;
  m[1, 2] := 5; p := PChar(s); i := 3; pi := @i;
  WriteLn('index : ', s[2], fs[1], ca[1], sa[1], da[1], jag[0][1], jag[0, 1],
          m[1, 2], m[1][2], p[1], pi[0]);

  { Length over every measurable shape }
  WriteLn('length: ', Length(s), ' ', Length(fs), ' ', Length(c), ' ',
          Length(ca), ' ', Length(sa), ' ', Length(da), ' ', Length(p), ' ',
          Length(r.arr), ' ', Length(m), ' ', Length('lit'), ' ', Length(''));
  ShowOpenArray(sa);

  { New/Dispose over a typed pointer and a record pointer }
  New(pr); pr^.a := 7; Write('new   : ', pr^.a); Dispose(pr);
  New(pi); pi^ := 9; WriteLn(' ', pi^); Dispose(pi);

  { `with` over a record and a class, and ordering over the kinds that DO order.
    Record equality is not exercised here -- FPC does not overload `=` on a bare
    record either -- but it is precisely why only the ORDERING operators are
    refused for a record operand: a method-pointer compare is a legitimate
    record `=` in this dialect and must keep working. }
  wr.a := 41;
  with wr do WriteLn('with  : ', a);
  wo := TCls.Create; wo.n := 7;
  with wo do WriteLn('withc : ', n);
  WriteLn('order : ', 1 < 2, ' ', 'a' < 'b', ' ', s < 'z', ' ', eA < eB);

  { Inc/Dec over ordinals and a pointer. NOT a float: `Inc(d)` is accepted here
    (deliberate laxness -- it computes d + 1 and damages nothing) but FPC
    rejects it with "Ordinal expression expected", so it cannot appear in a test
    whose .expected is FPC's own output. It is asserted nowhere and refused
    nowhere, which is exactly its status. }
  i := 1; Inc(i); Inc(i, 5); Dec(i);
  c := 'a'; Inc(c);
  q := 10; Inc(q, 3);
  e := eA; Inc(e);
  p := PChar(s); Inc(p, 2);
  WriteLn('inc   : ', i, ' ', c, ' ', q, ' ', Ord(e), ' ', p^);
end.
