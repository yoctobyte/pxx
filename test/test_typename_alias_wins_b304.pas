{ A source (or RTL) type ALIAS must beat the built-in type NAME of the same name.

  ParseTypeKind carries a chain of ~37 built-in names (widechar, tdatetime, currency, valreal,
  comp, sizeint, the string aliases, the P-pointer names, ...). That chain ran BEFORE the alias
  table -- which is only reached in its final `else` -- so a builtin SILENTLY WON over a program's
  own declaration. A comment inside the chain claimed the opposite; it was wrong.

  Latent for most of them, because nobody redeclares `widechar`. FATAL the moment the pointer
  names were added (b303): THIS COMPILER declares `PWord = ^NativeInt` (the machine word), and a
  builtin `PWord = ^UInt16` re-typed it -- `pw^` read two bytes instead of eight.

  Every branch in the chain is now guarded on "no alias of this name exists". Guarding (rather
  than reordering) can only ever make an alias WIN, never the reverse: the class, record and alias
  handling in the final `else` stays reachable exactly as it was.

  Each line below redeclares a builtin name as a DIFFERENT type and checks it got its own. }
program test_typename_alias_wins_b304;
type
  { redeclare builtin NAMES -- the source must win, in every case }
  TDateTime = Int64;        { builtin: Double }
  Currency  = Integer;      { builtin: Double }
  ValReal   = Single;       { builtin: Double }
  Comp      = Integer;      { builtin: Int64 }
  WideChar  = Byte;         { builtin: UInt16 }
  SizeInt   = Int16;        { builtin: NativeInt }
var
  a: TDateTime;
  b: Currency;
  c: ValReal;
  d: Comp;
  e: WideChar;
  f: SizeInt;
begin
  writeln('TDateTime=', SizeOf(a), ' (8, as Int64)');
  writeln('Currency =', SizeOf(b), ' (4)');
  writeln('ValReal  =', SizeOf(c), ' (4)');
  writeln('Comp     =', SizeOf(d), ' (4)');
  writeln('WideChar =', SizeOf(e), ' (1)');
  writeln('SizeInt  =', SizeOf(f), ' (2)');
end.
