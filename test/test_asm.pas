program AsmExit;
{ Rudimentary inline asm: emit raw x86-64 bytes.
  exit(42) = mov eax,60 / mov edi,42 / syscall }
begin
  asm
    db $b8, $3c, $00, $00, $00   { mov eax, 60  (sys_exit) }
    db $bf, $2a, $00, $00, $00   { mov edi, 42  (exit code) }
    db $0f, $05                  { syscall }
  end;
end.
