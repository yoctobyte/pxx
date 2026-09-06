{ `array of const` written as a LITERAL at a call to the enclosing class's own
  method, spelled WITHOUT a receiver.

  `[...]` at an argument position is a SET to the expression parser and an open
  array to the callee; only the parameter can say which, and every call path in
  the parser asks -- except the implicit-Self one, which hand-rolled its
  argument loop and asked nothing. fcl-passrc's
  `Log(mtError, n, fmt, ['#0'])` died there as `set item must be one
  character`.

  THE REFUSAL WAS THE LUCKY CASE, AND THAT IS THE POINT OF THIS FILE.
  `'#0'` is two characters, so the set parser could not accept it. A
  SINGLE-character string is a legal set item, so the same call with `['x']`
  COMPILED -- and the callee then read `Length` off a set:

      qualified n=3 t0=2       { Self.Log -- correct }
      bare      n=1026585632 t0=0   { Log    -- no diagnostic }

  So every row below passes elements a set would happily accept, and asserts a
  LENGTH and an ELEMENT TYPE. A row that only proves the call is refused when
  it should not be would have been green throughout the bug.

  Both spellings appear and must agree: the qualified one exercises a path that
  always had the door, so a divergence between the two rows names the door
  rather than the feature.

  bug-p-an-array-of-const-literal-is-a-set-at-a-bare-self-method-call }
{$mode objfpc}
program test_an_array_of_const_literal_at_a_bare_self_method_call;
type
  TMsg = (mtError, mtWarn);
  TLog = class
    procedure Log(const F: String; const Args: array of const);
    procedure Wide(aKind: TMsg; aNum: Integer; const F: String;
                   const Args: array of const; Pos: Integer = 0);
    procedure Work;
  end;

procedure TLog.Log(const F: String; const Args: array of const);
begin
  WriteLn(F, ' n=', Length(Args), ' t0=', Args[0].VType,
          ' tlast=', Args[Length(Args) - 1].VType);
end;

procedure TLog.Wide(aKind: TMsg; aNum: Integer; const F: String;
                    const Args: array of const; Pos: Integer = 0);
begin
  WriteLn(F, ' kind=', Ord(aKind), ' num=', aNum,
          ' n=', Length(Args), ' t0=', Args[0].VType, ' pos=', Pos);
end;

procedure TLog.Work;
begin
  { single-character strings -- a LEGAL set, which is why the broken parse was
    silent rather than refused }
  Self.Log('qualified', ['x', 'y', 'z']);
  Log('bare', ['x', 'y', 'z']);

  { integers -- also a legal set }
  Log('ints', [1, 2]);

  { the fcl-passrc shape: four args against five parameters, the fifth
    defaulted, and an element the set parser must reject }
  Wide(mtError, 1001, 'wide', ['#0']);
  Wide(mtWarn, 7, 'widepos', ['#0', 'ab'], 42);
end;

var l: TLog;
begin
  l := TLog.Create;
  l.Work;
end.
