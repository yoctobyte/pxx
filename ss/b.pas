program b; {$mode objfpc}
type TS = string[8]; var s: TS; p: ^TS;
begin p := @s; p^ := 'abc'; writeln(s); end.
