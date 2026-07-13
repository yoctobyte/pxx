{ Initialised STRING variables, global and local (b335).

  `var s: String = 'seeded';` — the LOCAL form landed with b329's var-section
  initializers; the GLOBAL form fell through to the ordinal ParseInitVal path
  and died "unexpected token". Registers a kind-1 (string literal) pending
  init, the same shape the C initializer path already flushes. Ordinal globals
  and locals pinned alongside. Verified against FPC. }
program test_var_string_initializer_b335;
{$mode objfpc}{$h+}

var
  gs: String = 'global';
  gn: Integer = 41;

procedure P;
var
  ls: String = 'local';
  ln2: Integer = 1;
begin
  Writeln(gs, '/', ls, ' ', gn + ln2);
end;

begin
  P;
  gs := 'mut';
  P;
end.
