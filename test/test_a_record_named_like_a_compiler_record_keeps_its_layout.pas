{ A record that merely shares its NAME with one of the compiler's own records
  keeps the layout it DECLARES. IsRecordType mapped fourteen names to the
  compiler's builtin layouts by string compare before consulting the program's
  records, so `type TProc = record A: array[0..99] of Int64; end` was 1344
  bytes with no diagnostic (fpc: 800) -- and Delphi ships a TProc. The builtin
  is now used only when the declared record has exactly its fields.

  Each type is 800 bytes plus a Byte tail. The tail's offset is 800 in the
  declared layout and nowhere near it in any builtin one, and the last element
  of A is written and read back, so a borrowed layout shows in both columns.
  bug-a-fourteen-compiler-internal-record-names-shadow-any-user-type }
program test_a_record_named_like_a_compiler_record_keeps_its_layout;
type
  TToken = record A: array[0..99] of Int64; Tail: Byte; end;
  TStrEntry = record A: array[0..99] of Int64; Tail: Byte; end;
  TFixup = record A: array[0..99] of Int64; Tail: Byte; end;
  TGlobFix = record A: array[0..99] of Int64; Tail: Byte; end;
  TCallFix = record A: array[0..99] of Int64; Tail: Byte; end;
  TSymbol = record A: array[0..99] of Int64; Tail: Byte; end;
  TParam = record A: array[0..99] of Int64; Tail: Byte; end;
  TProc = record A: array[0..99] of Int64; Tail: Byte; end;
  TRawToken = record A: array[0..99] of Int64; Tail: Byte; end;
  TTemplate = record A: array[0..99] of Int64; Tail: Byte; end;
  TSpecialization = record A: array[0..99] of Int64; Tail: Byte; end;
  TGenericFunc = record A: array[0..99] of Int64; Tail: Byte; end;
  TPendingGFSpec = record A: array[0..99] of Int64; Tail: Byte; end;
  TMethodFixup = record A: array[0..99] of Int64; Tail: Byte; end;
var
  v0: TToken;
  v1: TStrEntry;
  v2: TFixup;
  v3: TGlobFix;
  v4: TCallFix;
  v5: TSymbol;
  v6: TParam;
  v7: TProc;
  v8: TRawToken;
  v9: TTemplate;
  v10: TSpecialization;
  v11: TGenericFunc;
  v12: TPendingGFSpec;
  v13: TMethodFixup;
begin
  v0.A[99] := 1000; v0.Tail := 1;
  WriteLn('TToken ', PtrUInt(@v0.Tail) - PtrUInt(@v0), ' ', v0.A[99], ' ', v0.Tail);
  v1.A[99] := 1001; v1.Tail := 2;
  WriteLn('TStrEntry ', PtrUInt(@v1.Tail) - PtrUInt(@v1), ' ', v1.A[99], ' ', v1.Tail);
  v2.A[99] := 1002; v2.Tail := 3;
  WriteLn('TFixup ', PtrUInt(@v2.Tail) - PtrUInt(@v2), ' ', v2.A[99], ' ', v2.Tail);
  v3.A[99] := 1003; v3.Tail := 4;
  WriteLn('TGlobFix ', PtrUInt(@v3.Tail) - PtrUInt(@v3), ' ', v3.A[99], ' ', v3.Tail);
  v4.A[99] := 1004; v4.Tail := 5;
  WriteLn('TCallFix ', PtrUInt(@v4.Tail) - PtrUInt(@v4), ' ', v4.A[99], ' ', v4.Tail);
  v5.A[99] := 1005; v5.Tail := 6;
  WriteLn('TSymbol ', PtrUInt(@v5.Tail) - PtrUInt(@v5), ' ', v5.A[99], ' ', v5.Tail);
  v6.A[99] := 1006; v6.Tail := 7;
  WriteLn('TParam ', PtrUInt(@v6.Tail) - PtrUInt(@v6), ' ', v6.A[99], ' ', v6.Tail);
  v7.A[99] := 1007; v7.Tail := 8;
  WriteLn('TProc ', PtrUInt(@v7.Tail) - PtrUInt(@v7), ' ', v7.A[99], ' ', v7.Tail);
  v8.A[99] := 1008; v8.Tail := 9;
  WriteLn('TRawToken ', PtrUInt(@v8.Tail) - PtrUInt(@v8), ' ', v8.A[99], ' ', v8.Tail);
  v9.A[99] := 1009; v9.Tail := 10;
  WriteLn('TTemplate ', PtrUInt(@v9.Tail) - PtrUInt(@v9), ' ', v9.A[99], ' ', v9.Tail);
  v10.A[99] := 1010; v10.Tail := 11;
  WriteLn('TSpecialization ', PtrUInt(@v10.Tail) - PtrUInt(@v10), ' ', v10.A[99], ' ', v10.Tail);
  v11.A[99] := 1011; v11.Tail := 12;
  WriteLn('TGenericFunc ', PtrUInt(@v11.Tail) - PtrUInt(@v11), ' ', v11.A[99], ' ', v11.Tail);
  v12.A[99] := 1012; v12.Tail := 13;
  WriteLn('TPendingGFSpec ', PtrUInt(@v12.Tail) - PtrUInt(@v12), ' ', v12.A[99], ' ', v12.Tail);
  v13.A[99] := 1013; v13.Tail := 14;
  WriteLn('TMethodFixup ', PtrUInt(@v13.Tail) - PtrUInt(@v13), ' ', v13.A[99], ' ', v13.Tail);
end.
