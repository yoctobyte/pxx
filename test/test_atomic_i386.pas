program test_atomic_i386;
var v: Integer; old: Int64;
begin
  v := 7;
  old := __pxxatomic_xchg(@v, 42);
  writeln(old, ' ', v);                      { 7 42 }
  old := __pxxatomic_cas(@v, 42, 100);
  writeln(old, ' ', v);                      { 42 100 }
  old := __pxxatomic_cas(@v, 5, 999);
  writeln(old, ' ', v);                      { 100 100 }
  old := __pxxatomic_add(@v, 11);
  writeln(old, ' ', v);                      { 100 111 }
end.
