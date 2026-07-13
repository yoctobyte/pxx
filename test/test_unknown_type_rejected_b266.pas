program test_unknown_type_rejected_b266;
{ An UNKNOWN type name is now an ERROR. It used to become a 4-byte Integer, silently:

    var x: Integr;                 { a typo — compiled }
    var p: PSomethingUndeclared;   { a pointer — TRUNCATED every address stored in it }
    var b: Integer absolute a;     { `absolute` + its target parsed as "types" -> ignored }

  That one fallback produced, over time: TObject truncation, TClass truncation, Int8/Int16
  silently 4 bytes, AnsiChar silently 4 bytes, and `absolute` silently ignored — each found
  and patched ONE AT A TIME (bug-pascal-unknown-type-silently-integer).

  The fallback was only ever legitimately needed in ONE place: the ELEMENT of a `^`, where
  a forward reference is legal and ResolvePendingPointerAliases fixes it up afterwards by
  name. That case is preserved and pinned here; everything else now errors.

  This file is the POSITIVE half (what must still compile). The negative half — that a
  typo'd name is rejected — is checked in the Makefile, since it must fail to compile. }
type
  { the one legitimate forward reference: PNode names TNode before TNode exists }
  PNode = ^TNode;
  TNode = record
    v: Integer;
    next: PNode;
  end;

  { a named dynamic-array type lives in its own table, not the alias table }
  TByteArr = array of Byte;

var
  a, b: TNode;
  p: PNode;
  arr: TByteArr;
  c: AnsiChar;          { was silently a 4-byte Integer }
  s: Int16;             { likewise }
begin
  a.v := 1;
  b.v := 2;
  a.next := @b;
  p := @a;
  writeln('fwd-ptr=', p^.v, ' ', p^.next^.v);

  SetLength(arr, 3);
  arr[2] := 7;
  writeln('named-dynarray=', Length(arr), ' ', arr[2]);

  c := 'x';
  writeln('ansichar=', c, ' size=', SizeOf(c));
  s := 30000;
  writeln('int16=', s, ' size=', SizeOf(s));
end.
