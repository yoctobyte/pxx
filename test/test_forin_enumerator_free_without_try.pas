program TestForInEnumeratorFreeWithoutTry;
{ bug-a-a-generator-instance-is-not-freed-when-an-exception-escapes-the-for-in
  (the sibling arm found while fixing it)

  A `for X in C` over a class with GetEnumerator wraps the loop in a try/finally
  so the enumerator's `Free` runs on the unwind. That desugar has been here for a
  long time, and it NEVER ASKED FOR THE EXCEPTION RUNTIME. The stubs are emitted
  from a token pre-scan in ParseProgram (they are code, and code emitted after
  the body has started lands inside it), and that scan looked for a SOURCE `try`
  or `raise`. A program whose only try/finally is one the COMPILER synthesised
  therefore got ExcRaiseAddr = 0.

  Measured: this program does not compile on pin v403 --
  `compiler error: call to a runtime stub that was never emitted (code offset 0
  is the ELF entry point)`. It is not a new break; the generator arm of the same
  desugar just made it reachable a second way, which is how it was found.

  THE TWO THINGS THAT MUST BOTH BE TRUE, and one of them is why the file has no
  `try` in it: the loop must run (sum=60) and the enumerator must be freed
  exactly once (freed=1). A program that merely compiles proves neither, and
  adding a `try` anywhere would enable the runtime by the old path and make the
  test unable to fail. }

type
  TEnum = class
    i: Integer;
    function MoveNext: Boolean;
    function GetCurrent: Integer;
    property Current: Integer read GetCurrent;
    procedure Free;
  end;
  TCont = class
    function GetEnumerator: TEnum;
  end;

var freed: Integer;

function TEnum.MoveNext: Boolean; begin Inc(i); MoveNext := i <= 3; end;
function TEnum.GetCurrent: Integer; begin GetCurrent := i * 10; end;
procedure TEnum.Free; begin Inc(freed); end;

function TCont.GetEnumerator: TEnum;
var e: TEnum;
begin e := TEnum.Create; e.i := 0; GetEnumerator := e; end;

var c: TCont; x, s: Integer;
begin
  c := TCont.Create;
  freed := 0;
  s := 0;
  for x in c do s := s + x;
  writeln('sum=', s, ' freed=', freed);
end.
