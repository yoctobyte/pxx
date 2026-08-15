program test_strict_overload_width;
uses sysutils;
{ --strict-overload-width: FPC's NARROWEST-THAT-FITS choice among integer
  overloads, and the DEFAULT dialect's widening left alone beside it.

  Both halves are asserted from the same source, because the whole point of the
  flag is that the two answers differ: the Makefile compiles this twice and
  diffs each against its own expectation. The unflagged run must stay
  byte-identical to what pxx printed before the flag existed — the widening is
  the dialect, not a bug (user, 2026-08-14).

  The `Cardinal` row is the one that carries the rule. FPC picks Int64 there
  and LongInt everywhere else, which is only explicable as narrowest-that-FITS:
  LongInt is the same WIDTH as Cardinal but cannot hold its top half. That is
  why the flag needs IntParamHoldsEveryValue rather than ArgNarrowsInt, whose
  `TypeSize(p) < TypeSize(a)` test is signedness-blind and calls that a fit.

  Oracle for every row is FPC 3.2.2 under {$mode objfpc} — required, because in
  default FPC mode `Integer` is 16-bit and silently answers a different
  question.
  compat-pascal-strict-fpc-should-pick-the-narrowest-integer-overload }

type
  MyInt = Integer;      { a user alias resolves like its underlying type }

function F(v: Int64): AnsiString; overload;
begin F := 'int64'; end;
function F(v: LongInt): AnsiString; overload;
begin F := 'longint'; end;

function U(v: QWord): AnsiString; overload;
begin U := 'qword'; end;
function U(v: LongWord): AnsiString; overload;
begin U := 'longword'; end;
function U(v: Word): AnsiString; overload;
begin U := 'word'; end;

{ Extended is deliberately absent: pxx maps it onto the same 8-byte kind as
  Double on this target, so declaring both is a duplicate definition, not an
  overload set. Float sets already agreed with FPC before the flag; these two
  rows are here as the control that the flag leaves them alone. }
function G(v: Double): AnsiString; overload;
begin G := 'double'; end;
function G(v: Single): AnsiString; overload;
begin G := 'single'; end;

{ the only candidate NARROWS its argument: it must still win, flag or not —
  the ranking skips it, and the ordinary compatible phase binds it }
function N(v: SmallInt): AnsiString; overload;
begin N := 'smallint'; end;

var
  i: Integer; li: LongInt; si: SmallInt; c: Cardinal; b: Byte;
  w: Word; q: QWord; s: Single; d: Double; m: MyInt;
begin
  i := -1; li := -1; si := -1; c := 1; b := 1;
  w := 1; q := 1; s := 1; d := 1; m := -1;

  WriteLn('Integer  ', F(i));
  WriteLn('LongInt  ', F(li));
  WriteLn('SmallInt ', F(si));
  WriteLn('Cardinal ', F(c));
  WriteLn('Byte     ', F(b));
  WriteLn('literal  ', F(-1));
  WriteLn('MyInt    ', F(m));

  WriteLn('uByte    ', U(b));
  WriteLn('uWord    ', U(w));
  WriteLn('uCard    ', U(c));
  WriteLn('uQWord   ', U(q));

  WriteLn('fSingle  ', G(s));
  WriteLn('fDouble  ', G(d));

  WriteLn('narrow   ', N(i));

  { the downstream case Track B was blocked on: IntToHex's LongInt body masks,
    so selecting it is what makes a negative Integer print eight digits }
  WriteLn('hex      ', IntToHex(i, 8));
end.
