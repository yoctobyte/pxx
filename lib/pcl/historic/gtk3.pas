{ SPDX-License-Identifier: Zlib }
unit gtk3;

{ Thin hand-written binding to libgtk-3.so.0 / libc.

  Not a generated header import — GTK's real headers are glib-macro soup the
  C importer can't digest. We declare only the symbols the GUI layer calls,
  as Pascal `external` routines. GtkWidget*/GObject* etc. are opaque Pointer.

  Calling convention is cdecl (System V AMD64), which the external call path
  already uses. }

interface

type
  PGtkWidget = Pointer;

const
  GTK_WINDOW_TOPLEVEL = 0;

  { GtkMessageType }
  GTK_MESSAGE_INFO     = 0;
  GTK_MESSAGE_WARNING  = 1;
  GTK_MESSAGE_QUESTION = 2;
  GTK_MESSAGE_ERROR    = 3;
  { GtkButtonsType }
  GTK_BUTTONS_NONE  = 0;
  GTK_BUTTONS_OK    = 1;
  { GtkDialogFlags }
  GTK_DIALOG_MODAL              = 1;
  GTK_DIALOG_DESTROY_WITH_PARENT = 2;

{ --- lifecycle --- }
procedure gtk_init(argc: Pointer; argv: Pointer); cdecl; external 'libgtk-3.so.0';
function  gtk_get_major_version: Integer; cdecl; external 'libgtk-3.so.0';
function  gtk_get_minor_version: Integer; cdecl; external 'libgtk-3.so.0';
function  gtk_get_micro_version: Integer; cdecl; external 'libgtk-3.so.0';

{ --- event loop --- }
procedure gtk_main; cdecl; external 'libgtk-3.so.0';
procedure gtk_main_quit; cdecl; external 'libgtk-3.so.0';
function  gtk_events_pending: Integer; cdecl; external 'libgtk-3.so.0';
function  gtk_main_iteration_do(blocking: Integer): Integer; cdecl; external 'libgtk-3.so.0';

{ --- signals (GObject / GLib) --- }
function  g_signal_connect_data(instance: Pointer; signal: PChar; handler: Pointer;
                                data: Pointer; destroy: Pointer; flags: Integer): LongWord;
            cdecl; external 'libgobject-2.0.so.0';
function  g_timeout_add(interval: LongWord; func: Pointer; data: Pointer): LongWord;
            cdecl; external 'libglib-2.0.so.0';

{ --- widgets --- }
function  gtk_window_new(wtype: Integer): PGtkWidget; cdecl; external 'libgtk-3.so.0';
procedure gtk_window_set_title(window: PGtkWidget; title: PChar); cdecl; external 'libgtk-3.so.0';
procedure gtk_window_set_default_size(window: PGtkWidget; w: Integer; h: Integer); cdecl; external 'libgtk-3.so.0';
function  gtk_button_new_with_label(label_: PChar): PGtkWidget; cdecl; external 'libgtk-3.so.0';
procedure gtk_button_set_label(button: PGtkWidget; label_: PChar); cdecl; external 'libgtk-3.so.0';
procedure gtk_button_clicked(button: PGtkWidget); cdecl; external 'libgtk-3.so.0';
procedure gtk_container_add(container: PGtkWidget; widget: PGtkWidget); cdecl; external 'libgtk-3.so.0';
procedure gtk_widget_show_all(widget: PGtkWidget); cdecl; external 'libgtk-3.so.0';
procedure gtk_widget_destroy(widget: PGtkWidget); cdecl; external 'libgtk-3.so.0';

{ --- dialogs ---
  gtk_message_dialog_new is variadic; we bind a fixed prototype that always
  passes a "%s" format plus one message string, so arbitrary message text
  (incl. % chars) is shown literally. The external-call path sets al=0. }
function  gtk_message_dialog_new(parent: PGtkWidget; flags: Integer;
                                 mtype: Integer; buttons: Integer;
                                 fmt: PChar; msg: PChar): PGtkWidget;
            cdecl; external 'libgtk-3.so.0';
function  gtk_dialog_run(dialog: PGtkWidget): Integer; cdecl; external 'libgtk-3.so.0';

{ --- libc --- }
function  usleep(usec: LongWord): Integer; cdecl; external 'libc.so.6';

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
