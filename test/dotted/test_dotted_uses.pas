{ Regression: dotted / namespace unit names in `uses` + qualified references.
  See feature-dotted-unit-names. }
program test_dotted_uses;
uses Posix.SysSocket, System.Generics.Collections;
begin
  writeln(Posix.SysSocket.AF_INET);   { qualified const through a 2-part unit }
  writeln(Posix.SysSocket.SockTag);   { qualified call through a 2-part unit }
  writeln(ListTag);                    { unqualified symbol from a 3-part unit }
end.
