{ Val's `v` and `code` are var parameters of fixed widths (Int64/QWord/Double
  and Integer); FPC's Val takes any width for both. A narrower actual was
  overrun: pin v423 prints `65535 0 0` for the record row (the neighbouring
  field g, 333, zeroed by a 4-byte `code` write... and an 8-byte `v` write
  into a Word) and `0.00` for a Single destination. lib/rtl/charset.pas's own
  `Val(hs, charpos, code)` with `code: Word` was one of these. Expected output
  is fpc 3.2.2's. bug-p-a-var-parameter-accepts-a-narrower-actual-and-writes-past-it }
program test_val_writes_each_argument_at_its_own_width;
type TR = record w: Word; g: Word; end;
var g1: LongInt; code: Word; g2: LongInt; v: LongInt; b: Byte; sm: SmallInt;
    r: TR; sg: Single; d: Double; c64: Int64; q: QWord; ci: Integer;
begin
  g1 := 111; g2 := 222; r.g := 333;
  Val('$1F', v, code); writeln(v, ' ', code, ' ', g1, ' ', g2);
  Val('12x', v, code); writeln(v, ' ', code);
  Val('200', b, ci); writeln(b, ' ', ci);
  Val('-300', sm, c64); writeln(sm, ' ', c64);
  Val('65535', r.w, code); writeln(r.w, ' ', r.g, ' ', code);
  Val('1.5', sg, code); writeln(sg:0:2, ' ', code);
  Val('2.25', d, ci); writeln(d:0:2, ' ', ci);
  Val('18446744073709551615', q, code); writeln(q, ' ', code);
  Val('7', v); writeln(v);
end.
