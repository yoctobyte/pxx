program lib_format;
{ SysUtils.Format over an array of const.

  IT IS NOT PRINTF, and every expectation below that differs from C is the
  point of this file. Delphi's spec is

      %[index:][-][width][.prec]type

  with no '0' flag, so the leading zero of '%05d' is part of the WIDTH (pad to 5
  with SPACES) and zero-filling is what the precision does. This file used to
  assert the printf reading of '%05d' and so pinned the bug in place; every
  expectation here is now taken from FPC as the oracle
  (bug-b-format-delphi-spec-parity). }
uses sysutils;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

begin
  SayBool('int',      Format('%d', [42]) = '42');
  SayBool('width',    Format('%5d', [42]) = '   42');
  SayBool('left',     Format('%-5d|', [42]) = '42   |');
  { NOT '00042' — '05' is the width, and width padding is always spaces }
  SayBool('width-lead0', Format('%05d', [42]) = '   42');
  SayBool('prec-d',   Format('%.3d', [42]) = '042');
  SayBool('prec-d-w', Format('%8.3d', [42]) = '     042');
  { the sign stays outside the zero fill }
  SayBool('prec-neg', Format('%.5d', [-42]) = '-00042');
  SayBool('prec-zero',Format('%.3d', [0]) = '000');
  { for integers precision is a FLOOR, never a truncation (unlike %s) }
  SayBool('prec-floor', Format('%.2d', [12345]) = '12345');
  SayBool('prec-x',   Format('%.4x', [255]) = '00FF');
  SayBool('prec-x-w', Format('%8.4x', [255]) = '    00FF');
  { a 32-bit argument prints 32-bit; only an Int64 gives sixteen nibbles }
  SayBool('hex-neg32',Format('%x', [-1]) = 'FFFFFFFF');
  SayBool('hex-neg64',Format('%x', [Int64(-1)]) = 'FFFFFFFFFFFFFFFF');
  { argument index, and its cursor effect on the specifiers that follow }
  SayBool('index',    Format('%1:s-%0:s', ['a', 'b']) = 'b-a');
  SayBool('index-cont', Format('%1:s%s', ['a', 'b', 'c']) = 'bc');
  SayBool('index-width',Format('%0:8.5d|', [42]) = '   00042|');
  SayBool('index-left', Format('%1:-6s|', ['ab', 'cd']) = 'cd    |');
  SayBool('hex',      Format('%x', [255]) = 'FF');
  SayBool('str',      Format('%s', ['hi']) = 'hi');
  SayBool('str-prec', Format('%.2s', ['hello']) = 'he');
  SayBool('str-width',Format('%6s|', ['hi']) = '    hi|');
  SayBool('char',     Format('%c', [65]) = 'A');
  SayBool('percent',  Format('100%%', []) = '100%');
  SayBool('float2',   Format('%.2f', [3.14159]) = '3.14');
  SayBool('float3',   Format('%.3f', [3.14159]) = '3.142');
  SayBool('multi',    Format('%d-%s-%x', [1, 'a', 255]) = '1-a-FF');
  SayBool('mixed',    Format('[%8.2f]', [3.5]) = '[    3.50]');
end.
