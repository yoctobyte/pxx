program a; {$mode objfpc}
type TS = string[8]; var s: TS; p: ^TS; c: char;
begin c := 'X'; p := @s; p^ := c; writeln(s); end.
