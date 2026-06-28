program test_c_gtk_types;
uses gtk;
var
  window: PGtkWidget;
begin
  window := gtk_window_new(GTK_WINDOW_TOPLEVEL);
  if window <> nil then
    writeln('Successfully created GtkWidget window pointer!')
  else
    writeln('Failed to create GtkWidget window pointer!');
end.
