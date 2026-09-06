{ The Pascal spelling of test/reclayout_cross_frontend.c's two aggregates.
  See that file's header for why the members are 1 byte then 8 and why the
  assertion is a distance rather than an offset.
  bug-a-pascal-nilpy-rust-and-zig-over-align-an-8-byte-member-on-i386 }
program reclayout_cross_frontend;
type
  BOOLD = record b: Boolean; y: Double; end;
  BYTEQ = record c: Boolean; q: Int64; end;
var u: BOOLD; v: BYTEQ;
begin
  u.b := True; u.y := 2.0;
  v.c := True; v.q := 4;
  WriteLn(Ord(u.b) + Ord(v.c));
end.
