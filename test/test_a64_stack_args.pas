{ AAPCS64 stack arguments, one program per CALL KIND, because the capability was
  missing from five of six and present in the sixth — so a test that exercises
  only the direct call is exactly the test that was already passing.

  Ten parameters: x0..x7 hold the first eight and args 8 and 9 go in the
  outgoing stack block. Every routine returns a value that depends on the LAST
  two, which are the ones that travel on the stack — a routine summing only the
  register args would pass a weaker test while dropping them silently.
  bug-a-aarch64-has-no-stack-argument-passing-for-five-of-six-call-kinds }
program test_a64_stack_args;

type
  TBase = class
    function Ten(a, b, c, d, e, f, g, h, i, j: Integer): Integer; virtual;
  end;
  TChild = class(TBase)
    function Ten(a, b, c, d, e, f, g, h, i, j: Integer): Integer; override;
  end;

  TCtor = class
    Sum: Integer;
    constructor Create(a, b, c, d, e, f, g, h, i, j: Integer);
  end;

  TTenFn = function(a, b, c, d, e, f, g, h, i, j: Integer): Integer;

function TBase.Ten(a, b, c, d, e, f, g, h, i, j: Integer): Integer;
begin
  Result := a + b + c + d + e + f + g + h + i * 100 + j * 1000;
end;

function TChild.Ten(a, b, c, d, e, f, g, h, i, j: Integer): Integer;
begin
  Result := 1000000 + a + b + c + d + e + f + g + h + i * 100 + j * 1000;
end;

constructor TCtor.Create(a, b, c, d, e, f, g, h, i, j: Integer);
begin
  Sum := a + b + c + d + e + f + g + h + i * 100 + j * 1000;
end;

{ the DIRECT call — the one kind that already worked, kept as the control }
function DirectTen(a, b, c, d, e, f, g, h, i, j: Integer): Integer;
begin
  Result := a + b + c + d + e + f + g + h + i * 100 + j * 1000;
end;

var
  b: TBase;
  c: TChild;
  o: TCtor;
  fn: TTenFn;
begin
  Writeln('direct   ', DirectTen(1, 2, 3, 4, 5, 6, 7, 8, 9, 10));

  fn := @DirectTen;
  Writeln('indirect ', fn(1, 2, 3, 4, 5, 6, 7, 8, 9, 10));

  c := TChild.Create;
  b := c;
  Writeln('virtual  ', b.Ten(1, 2, 3, 4, 5, 6, 7, 8, 9, 10));
  b.Free;

  o := TCtor.Create(1, 2, 3, 4, 5, 6, 7, 8, 9, 10);
  Writeln('ctor     ', o.Sum);
  o.Free;
end.
