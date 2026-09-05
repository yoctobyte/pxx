program test_c_gtk_types;
uses gtk;
var
  window: Pointer;   { gtk_window_new returns void*; PGtkWidget was never declared — it was silently a 4-byte int, TRUNCATING the pointer (bug-pascal-unknown-type-silently-integer) }
begin
  { gtk_init BEFORE gtk_window_new, which GTK has always required and GTK 2 did
    not enforce. This test ran for months without it: under GTK 2 a window could
    be created with no display connection, so the omission was invisible. Under
    GTK 3 the same call aborts in _gtk_css_lookup_resolve with "Can't create a
    GtkStyleContext without a display connection" -- surfaced the moment `uses
    gtk` moved to GTK 3 (decide-which-gtk-a-bare-gtk-gtk-h-means).
    THE TEST WAS ALWAYS WRONG AND GTK 2 WAS LENIENT; this is not a GTK 3
    workaround, and it does not weaken what the row asserts. The subject is still
    that gtk_window_new's void* survives into a Pascal Pointer without being
    truncated to 4 bytes -- gtk_init returns nothing and cannot supply that. }
  gtk_init(nil, nil);
  window := gtk_window_new(GTK_WINDOW_TOPLEVEL);
  if window <> nil then
    writeln('Successfully created GtkWidget window pointer!')
  else
    writeln('Failed to create GtkWidget window pointer!');
end.
