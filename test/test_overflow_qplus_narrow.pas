program qplus_narrow;
{ {$Q+} for SUB-64-BIT ordinal destinations (bug-a-qplus-misses-32bit-overflow).
  Integer arithmetic runs at 64-bit register width, so the binop's own flags
  check is exact and never fires for a narrow result — the wrap happens at the
  narrowing STORE, which now range-checks the value against the destination
  width. Covers Integer/Cardinal/SmallInt/Byte overflow (each raises
  EIntOverflow), an in-range op per width (no raise), and {$Q-} wrapping. }
uses sysutils;
var i32: Integer; u32: Cardinal; i16: SmallInt; u8: Byte;
    k, caught, clean: Integer;
begin
  k := 1;               { defeats constant folding }
  caught := 0; clean := 0;
  {$Q+}
  i32 := 2000000000;
  try
    i32 := i32 + 2000000000 * k;
    writeln('no-raise-i32 ', i32);
  except
    on EIntOverflow do Inc(caught);
  end;
  u32 := 4000000000;
  try
    u32 := u32 + 400000000 * Cardinal(k);
    writeln('no-raise-u32 ', u32);
  except
    on EIntOverflow do Inc(caught);
  end;
  i16 := 30000;
  try
    i16 := i16 + SmallInt(10000 * k);
    writeln('no-raise-i16 ', i16);
  except
    on EIntOverflow do Inc(caught);
  end;
  u8 := 200;
  try
    u8 := u8 + Byte(100 * k);
    writeln('no-raise-u8 ', u8);
  except
    on EIntOverflow do Inc(caught);
  end;
  i32 := 100000 * k;
  try
    i32 := i32 * 100000;
    writeln('no-raise-mul ', i32);
  except
    on EIntOverflow do Inc(caught);
  end;
  { in-range: must NOT raise }
  i32 := 1000000000; i32 := i32 + 1000000000 * k; Inc(clean);
  u32 := 2000000000; u32 := u32 + 2000000000 * Cardinal(k); Inc(clean);
  i16 := 30000; i16 := i16 + SmallInt(2000 * k); Inc(clean);
  u8 := 200; u8 := u8 + Byte(55 * k); Inc(clean);
  {$Q-}
  i32 := 2000000000;
  i32 := i32 + 2000000000 * k;   { wraps silently under Q- }
  writeln('caught=', caught, ' clean=', clean, ' wrap=', i32);
end.
