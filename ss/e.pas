program e; {$mode objfpc}
type PR = ^TR; TR = record a: longint; s: string[8]; end; var r: TR; p: PR; ch: char;
begin ch := 'Y'; p := @r; p^.s := ch; writeln(p^.s); end.
