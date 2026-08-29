program test_c_gtk3_stock;
{ Stock GTK3 system headers, not the curated lib/pcl/gtk3_c.h: the whole
  /usr/include/gtk-3.0 surface is parsed, and the calls below bind to the real
  libgtk-3.so.0. Proves the header-import path end to end -- macro soup parsed,
  soname resolved, a real toplevel created, the real main loop entered and left.
  feature-c-gtk3-header-final-wiring }
uses gtk3_c;

function AutoQuit(data: Pointer): Integer; cdecl;
begin
  writeln('AutoQuit called from GTK main loop!');
  gtk_main_quit;
  AutoQuit := 0;
end;

var window: Pointer;
begin
  gtk_init(nil, nil);
  { GTK_WINDOW_TOPLEVEL is a real enum member here, not a #define we supplied. }
  window := gtk_window_new(GTK_WINDOW_TOPLEVEL);
  if window <> nil then
  begin
    writeln('Successfully created window');
    gtk_window_set_title(window, 'Stock GTK3 Window');
    gtk_widget_show_all(window);
    g_timeout_add(1000, @AutoQuit, nil);
    writeln('Starting gtk_main loop...');
    gtk_main;
    writeln('Main loop exited cleanly');
  end
  else
    writeln('Failed to create window');
end.
