program test_pchar_of_computed_string_leaks;
{ `PChar(expr)` over a computed AnsiString gets an OWNER.

  PXXPCharOf -- the wrapper the PChar cast routes a managed string through, so
  that PChar('') is a valid pointer to a shared #0 byte rather than nil -- is
  declared `(p: Pointer): Pointer`, deliberately, because it does pointer
  arithmetic. That makes ParamWantsManagedStrTemp False for it, so NONE of the
  seven managed-string-temp sites park anything at this call. A computed operand
  therefore handed the callee a char pointer into a block carrying a +1 that
  belonged to nobody, unreachable to every scope-exit scan because it was never
  a symbol.

  live before -> after, against the binary immediately before the fix
  (e7fb90cccb94, which already carries the array-of-const sibling f42665459).
  One arm per program, 1000 trips each:
    TakeP(PChar('lit' + c))     937 -> 4    allocs 1871
    TakeP(PChar(t))               3 -> 3    allocs  921   (control, unmoved)
  This whole program: 1421 -> 9 against a bound of 50, allocs 4809 either way.
  allocs is unchanged on every row -- same traffic, so the delta is ownership.
  The named-local row is the control that says this is about ownership and not
  about the cast.

  All five targets read the SAME numbers (pre 1421, post 9, allocs 4809 on
  x86-64/i386/aarch64/arm32/riscv32): the hole was in the shared cast lowering,
  with nothing per-target beside it.

  The printed lines cannot catch this. The pre-fix binary prints every one of
  them identically, on all five targets, while leaking 1421 blocks -- only the
  absolute bound sees it. They are here to catch the OPPOSITE mistake: a temp
  released too early would corrupt `q^` or the empty-string arms rather than
  move any count.

  The lifetime the fix creates is SCOPE EXIT, which is strictly longer than
  FPC's guarantee for PChar-of-a-temporary (end of statement), so no program
  that was correct under the oracle becomes wrong here.

  The empty-string guarantee is the thing this must not break, and it is checked
  by VALUE below rather than assumed: PChar(e) and PChar(e + '') must both be
  non-nil and point at a #0, which is what PXXPCharOf exists for. FPC agrees on
  every printed line.
  bug-a-pchar-of-a-computed-string-leaks-the-string }
{$mode objfpc}{$H+}
uses sysutils;

const N = 1000;

var i, sink: Integer;
    c: Char;
    t, e, acc: AnsiString;
    p, q: PChar;

procedure TakeP(s: PChar);
begin
  Inc(sink, Ord(s^));
end;

begin
  sink := 0; acc := ''; t := '';

  { computed operand -- the leak }
  for i := 1 to N do
  begin
    c := Chr(48 + i mod 10);
    TakeP(PChar('lit' + c));
  end;

  { CONTROL: a named local already owned it }
  for i := 1 to N do
  begin
    c := Chr(48 + i mod 10);
    t := 'lit' + c;
    TakeP(PChar(t));
  end;

  { both spellings live at once, and the pointer is READ, so a temp released too
    early would show up as wrong output rather than as a leak count }
  for i := 1 to 500 do
  begin
    t := 'k' + IntToStr(i mod 7);
    p := PChar(t);
    q := PChar(t + '-' + IntToStr(i));
    Inc(sink, Ord(p^) + Ord(q^) + StrLen(q));
    acc := acc + Char(q[0]);
  end;

  { PXXPCharOf's reason for existing: never nil, always a readable #0 }
  e := '';
  WriteLn('empty nil=', PChar(e) = nil, ' ord=', Ord(PChar(e)^));
  WriteLn('computed-empty nil=', PChar(e + '') = nil, ' ord=', Ord(PChar(e + '')^));

  WriteLn('sink=', sink);
  WriteLn('acclen=', Length(acc), ' head=', Copy(acc, 1, 8));
end.
