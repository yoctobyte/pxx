program test_a_builtin_type_name_is_redeclared;
{$mode objfpc}{$H+}
{ `type Integer = Int64;` -- the portability-unit idiom, a compat header pinning
  a width the dialect leaves open. It did not COMPILE: `expected 'begin' before
  'Integer'`, because Integer lexes as tkInteger_T and the type-declaration
  parser wants an identifier.

  NINE names lex as a type keyword and were refused; `string` is the tenth and
  is refused by fpc 3.2.2 TOO, so it is a genuine reserved word and the boundary
  is exact. THE `string` ROW IS NOT IN THIS FILE because a program that must
  fail to compile cannot share one with programs that must run. It is a
  one-line check and it must stay green:

      printf 'program s;\ntype string = Int64;\nbegin end.\n' > /tmp/s.pas
      ./compiler/pascal26 /tmp/s.pas /tmp/sx     # must ERROR, as fpc does

  ROW 8 IS THE CONTROL THAT MATTERS and it is not about redeclaration at all.
  `byte` and `integer` are ONE token kind (tkInteger_T, paslexer.inc), so a fix
  keyed on the KIND rather than the SPELLING redefines Byte as Int64 here too --
  a second type silently changing width from a declaration that never named it.
  Row 8 is the row that catches that, and every other row in this file passes
  while it is broken.

  Rows 1-2 and 5 are the three doors the ticket required to move TOGETHER: the
  name, a variable of it, and a cast to it. Two of the three moving is a type
  declaration that silently does not apply -- worse than the loud refusal it
  replaced. Rows 3, 4, 6 and 7 are there because SizeOf can report a width the
  program does not actually use: they store and read back a value no 32-bit
  Integer can hold.

  Byte-identical to fpc 3.2.2 on all nine rows, and on i386 / aarch64 / arm32 /
  riscv32 under qemu.
  compat-p-nine-builtin-type-names-cannot-be-redeclared-at-all }
type
  Integer = Int64;
  Char    = WideChar;
  TRec = record f: Integer; end;
function Twice(x: Integer): Integer;
begin Twice := x * 2; end;
var
  v: Integer;
  r: TRec;
  c: Char;
  b: Byte;
  a: array[0..2] of Integer;
begin
  v := 5000000000;
  r.f := v + 1;
  c := 'A';
  b := 255;
  a[2] := v div 2;
  WriteLn('1 sizeof name    ', SizeOf(Integer), ' ', SizeOf(Char));
  WriteLn('2 sizeof var     ', SizeOf(v), ' ', SizeOf(c));
  WriteLn('3 value survives ', v);
  WriteLn('4 field          ', r.f, ' ', SizeOf(r));
  WriteLn('5 cast           ', SizeOf(Integer(1)), ' ', Integer(v) div 1000);
  WriteLn('6 function       ', Twice(v));
  WriteLn('7 array elem     ', a[2], ' ', SizeOf(a));
  WriteLn('8 byte untouched ', SizeOf(Byte), ' ', b);
  WriteLn('9 ord of wide    ', Ord(c));
end.
