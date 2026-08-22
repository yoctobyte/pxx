program test_pointer_difference_is_a_number;
{ `p - q` over two typed pointers is a NUMBER of elements, not a pointer.
  tyPointer is reported as ordinal by TypeIsOrdinal, so the parser matched the
  pointer-ARITHMETIC arm and typed the result node tyPointer — invisible while
  the value was assigned to an integer first, fatal when it was not:
  `Writeln(pc - pc0)` on a ^Char printed the difference AS A STRING and
  segfaulted dereferencing address 3, while `n := pc - pc0; Writeln(n)` printed
  3. The IR lowering had typed it tyNativeInt all along. Every row below is
  checked against `fpc -Mobjfpc`. }

type
  TPI = ^Integer;
  TPB = ^Byte;
  TPC = ^Char;
  TPQ = ^Int64;
  TRec = record a, b, c: Integer; end;
  TPR = ^TRec;

var
  fails: Integer;

procedure Chk(const what: AnsiString; got, want: Int64);
begin
  if got = want then Writeln(what, ' ok')
  else begin Writeln(what, ' FAIL got=', got, ' want=', want); Inc(fails); end;
end;

var
  ai: array[0..7] of Integer;
  ab: array[0..7] of Byte;
  ac: array[0..7] of Char;
  aq: array[0..7] of Int64;
  ar: array[0..7] of TRec;
  pi, pi0: TPI;
  pb, pb0: TPB;
  pc, pc0: TPC;
  pq, pq0: TPQ;
  pr, pr0: TPR;
  n: PtrInt;

begin
  fails := 0;

  pi0 := @ai[0]; pi := @ai[3];
  pb0 := @ab[0]; pb := @ab[3];
  pc0 := @ac[0]; pc := @ac[3];
  pq0 := @aq[0]; pq := @aq[3];
  pr0 := @ar[0]; pr := @ar[3];

  { through a variable — this always worked }
  n := pi - pi0; Chk('var.int',  n, 3);
  n := pb - pb0; Chk('var.byte', n, 3);
  n := pc - pc0; Chk('var.char', n, 3);
  n := pq - pq0; Chk('var.i64',  n, 3);
  n := pr - pr0; Chk('var.rec',  n, 3);

  { directly in an expression — ^Char and ^Byte segfaulted here }
  Chk('dir.int',  pi - pi0, 3);
  Chk('dir.byte', pb - pb0, 3);
  Chk('dir.char', pc - pc0, 3);
  Chk('dir.i64',  pq - pq0, 3);
  Chk('dir.rec',  pr - pr0, 3);

  { the difference is a number, so it composes like one }
  Chk('arith',    (pi - pi0) * 2 + 1, 7);
  Chk('cmp',      Ord((pc - pc0) > 2), 1);
  Chk('zero',     pi0 - pi0,           0);
  Chk('negative', pi0 - pi,           -3);

  { and pointer arithmetic itself is untouched }
  pi := pi0 + 5;
  Chk('plus',     pi - pi0, 5);
  Inc(pi, -2);
  Chk('incdec',   pi - pi0, 3);
  pc := pc0 + 4;
  Chk('plus.char', pc - pc0, 4);

  if fails = 0 then Writeln('ALL OK') else Writeln('FAILURES: ', fails);
end.
