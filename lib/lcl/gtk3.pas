unit gtk3;

{ Thin hand-written binding to libgtk-3.so.0 / libc, now backed by direct C header import. }

interface

uses gtk3_c;

{ g_signal_connect(obj, signal, handler) — the macro from gtk; forwards to
  g_signal_connect_data with no closure data/notify and default flags. }
function SignalConnect(obj: Pointer; signal: AnsiString; handler: Pointer): LongWord;

{ Same, but passes a user-data pointer delivered as the handler's last arg. }
function SignalConnectData(obj: Pointer; signal: AnsiString; handler: Pointer; data: Pointer): LongWord;

{ Convert a Pascal string to a transient NUL-terminated C string. The
  Pascal string value is a pointer to an 8-byte length prefix followed by
  the chars, with no guaranteed NUL — so C calls cannot use it directly.
  GTK copies title/label strings immediately, so one shared static buffer
  reused per call is safe (calls are sequential). }
function PC(const s: AnsiString): Pointer;

implementation

var
  { Ring of buffers so several transient C strings can be live at once
    (e.g. a "%s" format plus its argument in the same call). }
  CBuf: array[0..4095] of Char;
  CBufSlot: Integer;

function PC(const s: AnsiString): Pointer;
var i, base: Integer;
begin
  base := CBufSlot * 1024;
  for i := 1 to Length(s) do
    CBuf[base + i-1] := s[i];
  CBuf[base + Length(s)] := #0;
  PC := @CBuf[base];
  CBufSlot := CBufSlot + 1;
  if CBufSlot >= 4 then CBufSlot := 0;
end;

function SignalConnect(obj: Pointer; signal: AnsiString; handler: Pointer): LongWord;
begin
  SignalConnect := g_signal_connect_data(obj, PC(signal), handler, nil, nil, 0);
end;

function SignalConnectData(obj: Pointer; signal: AnsiString; handler: Pointer; data: Pointer): LongWord;
begin
  SignalConnectData := g_signal_connect_data(obj, PC(signal), handler, data, nil, 0);
end;

end.
