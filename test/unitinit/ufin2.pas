unit ufin2;
interface
uses ufin;
procedure Touch2;
implementation
procedure Touch2; begin Touch; end;
initialization
  writeln('init2 runs');
finalization
  writeln('finalization2 runs');
end.
