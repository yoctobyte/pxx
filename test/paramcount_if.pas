program ParamCountIf;
begin
  if ParamCount < 1 then
    halt(7);
  writeln('argc-ok');
end.
