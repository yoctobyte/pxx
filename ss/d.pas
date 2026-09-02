program d; {$mode objfpc}
type PR = ^TR; TR = record a: longint; s: string[8]; end; var r: TR; p: PR;
begin p := @r; p^.s := 'abc'; writeln(p^.s); end.
