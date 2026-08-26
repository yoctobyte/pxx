{ `String(x)` in cast position is a TYPECAST, not the char->string conversion.

  `String` is a KEYWORD token (tkString_T) with its own branch in the factor
  parser, so it never reached the identifier-cast path that serves `ansistring`
  and the rest. That branch ended in an error, so every operand kind the
  conversions above it did not claim was rejected -- while every other cast
  target accepted the same expression:

    Integer(p^)  PtrUInt(p^)  Pointer(p^)  TObject(p^)  AnsiString(p^)   compile
    String(p^)                                                          error

  That is fgl.pp's `T(FList.Items[i]^)` exactly, so it took out every
  string-instantiated FPC container.

  The conversions stay conversions: a Char, a managed string and a Variant are
  answered before the cast, and the char rows below are here to prove the fix did
  not swallow them -- `String(c)` must still produce a one-character STRING and
  not reinterpret the char's bits.

  Every row measured against fpc 3.2.2 (-Mobjfpc -O1), except the two noted
  below, which fpc REJECTS and pxx accepts: the identifier path already accepted
  `AnsiString(i)`, and the two spellings disagreeing was the defect. Accepting a
  form fpc rejects is not one -- see the FPC-parity ceiling in CLAUDE.md. }
program test_string_typecast_is_a_cast;
{$mode objfpc}
type
  PStr = ^string;
  generic TBox<T> = class
    function Get(p: Pointer): T;
  end;
  TStrBox = specialize TBox<string>;
  TIntBox = specialize TBox<Integer>;

function TBox.Get(p: Pointer): T;
begin Result := T(p^); end;

var
  s: string; a: AnsiString; p: Pointer; ps: PStr; c: Char;
  blk: Pointer; i: Integer;
  sb: TStrBox; ib: TIntBox;
begin
  { the cast that was rejected: a deref of an UNTYPED pointer }
  s := 'hey'; p := @s;
  WriteLn('cast   [', String(p^), ']');
  { NOT asserted: `AnsiString(p^)` on the same operand. pxx prints `hey`; fpc
    3.2.2 compiles it and then dies with runtime error 216, so there is no oracle
    row to pin. The `String` spelling is the one this ticket is about and the one
    fgl writes. }
  WriteLn('len ', Length(String(p^)));

  { ...through a raw block, which is the shape fgl uses }
  blk := GetMem(4 * SizeOf(Pointer));
  FillChar(blk^, 4 * SizeOf(Pointer), 0);
  ps := PStr(blk); ps^ := 'alpha';
  p := blk;
  WriteLn('block  [', String(p^), '] ', Length(String(p^)));

  { ...and through a generic type parameter, which is how library code reaches
    it. The Integer instantiation is here because it always worked: it is what
    says the generic machinery was never the problem. }
  sb := TStrBox.Create; ib := TIntBox.Create;
  s := 'boxed'; i := 99;
  WriteLn('generic ', sb.Get(@s), ' ', ib.Get(@i));

  { the CONVERSIONS the cast must not have swallowed }
  c := 'q';
  WriteLn('char   [', String(c), '] ', Length(String(c)));
  a := 'kept'; WriteLn('str    [', String(a), ']');
end.
