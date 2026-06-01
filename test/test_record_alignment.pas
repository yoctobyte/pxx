program test_record_alignment;

{$PACKRECORDS 8}
type
  TDefault = record
    a: Byte;
    b: Cardinal;
  end;

  TPacked = packed record
    a: Byte;
    b: Cardinal;
  end;

{$PACKRECORDS 2}
  TAligned2 = record
    a: Byte;
    b: Cardinal;
  end;

{$PACKRECORDS 1}
  TAligned1 = record
    a: Byte;
    b: Cardinal;
  end;

{$PACKRECORDS 8}
  TNestedDefault = record
    a: Byte;
    b: TAligned2;
    c: Cardinal;
  end;

  TNestedPacked = record
    a: Byte;
    b: TPacked;
    c: Cardinal;
  end;

var
  d: TDefault;
  p: TPacked;
  a2: TAligned2;
  a1: TAligned1;
  nd: TNestedDefault;
  np: TNestedPacked;
begin
  writeln(SizeOf(TDefault));
  writeln(Int64(@d.b) - Int64(@d));

  writeln(SizeOf(TPacked));
  writeln(Int64(@p.b) - Int64(@p));

  writeln(SizeOf(TAligned2));
  writeln(Int64(@a2.b) - Int64(@a2));

  writeln(SizeOf(TAligned1));
  writeln(Int64(@a1.b) - Int64(@a1));

  writeln(SizeOf(TNestedDefault));
  writeln(Int64(@nd.b) - Int64(@nd));
  writeln(Int64(@nd.c) - Int64(@nd));

  writeln(SizeOf(TNestedPacked));
  writeln(Int64(@np.b) - Int64(@np));
  writeln(Int64(@np.c) - Int64(@np));
end.
