program lib_format;
{ Smoke for SysUtils.Format (printf-style over array of const). }
uses sysutils;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

begin
  SayBool('int',      Format('%d', [42]) = '42');
  SayBool('width',    Format('%5d', [42]) = '   42');
  SayBool('left',     Format('%-5d|', [42]) = '42   |');
  SayBool('zeropad',  Format('%05d', [42]) = '00042');
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
