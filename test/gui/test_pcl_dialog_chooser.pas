program test_pcl_dialog_chooser;

{ dialogs.TOpenDialog / TSaveDialog / TSelectDirectoryDialog over a real
  GtkFileChooserDialog.

  WHAT MAKES THIS A GUARD AND NOT A PASS-PRINTER. The obvious test -- open a
  chooser, dismiss it, assert Execute returned False -- CANNOT FAIL: a
  widgetset with no chooser at all returns '' from the seam, so False is also
  what "nothing happened" produces. Every row below is therefore about the
  widget that was actually built: its GtkFileChooser ACTION, and the filters
  the Delphi-shaped filter string parsed into. A no-op backend maps no window
  and this prints `saw=none`.

  The nested gtk_dialog_run loop is escaped the same way test_pcl_showmessage
  escapes it -- from a g_timeout. It POLLS rather than firing once at a fixed
  delay: a GtkFileChooser enumerates bookmarks and the filesystem before it
  maps, which is slow and variable under Xvfb, and a one-shot timeout that
  fires too early reports `saw=none` for a working chooser. }

uses interfaces, gtk3, gtk3_c, dialogs, uwidgetset;

var
  Report: AnsiString;   { what the timer observed, printed by the main body }
  Tries: Integer;

function CStr(p: Pointer): AnsiString;
var s: AnsiString; c: PChar;
begin
  s := '';
  if p <> nil then
  begin
    c := p;
    while c^ <> #0 do
    begin
      s := s + c^;
      p := p + 1;
      c := p;
    end;
  end;
  CStr := s;
end;

function IntStr(v: Integer): AnsiString;
var s: AnsiString; n: Integer;
begin
  if v = 0 then begin IntStr := '0'; Exit; end;
  s := '';
  n := v;
  while n > 0 do
  begin
    s := Chr(48 + (n mod 10)) + s;
    n := n div 10;
  end;
  IntStr := s;
end;

{ The visible toplevel that is a GtkFileChooser, or nil. Matching on the TYPE
  and not on the title, because a title match would pass for any window we
  happened to name the same -- including one this test created itself. }
function FindChooser: Pointer;
var lst, w: Pointer; i, n: Integer;
begin
  FindChooser := nil;
  lst := gtk_window_list_toplevels;
  if lst = nil then Exit;
  n := g_list_length(lst);
  for i := 0 to n - 1 do
  begin
    w := g_list_nth_data(lst, i);
    if (w <> nil) and (gtk_widget_get_visible(w) <> 0)
       and (g_type_check_instance_is_a(w, gtk_file_chooser_get_type) <> 0) then
      FindChooser := w;
  end;
  g_list_free(lst);
end;

{ Polled from a g_timeout while gtk_dialog_run spins. Records the widget's own
  answers, then tears it down, which returns control from the run. }
function InspectCB(data: Pointer): Integer; cdecl;
var dlg, flt, f: Pointer; i, n: Integer; names: AnsiString;
begin
  Tries := Tries + 1;
  dlg := FindChooser;
  if dlg = nil then
  begin
    if Tries < 60 then begin InspectCB := 1; Exit; end;   { G_SOURCE_CONTINUE }
    Report := 'saw=none';
    DismissActiveDialog;
    InspectCB := 0;
    Exit;
  end;

  Report := 'action=' + IntStr(gtk_file_chooser_get_action(dlg));

  flt := gtk_file_chooser_list_filters(dlg);
  n := 0;
  names := '';
  if flt <> nil then
  begin
    n := g_list_length(flt);
    for i := 0 to n - 1 do
    begin
      f := g_list_nth_data(flt, i);
      if i > 0 then names := names + ',';
      names := names + CStr(gtk_file_filter_get_name(f));
    end;
    g_list_free(flt);
  end;
  Report := Report + ' filters=' + IntStr(n);
  if names <> '' then Report := Report + ' [' + names + ']';

  DismissActiveDialog;
  InspectCB := 0;   { G_SOURCE_REMOVE }
end;

procedure RunOne(const label_: AnsiString; d: TFileDialog);
var ok: Boolean;
begin
  Report := 'saw=none';
  Tries := 0;
  g_timeout_add(50, @InspectCB, nil);
  ok := d.Execute;
  write(label_, ': ', Report, ' execute=');
  if ok then writeln('TRUE') else writeln('FALSE');
end;

var
  op: TOpenDialog;
  sv: TSaveDialog;
  dir: TSelectDirectoryDialog;

begin
  gtk_init(nil, nil);

  { Open, with a two-group filter and a preselected name. The name is the
    second half of this row: a dismissed dialog must NOT clear it, because a
    caller that set it as the preselection would lose it to a cancel. }
  op := TOpenDialog.Create('Open');
  op.Filter := 'Pascal|*.pas;*.inc|All files|*';
  op.FileName := 'keepme.pas';
  RunOne('open', op);
  writeln('open: name=', op.FileName);

  sv := TSaveDialog.Create('Save');
  RunOne('save', sv);

  dir := TSelectDirectoryDialog.Create('Folder');
  RunOne('folder', dir);
end.
