{ ===== Exception runtime emission ===== }

procedure EmitExceptionRuntime;
var unhandledJmp, si: Integer;
begin
  { Save enough integer state to return from a raise into the protected frame. }
  ExcSetJmpAddr := CodeLen;
  EmitB($48); EmitB($89); EmitB($1F);                         { mov [rdi], rbx }
  EmitB($48); EmitB($89); EmitB($6F); EmitB($08);             { mov [rdi+8], rbp }
  EmitB($4C); EmitB($89); EmitB($67); EmitB($10);             { mov [rdi+16], r12 }
  EmitB($4C); EmitB($89); EmitB($6F); EmitB($18);             { mov [rdi+24], r13 }
  EmitB($4C); EmitB($89); EmitB($77); EmitB($20);             { mov [rdi+32], r14 }
  EmitB($4C); EmitB($89); EmitB($7F); EmitB($28);             { mov [rdi+40], r15 }
  EmitB($48); EmitB($8D); EmitB($44); EmitB($24); EmitB($08); { lea rax, [rsp+8] }
  EmitB($48); EmitB($89); EmitB($47); EmitB($30);             { mov [rdi+48], rax }
  EmitB($48); EmitB($8B); EmitB($04); EmitB($24);             { mov rax, [rsp] }
  EmitB($48); EmitB($89); EmitB($47); EmitB($38);             { mov [rdi+56], rax }
  EmitB($31); EmitB($C0);                                     { xor eax, eax }
  EmitB($C3);                                                  { ret }

  ExcLongJmpAddr := CodeLen;
  EmitB($48); EmitB($8B); EmitB($1F);                         { mov rbx, [rdi] }
  EmitB($48); EmitB($8B); EmitB($6F); EmitB($08);             { mov rbp, [rdi+8] }
  EmitB($4C); EmitB($8B); EmitB($67); EmitB($10);             { mov r12, [rdi+16] }
  EmitB($4C); EmitB($8B); EmitB($6F); EmitB($18);             { mov r13, [rdi+24] }
  EmitB($4C); EmitB($8B); EmitB($77); EmitB($20);             { mov r14, [rdi+32] }
  EmitB($4C); EmitB($8B); EmitB($7F); EmitB($28);             { mov r15, [rdi+40] }
  EmitB($48); EmitB($8B); EmitB($67); EmitB($30);             { mov rsp, [rdi+48] }
  EmitB($B8); EmitI32(1);                                     { mov eax, 1 }
  EmitB($FF); EmitB($67); EmitB($38);                         { jmp qword [rdi+56] }

  ExcRaiseAddr := CodeLen;
  EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_TOP);
  EmitB($48); EmitB($85); EmitB($C0);                         { test rax, rax }
  EmitB($0F); EmitB($84); unhandledJmp := CodeLen; EmitI32(0); { jz unhandled }
  EmitB($48); EmitB($8D); EmitB($78); EmitB(EXC_JMP_OFFSET);  { lea rdi, [rax+8] }
  EmitB($E9); EmitI32(ExcLongJmpAddr - (CodeLen + 4));        { jmp longjmp }
  Patch32(unhandledJmp, CodeLen - (unhandledJmp + 4));

  if not NoUnhandledHandler then
  begin
    si := InternStr('Unhandled exception');
    MovRaxImm(SYS_WRITE); MovRdiImm(2);
    EmitB($48); EmitB($BE); EmitDataRef(Strs[si].Offset + 8);
    MovRdxImm(Strs[si].Len); EmitSyscall;
    MovRaxImm(SYS_WRITE); MovRdiImm(2);
    EmitB($48); EmitB($BE); EmitDataRef(NEWLINE_OFFSET);
    MovRdxImm(1); EmitSyscall;
  end;
  EmitExit(1);
end;
