{ SPDX-License-Identifier: Zlib }
unit gtk3;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Thin hand-written binding to libgtk-3.so.0 / libc, now backed by direct C header import. }

interface

uses gtk3_c;

{ g_signal_connect(obj, signal, handler) — the macro from gtk; forwards to
  g_signal_connect_data with no closure data/notify and default flags. }
function SignalConnect(obj: Pointer; signal: AnsiString; handler: Pointer): LongWord;

{ Same, but passes a user-data pointer delivered as the handler's last arg. }
function SignalConnectData(obj: Pointer; signal: AnsiString; handler: Pointer; data: Pointer): LongWord;

{ The `const char*` for a Pascal string, as a pass-through: no copy, no
  buffer, no shared state. A managed string's own bytes ARE a valid C string
  (builtinheap.pas:2386 allocates PXX_HDR_SIZE + len + 1 and stores the NUL,
  for every string, not only for literals), and PChar() of the empty string —
  whose handle is nil — routes through PXXPCharOf onto a shared read-only #0
  byte, so an empty AnsiString arrives as a pointer to "" and never as NULL.
  That empty case is the one job the old copying version did that a naive
  `@s[1]` cannot; the language does it here.

  It was a four-slot static ring until 2026-09-14, which had two bugs the ring
  made unavoidable: a string of 1024 chars wrote its NUL past the array, and
  ANY call taking more than four PChar arguments silently reused a slot its
  caller still held. Deleting the copy deletes both, and makes PC() reentrant
  and thread-safe as a side effect.
  bug-b-gtk3-pc-writes-past-its-buffer-on-a-long-string }
function PC(const s: AnsiString): Pointer;

implementation

function PC(const s: AnsiString): Pointer;
begin
  PC := PChar(s);
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
