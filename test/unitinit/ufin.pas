unit ufin;
interface
procedure Touch;
implementation
procedure Touch; begin end;
initialization
  writeln('init runs');
finalization
  writeln('finalization runs');
end.
