{ A typecast of a VARIANT is the CONVERSION, not a reinterpret of the record --
  and WideChar was the one character kind the conversion did not know about.

  `IRVariantUnboxKind` (symtab.inc) lists the kinds a variant payload may be
  unboxed into. It was written when a WideChar variable was tyUInt16, which the
  list names; the fix that gave WideChar its OWN kind took it out of the list
  without touching the list, and nothing failed loudly -- the cast simply fell
  out of the unbox and reinterpreted the variant RECORD, so

      v := 'A';  w := WideChar(v)

  answered 5 (a field of the record) against fpc 3.2.2's 65. Measured on pin
  v404 too, so it is not new.

  EVERY ROW HERE HOLDS A CHARACTER IN THE VARIANT, deliberately. pxx unboxes a
  NUMERIC variant arithmetically (`v := 233; Char(v)` -> 233) while fpc
  stringifies it first (-> '2', 50). That divergence is older than this fix,
  applies to `Char` exactly as much as to `WideChar`, and is a separate
  question about Variant->character semantics; pinning it here would make this
  test about that instead.

  The `Char` rows are the CONTROL: they went through the same predicate and
  always worked, so a regression that breaks the shared list shows up as both
  columns moving rather than one. .expected is fpc 3.2.2's own output. }
program test_a_variant_cast_to_widechar_converts_like_char;
{$mode delphi}
var
  v: Variant;
  w: WideChar;
  c: Char;
  s: string;
begin
  v := 'A';   w := WideChar(v);  WriteLn('wide  one-char   ', Ord(w));
  v := 'A';   c := Char(v);      WriteLn('char  one-char   ', Ord(c));
  v := 'AB';  w := WideChar(v);  WriteLn('wide  two-char   ', Ord(w));
  v := 'AB';  c := Char(v);      WriteLn('char  two-char   ', Ord(c));
  v := 'z';   w := WideChar(v);  WriteLn('wide  lower      ', Ord(w));
  v := 'z';   c := Char(v);      WriteLn('char  lower      ', Ord(c));

  { the string context: the UTF-16 code unit becomes its UTF-8 bytes, and this
    is the path the deleted -3 marker used to claim to be the only evidence for.
    ASTTk = tyWideChar carries it. }
  v := 'A';   s := 'x' + WideChar(v);
  WriteLn('wide  in-string  ', Length(s), ' ', s);

  WriteLn('VARIANT WIDECHAR OK');
end.
