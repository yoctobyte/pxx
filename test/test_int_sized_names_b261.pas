program test_int_sized_names_b261;
{ Int8 / Int16 / Int32 and TClass were NOT recognised type names. They fell through to the
  unknown-name default, which silently yields a 4-byte Integer:

    Int8  -> 4 bytes (should be 1)
    Int16 -> 4 bytes (should be 2)
    Int32 -> 4 bytes (right, by luck)
    TClass-> 4 bytes — a CLASS REFERENCE truncated to 32 bits

  UInt8/16/32/64 were all present; only the signed spellings were missing. The wrong sizes
  also mislay any record the fields sit in.

  In pxx a class reference is the address of the class RTTI blob, so TClass is
  pointer-sized with a tyClass element — the same shape TObject already had.

  The unknown-name default that hid all this is filed separately as
  bug-pascal-unknown-type-silently-integer; it is still there, and it is why a typo'd type
  name still compiles. }
type
  TPub = class
  published
    procedure Ping;
  end;

  TRec = record
    a: Int8;
    b: Int16;
    c: Int32;
    d: Int64;
  end;
procedure TPub.Ping;
begin
end;

var
  r: TRec;
  k: TClass;
  o: TObject;
begin
  writeln('Int8=', SizeOf(r.a));
  writeln('Int16=', SizeOf(r.b));
  writeln('Int32=', SizeOf(r.c));
  writeln('Int64=', SizeOf(r.d));
  writeln('TClass=', SizeOf(k));      { pointer-sized, or a class ref truncates }
  writeln('TObject=', SizeOf(o));

  { they must actually hold their range }
  r.b := 30000;
  writeln('int16-val=', r.b);
  r.a := -128;
  writeln('int8-val=', r.a);

  { a class reference must survive a round trip }
  k := TPub;
  writeln('classref-nonnil=', Pointer(k) <> nil);
end.
