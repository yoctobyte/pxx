program test_c_gtk_window;
uses gtk;

function AutoQuit(data: Pointer): Integer; cdecl;
begin
  writeln('AutoQuit called from GTK main loop!');
  gtk_main_quit;
  AutoQuit := 0;
end;

var
  window: PGtkWidget;
begin
  gtk_init(nil, nil);
  window := gtk_window_new(GTK_WINDOW_TOPLEVEL);
  if window <> nil then
  begin
    writeln('Successfully created window');
    gtk_window_set_title(window, 'C-Header Window');
    gtk_widget_show_all(window);
    g_timeout_add(1000, @AutoQuit, nil);
    writeln('Starting gtk_main loop...');
    gtk_main;
    writeln('Main loop exited cleanly');
  end
  else
    writeln('Failed to create window');
end.
