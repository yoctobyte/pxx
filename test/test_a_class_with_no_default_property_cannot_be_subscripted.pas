program test_a_class_with_no_default_property_cannot_be_subscripted;
{ THE HOLE THE `default` SPLIT WOULD HAVE WIDENED, closed in the same commit.

  `default 16` on a plain property used to set the default-INDEXED-property
  flag, so a class carrying only a value clause was still refused when you
  subscripted it -- with the wrong words (`default property is write-only`
  against fpc's `No default property available`), but refused. Correcting the
  flag routes that same source into the fall-through instead, where an instance
  pointer meets a raw AN_INDEX: `t[0]` answered 375390216, then -1189085176 on
  the next run of the same program. Silent, not a crash. Trading a badly worded
  refusal for a wrong number is strictly worse than the bug being fixed.

  PRE-EXISTING, NOT INTRODUCED: a class with no `default` clause at all already
  answered garbage here (148897800 on pin v404, -1189085176 at tip), which is
  why the fix is a refusal in the parser rather than a revert of the split.

  TWO LOOPS, AND THAT IS WHY THERE ARE THREE ROWS. `t[0]` goes through
  ParseLValueAST's suffix loop; `TC(t)[0]` goes through the CHAINED walker,
  which never asked the question at all -- 130481955799048. One loop fixed and
  the other left silent is the double case normalise-dont-special-case names,
  and the cast spelling is the arm that stays broken if you only run the first.

  ONE ROW PER COMPILE, SELECTED BY -dROW_x, AND THAT IS NOT TIDINESS. The check
  is an Error() and Error() halts, so all three rows in one file report exactly
  the first one -- a `grep -c` of 1 that passes whether the other two are refused
  or silently print garbage. Two thirds of the assertions would have been unable
  to fail. Three compiles, three greps, and the Makefile asserts each.

  fpc 3.2.2 refuses all three with `No default property available`.
  bug-p-a-property-default-value-clause-is-read-as-the-default-indexed-property-marker }
{$mode delphi}

type
  TC = class
  private
    FDepth: Integer;
  public
    property Depth: Integer read FDepth write FDepth default 16;
  end;

  TPlain = class
  private
    FN: Integer;
  public
    property N: Integer read FN write FN;
  end;

var
  t: TC;
  p: TPlain;
begin
  t := TC.Create;
  p := TPlain.Create;
{$ifdef ROW_A}
  WriteLn(t[0]);        { the value clause must not have claimed the slot }
{$endif}
{$ifdef ROW_B}
  WriteLn(TC(t)[0]);    { the chained walker, the second loop }
{$endif}
{$ifdef ROW_C}
  WriteLn(p[0]);        { no default clause at all -- the pre-existing hole }
{$endif}
  WriteLn(t.Depth, p.N);   { every row compiles the same class pair }
end.
