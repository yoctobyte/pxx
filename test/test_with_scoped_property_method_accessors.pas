{ A with-scoped property whose accessors are METHODS — the spelling the
  with-scope arm of ParseLValueAST used to decline in a COMMENT.

  It resolved a with-scoped property only when the accessor was a FIELD. A
  getter/setter pair fell past that arm, past the `Free` desugar and past the
  method lookup (a property name is not a method name), out of the with loop
  and out of the compiler as `undefined variable (V)`. Every OTHER receiver
  already resolved the same declaration: `c.V`, a bare `V` inside a method,
  `Self.V`, and `TCls.V` for the class flavour. One concept, four resolution
  paths, and the fourth declined in prose —
  devdocs/dev/normalise-dont-special-case.md.

  THE ACCESSORS MUST BE OBSERVABLE, not merely called. Every getter here adds
  100 and every setter stores plain, so a row that reached the BACKING FIELD
  instead of the accessor prints a number 100 too small: a with-scoped property
  wrongly resolved as its own backing field would compile every line in this
  file and print plausible values. That is the failure this file is aimed at,
  and it is why no row prints the field alone.

  The INDEXED rows are the second half of the same arm: `:=` follows the
  SUBSCRIPT, so a zero-lookahead peek reads the `[` and picks the READ accessor
  for a write. `A[FA[0] + 1] := 9` is the row that needs the peek to BALANCE
  rather than merely skip one token — its subscript is itself an indexed
  expression, so an unbalanced scan stops inside it.

  Expected output is fpc 3.2.2's own.
  bug-p-a-with-scoped-property-with-method-accessors-is-undefined }
program test_with_scoped_property_method_accessors;
{$mode delphi}

type
  TCls = class
  private
    FV: LongInt;
    FA: array[0..3] of LongInt;
    FN: LongInt;
    function GetV: LongInt;
    procedure SetV(v: LongInt);
    function GetA(i: LongInt): LongInt;
    procedure SetA(i, v: LongInt);
    function GetN: LongInt;
  public
    property V: LongInt read GetV write SetV;
    property A[i: LongInt]: LongInt read GetA write SetA;
    { read-only, and read through a getter — the arm must not demand a setter }
    property N: LongInt read GetN;
  end;

function TCls.GetV: LongInt; begin Result := FV + 100; end;
procedure TCls.SetV(v: LongInt); begin FV := v; end;
function TCls.GetA(i: LongInt): LongInt; begin Result := FA[i] + 100; end;
procedure TCls.SetA(i, v: LongInt); begin FA[i] := v; end;
function TCls.GetN: LongInt; begin Result := FN + 100; end;

var
  c: TCls;
begin
  c := TCls.Create;
  c.FN := 7;
  with c do
  begin
    { scalar: the setter stores plain, the getter adds 100 }
    V := 5;
    WriteLn(FV, ' ', V);

    { indexed: `:=` sits after the subscript }
    A[3] := 33;
    WriteLn(FA[3], ' ', A[3]);

    { ...and the subscript is itself an indexed expression, so the peek that
      finds the `:=` has to balance the bracket group }
    FA[0] := 1;
    A[FA[0] + 1] := 9;
    WriteLn(FA[2], ' ', A[2]);

    { read-only through a getter }
    WriteLn(N);
  end;
end.
