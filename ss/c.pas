program c; {$mode objfpc}
type PR = ^TR; TR = record a: longint; s: string[8]; end; var r: TR; p: PR;
begin p := @r; r.s := ''; p^.a := 1; writeln(r.a); end.
