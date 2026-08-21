program test_variant_conversion_failure_is_catchable;
{ A failed Variant conversion must RAISE, not kill the process.

  `try i := v; except ... end` is the whole reason that try is written: the
  text may not be numeric. FPC raises EVariantError and the handler runs; pxx
  used to print "Runtime error: EVariantError, ..." from inside the builtin
  conversion helper and Halt(219) — so the handler was unreachable and the
  program died at the first bad input.

  The helpers live in the builtin units, which have no exception class to
  raise; sysutils installs PXXVariantErrorHook at startup, exactly as it
  already did for div-by-zero, overflow, range, I/O and nil-reference. A
  program without sysutils keeps the print-and-halt behaviour.

  bug-a-variant-conversion-failure-is-uncatchable }

uses SysUtils;

var
  v: Variant;
  i: Integer;
  d: Double;
  b: Boolean;
  s: AnsiString;

function IntOf(const x: Variant): AnsiString;
var n: Integer;
begin
  try
    n := x;
    IntOf := IntToStr(n);
  except
    on e: EVariantError do IntOf := 'EVariantError';
    on e: Exception do IntOf := 'other:' + e.ClassName;
  end;
end;

begin
  { the value cases still convert }
  v := '42';   WriteLn(IntOf(v));                  { 42 }
  v := 7;      WriteLn(IntOf(v));                  { 7 }

  { ...and the failures are catchable, by the specific class }
  v := 'abc';  WriteLn(IntOf(v));                  { EVariantError }
  v := '';     WriteLn(IntOf(v));                  { EVariantError }

  { caught as plain Exception too — EVariantError descends from it, which is
    what ordinary code writes }
  v := 'nope';
  try
    i := v;
    WriteLn('NOT REACHED ', i);
  except
    on e: Exception do WriteLn('exc ', e.ClassName);
  end;

  { float and boolean take the same path }
  v := 'zz';
  try
    d := v;
    WriteLn('NOT REACHED ', d:0:1);
  except
    on e: EVariantError do WriteLn('float raised');
  end;

  v := 'zz';
  try
    b := v;
    WriteLn('NOT REACHED ', b);
  except
    on e: EVariantError do WriteLn('bool raised');
  end;

  { the message survives the hand-off, so the diagnostic is not lost }
  v := 'abc';
  s := '';
  try
    i := v;
  except
    on e: EVariantError do s := e.Message;
  end;
  { The last line is the one place FPC and pxx differ, and only in WORDING:
    FPC says "Invalid variant type cast", pxx names the actual conversion.
    Every other line above is byte-identical to fpc 3.2.2 on this source. }
  WriteLn(s);                                      { cannot convert string to integer }

  WriteLn('still alive');
end.
