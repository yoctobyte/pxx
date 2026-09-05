{ A generic header written TIGHT -- no space before the `=`:

    generic TList<_T>=class(TObject)

  The lexer's maximal munch makes `>=` a single tkGe token, and the header
  grammar wants `>` then `=`, so this was refused with "expected '>' before
  '>='" while the identical program WITH a space compiled and ran. A space
  cannot change what a program means, and fpc 3.2.2 accepts both spellings --
  the FPC test suite writes the tight one throughout (it stood in front of 8
  rows of the conformance generics cluster: tgeneric1/3/5/6/8/10/11/92).

  BOTH SPELLINGS ARE HERE ON PURPOSE. The bug was that they disagreed, so a row
  that exercises only the tight one would pass against a compiler that had
  broken the spaced one instead, and neither alone can see the divergence that
  was the actual defect.

  The fix is deliberately at the consumer, not in the lexer: the header
  collector uses "`>=` lexes as tkGe" to tell a template header from a
  comparison `a < b >= c`, so splitting tkGe globally would destroy a
  distinction the parser depends on.
  feature-pascal-corpus-fpc-testsuite }
{$mode objfpc}
program generic_header_tight_equals;
type
  generic TTight<_T>=class(TObject)
    procedure Show(x: _T);
  end;
  generic TSpaced<_T> = class(TObject)
    procedure Show(x: _T);
  end;
  TTightInt  = specialize TTight<Integer>;
  TSpacedInt = specialize TSpaced<Integer>;

procedure TTight.Show(x: _T);  begin WriteLn('tight ', x); end;
procedure TSpaced.Show(x: _T); begin WriteLn('spaced ', x); end;

var a: TTightInt; b: TSpacedInt;
begin
  a := TTightInt.Create;
  b := TSpacedInt.Create;
  a.Show(1);
  b.Show(2);
end.
