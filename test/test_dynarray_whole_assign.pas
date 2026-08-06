program test_dynarray_whole_assign;
{ Regression: `b := a` on a DYNAMIC array must produce a usable array — correct
  Length, readable elements, and no crash — for plain and managed element types,
  as a local, as a global, and through a function.

  arm32 and riscv32 had no dynamic-array arm in IR_STORE_SYM at all, so the
  store fell through to the scalar path and published the wrong one of IR_LEA's
  read/write results; `Length(b)` then dereferenced garbage and segfaulted.
  That killed lib_zlib and, through it, lib_png.
  bug-a-arm32-dynamic-array-assignment-has-no-store-arm.

  It NOW ALSO asserts aliasing, which it deliberately did not when it was
  written: dynamic arrays are reference types in FPC/Delphi, so `b := a` makes
  the two names one array and a write through either is visible through the
  other. x86-64 used to copy-on-write instead, silently, and alone among the
  targets; that is fixed
  (bug-a-x86-64-dynarray-assignment-copies-instead-of-aliasing, direction settled
  by decide-dynamic-array-value-vs-reference-semantics). Every assertion below
  was diffed against an FPC build of this same file. }
type TByteArray = array of Byte;
var
  gData: TByteArray;

function Peek(i: Integer): Integer;
begin Peek := gData[i]; end;

procedure LocalToLocal;
var a, b: array of Byte;
begin
  SetLength(a, 8); a[3] := 42; a[7] := 7;
  b := a;
  writeln(Length(b), ' ', b[3], ' ', b[7]);
end;

procedure ManagedElems;
var s, t: array of string;
begin
  SetLength(s, 3);
  s[0] := 'p'; s[1] := 'q'; s[2] := 'r';
  SetLength(t, 1); t[0] := 'old';   { destination already holds a handle }
  t := s;
  writeln(Length(t), ' ', t[0], t[1], t[2]);
  t := t;                            { self-assign must not destroy it }
  writeln(Length(t), ' ', t[0], t[1], t[2]);
end;

{ ALIASING — the actual semantics, in both directions. A write through the
  SECOND name must be visible through the first and vice versa, because there is
  only one array. This is what silently did nothing on x86-64. }
procedure Aliases;
var a, b: array of Integer;
begin
  SetLength(a, 3); a[0] := 1; a[1] := 2; a[2] := 3;
  b := a;
  b[0] := 77;                        { write through B, read through A }
  a[1] := 88;                        { write through A, read through B }
  writeln(a[0], ' ', b[0], ' ', a[1], ' ', b[1]);   { 77 77 88 88 }
end;

{ …and at DEPTH. The nested clone was a separate site per backend, so the flat
  case passing says nothing about this one — arm32 still detached after x86-64
  was fixed. }
procedure AliasesNested;
var a, b: array of array of Integer;
    i: Integer;
begin
  SetLength(a, 2);
  for i := 0 to 1 do begin SetLength(a[i], 2); a[i][0] := i; a[i][1] := i * 10; end;
  b := a;
  b[0][0] := 77;
  a[1][1] := 88;
  writeln(a[0][0], ' ', b[0][0], ' ', a[1][1], ' ', b[1][1]);  { 77 77 88 88 }
end;

{ MANAGED element type: aliasing must not depend on the element being a plain
  scalar, and the string refcounting must survive the shared write. }
procedure AliasesManaged;
var s, t: array of string;
begin
  SetLength(s, 2); s[0] := 'a'; s[1] := 'b';
  t := s;
  t[0] := 'zz';
  writeln(s[0], ' ', t[0], ' ', s[1], ' ', t[1]);   { zz zz b b }
end;

{ SetLength DETACHES, which is FPC too and is the one place a copy still
  happens — it is also why Copy(a) had to land first as the explicit way to ask
  for a duplicate. }
procedure SetLengthDetaches;
var a, b: array of Integer;
begin
  SetLength(a, 2); a[0] := 1;
  b := a;
  SetLength(b, 3);                   { b is now its own array }
  b[0] := 9;
  writeln(a[0], ' ', b[0], ' ', Length(a), ' ', Length(b));  { 1 9 2 3 }
end;

{ Copy() is the escape hatch: an explicit duplicate does NOT alias. }
procedure CopyDetaches;
var a, b: array of Integer;
begin
  SetLength(a, 2); a[0] := 1;
  b := Copy(a);
  b[0] := 9;
  writeln(a[0], ' ', b[0]);          { 1 9 }
end;

var s: TByteArray;
begin
  LocalToLocal;
  ManagedElems;
  SetLength(s, 8); s[3] := 42;
  gData := s;                        { global := local }
  writeln(Length(gData), ' ', gData[3], ' ', Peek(3));
  Aliases;
  AliasesNested;
  AliasesManaged;
  SetLengthDetaches;
  CopyDetaches;
  writeln('OK');
end.
