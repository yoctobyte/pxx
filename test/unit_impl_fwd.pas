unit unit_impl_fwd;

{ Exercises the implementation-section declaration pre-scan: the public routine
  and the private helpers below are all used before they are defined, and there
  is NO `forward` directive anywhere in the implementation. Only the entry point
  is exported; everything it leans on is impl-private. }

interface

function Compute: Integer;

implementation

{ Public body calls a private helper defined later in the implementation. }
function Compute: Integer;
begin
  Compute := AddUp(4) + Helper;   { both defined below }
end;

{ Mutual recursion between two private helpers, no forward declarations. }
function AddUp(n: Integer): Integer;
begin
  if n <= 0 then
    AddUp := 0
  else
    AddUp := n + AddDown(n - 1);
end;

function AddDown(n: Integer): Integer;
begin
  if n <= 0 then
    AddDown := 0
  else
    AddDown := n + AddUp(n - 1);
end;

{ A private helper that uses a const declared after it. }
function Helper: Integer;
begin
  Helper := PrivBase * 2;
end;

const
  PrivBase = 50;

end.
