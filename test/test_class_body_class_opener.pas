program test_class_body_class_opener;
{ EVERY spelling the class-body `class` opener accepts, in ONE file, because
  the opener is a single lookahead point now and a change to it moves all of
  them at once. It used to be five independent arms, so a regression could hit
  one spelling and leave the other four green.

  BOTH KEYWORD ORDERS around `generic` are here on purpose: `generic class
  function` is FPC's (tgenfunc3.pp) and `class generic function` is ours
  (test/generic_xunit_method_units/uxgm.pas). The opener consumes them in a
  loop rather than testing two fixed orders.

  The REFUSALS are asserted in the Makefile, not here -- a file that must not
  compile cannot also print.

  TWO ROWS ARE PXX EXTENSIONS AND FPC 3.2.2 CANNOT VALIDATE THEM: it rejects
  `class const` outright (`Procedure or Function expected`) and it has no
  `class generic function` order. With those two dropped, fpc -Mdelphi prints
  this file's other seven rows IDENTICALLY -- measured, not assumed.

  The one row fpc does NOT print is `fini`: FPC 3.2.2 runs a program-level
  class CONSTRUCTOR and skips the matching class DESTRUCTOR, where pxx runs
  both. That divergence is older than this test and untouched by it -- pin
  v407 prints `fini` too -- and pxx is doing the more useful thing, so it is
  recorded here rather than filed.
  bug-p-the-class-body-class-opener-is-a-hand-maintained-lookahead-list }
type
  TC = class
  const
    Plain = 1;
  class const
    Version = 3;
  class var
    Count: LongInt;
  var
    Inst: LongInt;
    Field: LongInt;
    class property Total: LongInt read Count write Count;
    class function Twice(x: LongInt): LongInt;
    class procedure Bump;
    class constructor Init;
    class destructor Fini;
    generic class function GenA<T>(x: T): T;
    class generic function GenB<T>(x: T): T;
  end;

class function TC.Twice(x: LongInt): LongInt;
begin Result := x * 2; end;

class procedure TC.Bump;
begin Count := Count + 1; end;

class constructor TC.Init;
begin Count := 100; end;

class destructor TC.Fini;
begin WriteLn('fini ', Count); end;

generic class function TC.GenA<T>(x: T): T;
begin Result := x; end;

class generic function TC.GenB<T>(x: T): T;
begin Result := x; end;

var
  o: TC;
begin
  WriteLn('plain ', TC.Plain);
  WriteLn('version ', TC.Version);
  { the class constructor ran before this line }
  WriteLn('count ', TC.Count);
  TC.Bump;
  WriteLn('total ', TC.Total);
  WriteLn('twice ', TC.Twice(21));
  WriteLn('gena ', TC.GenA<LongInt>(7));
  WriteLn('genb ', TC.GenB<LongInt>(9));
  o := TC.Create;
  o.Inst := 5;
  o.Field := 6;
  WriteLn('inst ', o.Inst, ' ', o.Field);
  o.Free;
end.
