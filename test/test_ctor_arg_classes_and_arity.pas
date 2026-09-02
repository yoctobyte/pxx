{ A constructor's arguments ACROSS THE FOUR-REGISTER BOUNDARY.

  arm32 refused any constructor of more than four parameter words outright --
  Self counts as one, so `Create(a,b,c,d)` was already over. It was the only
  target that did; x86-64, i386, aarch64 and riscv32 all answered. The refusal
  was in the class-instantiation arm of IR_CALL, which dropped the whole
  argument block BEFORE the call and so had nowhere to put words 4..n-1 -- the
  direct, virtual and indirect ladders in that same file had all learned to keep
  the overflow on the stack across the call.

  THE POINT OF THIS FILE IS THE BOUNDARY, not the failure. Three and four words
  worked before and must still work: a fix that only satisfies the case that
  used to be refused cannot tell a repair from a convention change. The rows run
  from one word up to nine.
  bug-a-arm32-refuses-a-constructor-with-more-than-four-parameter-words }
program test_arm32_wide_constructor;

type
  TC2 = class
    v: Integer;
    constructor Create(a, b: Integer);              { 3 words with Self }
  end;
  TC3 = class
    v: Integer;
    constructor Create(a, b, c: Integer);           { 4 words -- the old limit }
  end;
  TC4 = class
    v: Integer;
    constructor Create(a, b, c, d: Integer);        { 5 -- first one refused }
  end;
  TC8 = class
    v: Integer;
    constructor Create(a, b, c, d, e, f, g, h: Integer);   { 9 words }
  end;
  TC64 = class
    v: Int64;
    constructor Create(a: Int64; b, c, d, e: Integer);
  end;
  TRec8 = record x, y: Integer; end;
  TCRec = class
    v: Integer;
    constructor Create(a: Integer; r: TRec8; b: Integer);
  end;
  TCDbl = class
    v: Integer;
    constructor Create(a: Integer; d: Double; b: Integer);
  end;

constructor TC2.Create(a, b: Integer);
begin v := a * 10 + b; end;

constructor TC3.Create(a, b, c: Integer);
begin v := (a * 10 + b) * 10 + c; end;

constructor TC4.Create(a, b, c, d: Integer);
begin v := ((a * 10 + b) * 10 + c) * 10 + d; end;

constructor TC8.Create(a, b, c, d, e, f, g, h: Integer);
begin v := ((((((a * 10 + b) * 10 + c) * 10 + d) * 10 + e) * 10 + f) * 10 + g) * 10 + h; end;

{ An Int64 first parameter, so the words and the ARGUMENTS stop being the same
  count: five arguments, six parameter words. A limit expressed in words has to
  be tested with something that makes the two differ. }
constructor TC64.Create(a: Int64; b, c, d, e: Integer);
begin v := a + b * 1000 + c * 100 + d * 10 + e; end;

{ The other two multi-word classes, for the same reason the Int64 row exists: a
  ladder that pushes one word per ARGUMENT is wrong for every one of them, and
  which ones a backend gets right is not guessable from which ones it declares. }
constructor TCRec.Create(a: Integer; r: TRec8; b: Integer);
begin v := a * 100000 + r.x * 1000 + r.y * 10 + b; end;

constructor TCDbl.Create(a: Integer; d: Double; b: Integer);
begin v := a * 100000 + Trunc(d * 100) * 10 + b; end;

var
  fails: Integer;

procedure Check(got, want: Int64; const what: AnsiString);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ': got ', got, ' want ', want);
    Inc(fails);
  end;
end;

var
  c2: TC2; c3: TC3; c4: TC4; c8: TC8; c64: TC64; cr: TCRec; cd: TCDbl;
  r8: TRec8;
begin
  fails := 0;
  c2 := TC2.Create(1, 2);                        Check(c2.v, 12, 'two args (three words)');
  c3 := TC3.Create(1, 2, 3);                     Check(c3.v, 123, 'three args (four words -- the old limit)');
  c4 := TC4.Create(1, 2, 3, 4);                  Check(c4.v, 1234, 'four args (five words -- first one refused)');
  c8 := TC8.Create(1, 2, 3, 4, 5, 6, 7, 8);      Check(c8.v, 12345678, 'eight args (nine words)');
  c64 := TC64.Create(70000, 1, 2, 3, 4);         Check(c64.v, 71234, 'Int64 first arg (five args, six words)');
  r8.x := 2; r8.y := 3;
  cr := TCRec.Create(7, r8, 9);                  Check(cr.v, 702039, 'by-value 8-byte record in the middle');
  cd := TCDbl.Create(7, 2.5, 9);                 Check(cd.v, 702509, 'Double in the middle');
  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('WIDECTOR OK') else WriteLn('WIDECTOR FAILED');
end.
