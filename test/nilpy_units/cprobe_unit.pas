unit cprobe_unit;
{ Pulls a C source, which pulls crtl and with it every name crtl's headers
  declare — `atexit` among them. Exists so a NilPy test can prove that those
  names do not shadow Python module qualifiers. }

interface

uses pxxcio, './cprobe_c.c';

function cprobe_value: Integer;

implementation

function cprobe_value: Integer;
begin
  cprobe_value := cprobe_add(40, 2);
end;

end.
