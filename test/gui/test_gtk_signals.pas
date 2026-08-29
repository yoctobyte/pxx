program test_gtk_signals;

{ Real GTK3 event loop driven by Pascal callbacks wired through @proc.
  - "destroy" on the window quits the loop (so closing it works).
  - "clicked" on the button prints a line.
  - a 2s timeout fires AutoQuit, so the program also terminates unattended
    and exercises a @proc callback through GTK's actual main loop. }

uses gtk3, gtk3_c;

var
  { Pointer, not PGtkWidget: that typedef existed only in the curated
    lib/pcl/gtk3_c.h and has no counterpart in the stock GTK3 headers
    the binding now includes -- there it is GtkWidget*, which pxx's C
    import surfaces as a plain Pointer. The sibling test_c_gtk_window.pas
    made this same switch earlier for a sharper reason: PGtkWidget was
    never DECLARED there at all, so it was silently a 4-byte integer and
    truncated the pointer (bug-pascal-unknown-type-silently-integer). }
  win, btn: Pointer;

procedure OnDestroy(widget: Pointer; data: Pointer); cdecl;
begin
  writeln('destroy -> quit');
  gtk_main_quit;
end;

procedure OnClick(widget: Pointer; data: Pointer); cdecl;
begin
  writeln('button clicked');
end;

{ Synthesise the click. Without this nothing ever presses the button, so
  OnClick never runs and `clicked` -- the whole point of the file -- is
  asserted by nothing. The test predates being wired and was written to be
  WATCHED: a human clicked the button. An automated row has to press it
  itself or it is green on a dead callback. }
function ClickCB(data: Pointer): Integer; cdecl;
begin
  gtk_button_clicked(btn);
  ClickCB := 0;
end;

function AutoQuit(data: Pointer): Integer; cdecl;
begin
  writeln('timeout -> quit');
  gtk_main_quit;
  AutoQuit := 0; { G_SOURCE_REMOVE }
end;

begin
  gtk_init(nil, nil);

  win := gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(win, PC('Frankonpiler GTK'));
  gtk_window_set_default_size(win, 320, 240);

  btn := gtk_button_new_with_label(PC('Click me'));
  gtk_container_add(win, btn);

  SignalConnect(win, 'destroy', @OnDestroy);
  SignalConnect(btn, 'clicked', @OnClick);
  g_timeout_add(300, @ClickCB, nil);
  g_timeout_add(1000, @AutoQuit, nil);

  gtk_widget_show_all(win);
  gtk_main;

  writeln('exited cleanly');
end.
