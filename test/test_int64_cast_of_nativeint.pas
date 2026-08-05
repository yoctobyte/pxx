program test_int64_cast_of_nativeint;
{ Regression: the EXPLICIT cast `Int64(n)` where n is NativeInt/NativeUInt must
  sign/zero-EXTEND on 32-bit targets, not reinterpret 8 bytes at a 4-byte
  location. The "is the source already 64 bits?" guard listed tyNativeInt /
  tyNativeUInt unconditionally, which only holds on a 64-bit target — so on
  i386/arm32/riscv32 the widen was skipped and the high half came from whatever
  sat next in storage. Int64(5) read 4294967301.

  The IMPLICIT conversion (q := n) never went through that path and stayed
  correct, which is why this hid: the broken spelling is the one used when
  someone is deliberately forcing 64-bit arithmetic, i.e. right before a
  multiply that amplifies it. C's clock() returned a huge random number with a
  NEGATIVE delta between successive calls.
  bug-a-explicit-int64-cast-of-nativeint-does-not-extend-on-32bit. }
type TSpec = record Sec: NativeInt; Nsec: NativeInt; end;
var n: NativeInt; u: NativeUInt; q: Int64; ts: TSpec; p: Pointer;
begin
  n := 5;    writeln(Int64(n));            { 5 }
  n := -3;   writeln(Int64(n));            { -3 }
  q := n;    writeln(q);                   { -3 — the implicit form, always ok }
  u := 7;    writeln(Int64(u));            { 7 }
  writeln(Int64(u) * 1000000);             { 7000000 — the amplifying shape }

  { record fields, the shape __pxx_clock actually uses }
  ts.Sec := 1234; ts.Nsec := 567890000;
  writeln(Int64(ts.Sec) * 1000000 + Int64(ts.Nsec) div 1000);   { 1234567890 }

  { a POINTER cast must stay unaffected — the PAL passes syscall addresses
    this way, and its high half was already correct }
  p := @n;
  writeln(Ord(Int64(p) <> 0));             { 1 }
  writeln('OK');
end.
