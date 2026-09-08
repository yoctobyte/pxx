{ Delphi mode takes a method reference with no `@` at all. Until this fixture the
  receiver had to be a single identifier -- a symbol, a class name or a metaclass
  variable -- because TryParseParenlessMethodRef resolved it from one token. A
  CHAIN is a fourth thing: an expression whose type is a class. So
  `TG.F := g.Foo` worked and `TG.F := TG.Create.Foo` answered `wrong number of
  parameters in call to TG.Foo`, which reads as a defect in Foo and is not.

  WHY THIS ARM NEEDED A REWIND WHERE ITS `@` TWIN DID NOT. `@` commits the parse
  the moment it is seen, so that site can walk the chain and decide afterwards --
  its comment says "rewind nothing, set the stop, recurse". This one is a TRIAL:
  it has to leave the token stream untouched when the shape turns out to be an
  ordinary call, and finding out what `TG.Create` IS means parsing it, which
  moves TokPos and allocates nodes.

  ROW 3 IS THE ONE THAT MATTERS AND IT IS THE ONE A HAPPY-PATH FIXTURE OMITS.
  `TG.Create.Bar` is the same token shape as row 2 and is a CALL, because Bar's
  result does not satisfy a method-pointer target. It can only work if the failed
  trial put back everything it touched -- the token position, ProcCount,
  SymCount, FrameSize and the AST arena. A fixture with only rows 1 and 2 passes
  with no rewind at all, because nothing would ever ask for one.
  bug-p-a-delphi-parenless-method-reference-cannot-have-a-chained-receiver }
program test_delphi_parenless_methodref_chained_receiver;
{$mode delphi}
type
  TG = class
    X: Integer;
    class var F: function(const aX: Integer): TG of object;
    function Foo(const aX: Integer): TG;
    function Bar: Integer;
    function Mk: TG;
  end;
function TG.Foo(const aX: Integer): TG;
begin Result := TG.Create; Result.X := aX; end;
function TG.Bar: Integer;
begin Result := 7; end;
function TG.Mk: TG;
begin Result := TG.Create; Result.X := 5; end;
var g: TG; n: Integer;
begin
  g := TG.Create;

  { 1. depth 1 -- the spelling that already worked, kept so a regression in the
       common case cannot hide behind the new arm. }
  TG.F := g.Foo;
  WriteLn('one=', TG.F(41).X);

  { 2. a chained receiver: construct, then bind the instance's method. }
  TG.F := TG.Create.Foo;
  WriteLn('chain=', TG.F(42).X);

  { 3. THE REWIND. Same shape, but the trailing name is a CALL and the trial
       must put the stream back for the ordinary parse to read it. }
  n := TG.Create.Bar;
  WriteLn('call=', n);

  { 4. two links before the method, through a method-valued receiver. }
  TG.F := g.Mk.Foo;
  WriteLn('deep=', TG.F(43).X);

  { 5. the rewind again, one link deeper, so the restored position is exercised
       at a length where an off-by-one would survive row 3. }
  n := g.Mk.Bar;
  WriteLn('deepcall=', n);
end.
