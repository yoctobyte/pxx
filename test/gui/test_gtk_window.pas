program test_gtk_window;

{ Opens a real GTK3 window with a button, pumps the event loop manually for
  ~3 seconds (no signal callbacks yet — proc-address is the next enabler),
  then exits cleanly. Proves widget creation + rendering over the FFI. }

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
  i: Integer;

begin
  gtk_init(nil, nil);

  win := gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(win, PC('Frankonpiler GTK'));
  gtk_window_set_default_size(win, 320, 240);

  btn := gtk_button_new_with_label(PC('Hello World'));
  gtk_container_add(win, btn);

  gtk_widget_show_all(win);

  { Pump the loop briefly. This was 300 frames (~3s) because the file was an
    EYEBALL demo -- long enough for a human to see the window. A suite row
    watches nothing, so the duration buys only wall-clock; what is being
    asserted is that the pump idiom (gtk_events_pending/gtk_main_iteration_do,
    as opposed to gtk_main) runs and exits cleanly.
    NOTE the line below is NOT witnessed: with no display this still prints
    "window shown, exiting". Mapping is gui_realwindow's tier, not this one. }
  for i := 1 to 30 do
  begin
    while gtk_events_pending <> 0 do
      gtk_main_iteration_do(0);
    usleep(10000);
  end;

  writeln('window shown, exiting');
end.
