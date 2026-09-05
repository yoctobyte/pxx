{ A class property with ARGUMENTS — the two spellings that give an accessor an
  index, reached through the class name.

  `class property A[i: LongInt]` declares a subscript; `class property P0: T
  index 0` supplies a constant. Both feed the SAME accessor parameter, and
  neither reached it: the class-name path in ParseLValueAST hand-built its
  accessor call instead of using pasparser_call.inc's four accessor helpers, so

    TC.A[2] := 7    picked the READ accessor -- its `:=` peek was zero-lookahead
                    and saw the `[` -- then said `wrong number of parameters`
    WriteLn(TC.A[2]) left the `[` for a caller with no use for it:
                    `expected ')' before '['`
    TC.P0 := 5      built the index constant with PropIndexConstArg and then
                    DROPPED the chain, never linking it into the call
    WriteLn(TC.P0)  never called PropIndexConstArg at all

  THE SHARING IS THE ASSERTION, not the compile. Both properties here are
  backed by ONE class var array through ONE accessor pair, so the index has to
  arrive for the rows to differ from each other: if it were dropped, every row
  would read and write slot 0 and still print a plausible number. The `index`
  pair is deliberately two properties over one getter/setter, which is the
  whole point of the modifier and the only way a lost constant shows up.

  Every spelling works through an INSTANCE already (property A[i] on a plain
  object), which is why this read as a missing feature rather than a bug: one
  concept, two resolution paths, and the second one stayed broken --
  devdocs/dev/normalise-dont-special-case.md.

  Expected output is fpc 3.2.2's own.
  bug-p-a-class-property-cannot-be-indexed }
program test_class_property_indexed;
{$mode delphi}

type
  TCls = class
  private
    class var FA: array[0..7] of LongInt;
    class function GetA(i: LongInt): LongInt; static;
    class procedure SetA(i, v: LongInt); static;
    class function GetIx(ix: LongInt): LongInt; static;
    class procedure SetIx(ix, v: LongInt); static;
  public
    { a declared SUBSCRIPT }
    class property A[i: LongInt]: LongInt read GetA write SetA;
    { two properties, one accessor pair, told apart ONLY by `index` }
    class property P0: LongInt index 4 read GetIx write SetIx;
    class property P1: LongInt index 5 read GetIx write SetIx;
  end;

  { the multi-index spelling, and a getter that is not `static` }
  TGrid = class
  private
    class var FG: array[0..8] of LongInt;
    class function GetC(r, c: LongInt): LongInt; static;
    class procedure SetC(r, c, v: LongInt); static;
  public
    class property Cells[r, c: LongInt]: LongInt read GetC write SetC;
  end;

class function TCls.GetA(i: LongInt): LongInt;
begin Result := FA[i] + 100; end;

class procedure TCls.SetA(i, v: LongInt);
begin FA[i] := v; end;

class function TCls.GetIx(ix: LongInt): LongInt;
begin Result := FA[ix]; end;

class procedure TCls.SetIx(ix, v: LongInt);
begin FA[ix] := v; end;

class function TGrid.GetC(r, c: LongInt): LongInt;
begin Result := FG[r * 3 + c]; end;

class procedure TGrid.SetC(r, c, v: LongInt);
begin FG[r * 3 + c] := v; end;

begin
  { subscript, write then read — the getter adds 100 so a read that never
    reached the accessor would print the raw slot instead }
  TCls.A[2] := 7;
  WriteLn(TCls.FA[2]);
  WriteLn(TCls.A[2]);

  { the subscript is an EXPRESSION, not just a literal, and it may itself be
    indexed — which is what the `:=` peek has to balance past }
  TCls.FA[0] := 1;
  TCls.A[TCls.FA[0] + 2] := 9;
  WriteLn(TCls.FA[3]);

  { `index N`: two properties over one accessor pair. If the constant were
    dropped both rows would land on slot 0 and agree with each other. }
  TCls.P0 := 41;
  TCls.P1 := 42;
  WriteLn(TCls.P0, ' ', TCls.P1);
  WriteLn(TCls.FA[4], ' ', TCls.FA[5]);

  { multi-index }
  TGrid.Cells[1, 2] := 55;
  WriteLn(TGrid.Cells[1, 2], ' ', TGrid.FG[5]);
end.
