program test_managed_arg_temp;

{ A materialised managed-string argument (literal, concat, char/string
  coercion, or function result -- anything that is not an existing lvalue) is
  refcount 1 with no owner. The compiler binds each such argument to a hidden
  owning local and passes it by borrow, so the value is released on scope exit
  (and the previous value is released on loop reuse) instead of leaking.

  This guards correctness: the callee sees the right value for every temp form,
  passing an existing variable still works (borrowed, not re-bound), and the
  hidden local must not corrupt or prematurely free a value that the caller
  still holds. The loops exercise repeated reuse of the hidden slot. }

{$define PXX_MANAGED_STRING}

function Tag(a: AnsiString): AnsiString;
begin
  Tag := '<' + a + '>';
end;

function Mk(n: Integer): AnsiString;
begin
  Mk := 'm';
end;

procedure Echo(s: AnsiString);
begin
  writeln(s);
end;

procedure Check(ok: Boolean);
begin
  if ok then writeln(1) else writeln(0);
end;

var
  v: AnsiString;
  c: Char;
  i, good: Integer;
begin
  Echo('literal');            { literal temp }
  Echo('a' + 'b');            { concat temp }
  c := 'k';
  Echo(c);                    { char variable -> AnsiString }
  writeln(Tag('x'));          { temp arg through a function result }
  writeln(Tag(Mk(0)));        { function-result arg (nested call) }

  v := 'keep';
  Echo(v);                    { existing variable: borrowed, not re-bound }
  Check(v = 'keep');          { v must be intact after the borrow }

  good := 0;
  for i := 1 to 5000 do       { hidden-slot reuse: previous value released }
    if Tag('y') = '<y>' then Inc(good);
  Check(good = 5000);
end.
