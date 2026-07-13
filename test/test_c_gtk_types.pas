program test_c_gtk_types;
uses gtk;
var
  window: Pointer;   { gtk_window_new returns void*; PGtkWidget was never declared — it was silently a 4-byte int, TRUNCATING the pointer (bug-pascal-unknown-type-silently-integer) }
begin
  window := gtk_window_new(GTK_WINDOW_TOPLEVEL);
  if window <> nil then
    writeln('Successfully created GtkWidget window pointer!')
  else
    writeln('Failed to create GtkWidget window pointer!');
end.
