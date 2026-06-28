program test_c_gtk_call;
uses gtk;
begin
  gtk_init(nil, nil);
  writeln('gtk_init resolved and called successfully!');
end.
