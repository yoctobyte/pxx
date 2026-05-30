program test_gtk_window;

{ Opens a real GTK3 window with a button, pumps the event loop manually for
  ~3 seconds (no signal callbacks yet — proc-address is the next enabler),
  then exits cleanly. Proves widget creation + rendering over the FFI. }

uses gtk3;

var
  win, btn: PGtkWidget;
  i: Integer;

begin
  gtk_init(nil, nil);

  win := gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(win, PC('Frankonpiler GTK'));
  gtk_window_set_default_size(win, 320, 240);

  btn := gtk_button_new_with_label(PC('Hello World'));
  gtk_container_add(win, btn);

  gtk_widget_show_all(win);

  { pump ~3s: 300 frames * 10ms }
  for i := 1 to 300 do
  begin
    while gtk_events_pending <> 0 do
      gtk_main_iteration_do(0);
    usleep(10000);
  end;

  writeln('window shown, exiting');
end.
