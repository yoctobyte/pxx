{ SPDX-License-Identifier: 0BSD }
{ The library sibling of test/test_dotted_program_name.pas: a dotted `library`
  name reads the same way a dotted program, unit or `uses` name does. }
library my.dotted.lib;
function DottedAnswer: Integer; cdecl;
begin
  DottedAnswer := 42;
end;
exports DottedAnswer;
end.
