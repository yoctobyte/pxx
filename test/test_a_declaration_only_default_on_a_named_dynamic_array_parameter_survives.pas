program test_a_declaration_only_default_on_a_named_dynamic_array_parameter_survives;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

{ `procedure M(const a: TArr = nil)` declared in a class body and implemented
  WITHOUT repeating the default -- the ordinary Pascal spelling -- made `o.M`
  fail with `wrong number of parameters in call to TC.M`. fpc prints `M len=0`.

  THE FOUR CONTROLS ARE THE FINDING, not the failing row: an Integer default and
  a string default with the same omission on the same class were honoured, the
  same `TArr = nil` written on BOTH sides worked, and the same shape as a free
  routine worked. So it was never "class methods lose declaration defaults", nor
  "nil defaults are lost", nor "the declaration-only spelling", nor the type on
  its own -- it was that type at that site, and each control removes one of the
  four explanations a single failing row would have left open.

  CAUSE, AND IT WAS FIXED BY SOMETHING ELSE. The ticket guessed that the
  declaration row recorded the ELEMENT kind for `TArr` while the implementation
  row recorded the array, so the two rows disagreed about the parameter and the
  binding dropped the default with it -- and said the guess was unverified. It
  was right: the four method parameter parsers knew only the literal `array of`
  spelling and ParseTypeKind collapsed a named array type to a scalar. Teaching
  them named array types
  (bug-p-an-interface-dispatched-call-passing-a-named-dynamic-array-segfaults)
  made the two rows agree and this row started passing.

  AND IT BROKE THIS FILE'S SIBLING ON THE WAY, WHICH IS WHY THE `= nil` ROWS ARE
  HERE AT ALL. The open-array-default refusal asks its caller "is this an open
  array", and the three method parsers answered with their IsArray flag because
  that flag used to be true ONLY for the literal `array of` spelling. The moment
  a named array type also set it, `const a: TArr = nil` in a class body was
  refused as an open-array default -- a REGRESSION shipped in that fix, caught
  only by running this test by hand, because these rows live in `test-core` and
  `gate.sh quick` does not run them. The three parsers now ask
  `IsArray and (dynDepth <= 0)`, which is what ParseSubroutine has always asked.

  All four parameter parsers are represented, declaration-only, because a flag
  passed wrongly at one call site refuses only there.
  bug-p-a-named-dynamic-array-default-declared-in-a-class-body-is-lost-if-the-implementation-omits-it }

type
  TArr = array of Integer;

  TC = class
    procedure M(const a: TArr = nil);          { default on the DECLARATION only }
    procedure N(n: Integer = 5);               { control: ordinal }
    procedure S(const s: AnsiString = 'hi');   { control: managed string }
    procedure B(const a: TArr = nil);          { control: written on BOTH sides }
  end;

  TR = record
    procedure R(const a: TArr = nil);
  end;

  IFoo = interface
    ['{5E1B0A11-1111-4222-8333-444455556666}']
    procedure I1(const a: TArr = nil);
  end;

  TFoo = class(TInterfacedObject, IFoo)
    procedure I1(const a: TArr = nil);
  end;

  { NO PROC-TYPE ROW, and the reason is a fourth defect rather than tidiness:
    `TCb = procedure(n: Integer = 5)` does not parse at all -- `expected ')'
    before '='` -- for ANY parameter type. ParseProcTypeSignature has no
    ParseParamDefaultValue call, so the proc-type parser is the one of the four
    that cannot express a default in the first place. fpc compiles it and
    honours it at a parenless indirect call. Measured 2026-09-06 and filed;
    putting a row here would fail for a reason that has nothing to do with the
    declaration-only binding this file is about.
    bug-p-a-procedural-types-parameter-cannot-carry-a-default-value }

var
  fails: Integer = 0;
  seen: AnsiString = '';

procedure Note(const tag: AnsiString; n: Integer);
var d: AnsiString;
begin
  Str(n, d);
  seen := seen + tag + '=' + d + ' ';
end;

procedure TC.M(const a: TArr);              begin Note('M', Length(a)); end;
procedure TC.N(n: Integer);                 begin Note('N', n); end;
procedure TC.S(const s: AnsiString);        begin Note('S', Length(s)); end;
procedure TC.B(const a: TArr = nil);        begin Note('B', Length(a)); end;
procedure TR.R(const a: TArr);              begin Note('R', Length(a)); end;
procedure TFoo.I1(const a: TArr);           begin Note('I', Length(a)); end;
procedure Free1(const a: TArr = nil);       begin Note('F', Length(a)); end;

procedure Expect(const what, got, want: AnsiString);
begin
  if got = want then
    WriteLn('ok   ', what, ' ', got)
  else
  begin
    WriteLn('FAIL ', what, ' got ', got, ' want ', want);
    Inc(fails);
  end;
end;

var
  o: TC;
  r: TR;
  ff: TFoo;
begin
  o := TC.Create;
  ff := TFoo.Create;

  { THE ROW THAT WAS BROKEN: declaration-only default, named dynamic array. }
  seen := ''; o.M;      Expect('class decl-only ', seen, 'M=0 ');

  { the four controls, each removing a different explanation }
  seen := ''; o.N;      Expect('ctrl ordinal    ', seen, 'N=5 ');
  seen := ''; o.S;      Expect('ctrl string     ', seen, 'S=2 ');
  seen := ''; o.B;      Expect('ctrl both sides ', seen, 'B=0 ');
  seen := ''; Free1;    Expect('ctrl free rtn   ', seen, 'F=0 ');

  { ...and the other two parsers with no implementation header to fall back on,
    which is where a flag passed wrongly at one call site would show }
  seen := ''; r.R;      Expect('record decl-only', seen, 'R=0 ');
  seen := ''; ff.I1;    Expect('iface decl-only ', seen, 'I=0 ');

  { a NON-nil default is not expressible for a dynamic array in either compiler,
    so `nil` is the whole of what this type can default to and there is no
    second value to distinguish a correct fill from a zeroed one. The controls
    above carry that weight instead: N=5 and S=2 are values no zero fill
    produces. }

  if fails = 0 then WriteLn('DECLONLYDEFAULT OK') else WriteLn('DECLONLYDEFAULT FAILED ', fails);
end.
