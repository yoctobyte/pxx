unit uinlinespecfwd;
{ A generic ROUTINE whose INTERFACE header and implementation BODY are apart,
  with a use of it between the two. A unit is the only place those can be
  separated, which is why this construct has no program-level spelling.
  bug-p-an-inline-specialize-before-the-generic-routines-body-is-not-rewritten }
{$mode objfpc}{$H+}
interface

generic function TwiceOf<T>(a: T): T;      { the header -- what makes it visible }
function UsedBeforeBody: LongInt;
function UsedAfterBody: LongInt;

implementation

{ the USE, above the body and below the header -- fpc accepts it, pxx refused }
function UsedBeforeBody: LongInt;
begin
  Result := specialize TwiceOf<LongInt>(21);
end;

generic function TwiceOf<T>(a: T): T;      { the body, only here }
begin
  Result := a + a;
end;

{ the same use BELOW the body: the shape that always worked, kept as the control
  that says which of the two a regression broke }
function UsedAfterBody: LongInt;
begin
  Result := specialize TwiceOf<LongInt>(16);
end;

end.
