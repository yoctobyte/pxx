program test_gtk_signals;

{ Real GTK3 event loop driven by Pascal callbacks wired through @proc.
  - "destroy" on the window quits the loop (so closing it works).
  - "clicked" on the button prints a line.
  - a 2s timeout fires AutoQuit, so the program also terminates unattended
    and exercises a @proc callback through GTK's actual main loop. }

uses gtk3;

var
  win, btn: PGtkWidget;

procedure OnDestroy(widget: Pointer; data: Pointer); cdecl;
begin
  writeln('destroy -> quit');
  gtk_main_quit;
end;

procedure OnClick(widget: Pointer; data: Pointer); cdecl;
begin
  writeln('button clicked');
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
  g_timeout_add(2000, @AutoQuit, nil);

  gtk_widget_show_all(win);
  gtk_main;

  writeln('exited cleanly');
end.
