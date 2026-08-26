program test_inherited_and_parenless_defaults;
{ TWO defaults bugs, found together and fixed together.

  1. `inherited Create;` against `constructor Create(AN: Integer = 8)` was
     `inherited call argument count mismatch` — the arity check ran before
     anything filled defaults, so a capability the ordinary call path already
     had was simply never reached from the inherited path.

  2. Found by varying the CALL SITE rather than the inherited call, and the
     worse of the two: a PARENLESS call to an all-defaulted method
     (`d.Foo;`) sent the call out carrying only Self, and the callee read an
     uninitialised frame slot. On a VIRTUAL method that SEGFAULTS. Unrelated to
     `inherited`, unrelated to override, and older than both.

  The shape that hid #2 for so long is worth stating: every neighbour works.
  `d.Foo(5)` works, `d.Foo()` works (the empty-parens arm fills defaults), a
  zero-parameter `d.Z;` works, and the NON-virtual spelling of the crashing
  source works. Only virtual + all-defaulted + no parens crashes, which is why
  the rows below are deliberately redundant.

  .expected IS fpc 3.2.2's own output on this source. }
{$mode objfpc}
type
  TBase = class
    n: Integer; s: AnsiString;
    constructor Create(AN: Integer = 8);
    procedure Z; virtual;
    procedure Foo(a: Integer = 3; const b: AnsiString = 'zz'); virtual;
    procedure Plain(a: Integer = 4);
    function Bar(a: Integer = 5): Integer; virtual;
  end;
  TDer = class(TBase)
    constructor Create(b: Boolean);
    procedure Foo(a: Integer = 3; const b: AnsiString = 'zz'); override;
    function Bar(a: Integer = 5): Integer; override;
  end;
constructor TBase.Create(AN: Integer = 8); begin n := AN; s := ''; end;
procedure TBase.Z; begin n := 42; end;
procedure TBase.Foo(a: Integer = 3; const b: AnsiString = 'zz'); begin n := a; s := b; end;
procedure TBase.Plain(a: Integer = 4); begin n := a; end;
function TBase.Bar(a: Integer = 5): Integer; begin Bar := a * 2; end;
constructor TDer.Create(b: Boolean); begin inherited Create; end;
procedure TDer.Foo(a: Integer = 3; const b: AnsiString = 'zz'); begin inherited Foo; end;
function TDer.Bar(a: Integer = 5): Integer; begin Bar := inherited Bar; end;

var d: TDer; b: TBase;
begin
  { 1. inherited with every argument omitted }
  d := TDer.Create(True);
  WriteLn('inh ctor : ', d.n);
  d.Foo;
  WriteLn('inh proc : ', d.n, ' ', d.s);
  WriteLn('inh func : ', d.Bar);

  { 2. the parenless call site, and each neighbour that already worked }
  b := TBase.Create;
  b.Z;             WriteLn('virt 0arg: ', b.n);
  b.Foo;           WriteLn('virt bare: ', b.n, ' ', b.s);
  b.Foo();         WriteLn('virt (): ', b.n, ' ', b.s);
  b.Foo(7);        WriteLn('virt part: ', b.n, ' ', b.s);
  b.Foo(9, 'qq');  WriteLn('virt full: ', b.n, ' ', b.s);
  b.Plain;         WriteLn('nonv bare: ', b.n);
  WriteLn('virt fn  : ', b.Bar);
  b.Free; d.Free;
end.
