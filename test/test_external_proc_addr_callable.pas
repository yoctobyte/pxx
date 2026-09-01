{ `@external` must yield the address the CALL path would use -- not merely a
  non-nil one. Every existing check of this (soname_host_discovery.pas, and
  cexternal_func_addr_b106.c on the C side) asserts `<> nil` and stops there, so
  a displacement patched to the wrong place passes them whenever the wrong place
  happens to be mapped. This one calls through the pointer and compares the
  answer with a direct call to the same routine.

  Live case: converting the external CALL site to `call [rip+disp32]`
  (feature-a-x86-64-object-output-is-position-dependent) without converting
  EmitExternalProcAddr's sibling `mov rax,[abs]` left the address-of arm
  absolute while PatchDynCallSites, which reads TargetArch alone, patched it
  PC-relatively. That one crashed, so everything caught it.

  MEASURED, with the addend deliberately shifted by one slot (+8): `@strlen`
  came back NON-NIL -- it had resolved to the neighbouring GOT entry, `puts` --
  and calling through it returned 12 instead of 11, exit code 0, no crash. The
  nil checks all passed. TWO externals are therefore declared below on purpose:
  with one, the neighbouring slot is zero and the bug degrades into the easy nil
  case that the existing tests already catch. }
program test_external_proc_addr_callable;

type
  TStrLen = function(s: PChar): PtrInt; cdecl;

function strlen(s: PChar): PtrInt; cdecl; external 'libc.so.6';
{ Second external, so the slot next to strlen's holds a real address rather
  than zero -- see the header. Never called. }
function puts(s: PChar): PtrInt; cdecl; external 'libc.so.6';

var
  p, q: Pointer;
  f: TStrLen;
  direct, viaptr: PtrInt;
begin
  { The VALUE comparison first, deliberately. It is the check that catches a
    wrong-but-mapped address, and a nil test placed ahead of it will trip first
    on a defect that this one describes better. }
  p := @strlen;
  if p = nil then begin WriteLn('FAIL: @strlen is nil'); Halt(1); end;
  f := TStrLen(p);
  direct := strlen('hello world');
  viaptr := f('hello world');
  if direct <> 11 then
  begin WriteLn('FAIL: direct call returned ', direct, ', want 11'); Halt(1); end;
  if viaptr <> direct then
  begin WriteLn('FAIL: via @strlen returned ', viaptr, ', direct returned ', direct); Halt(1); end;
  q := @puts;
  if q = nil then begin WriteLn('FAIL: @puts is nil'); Halt(1); end;
  if q = p then begin WriteLn('FAIL: @puts and @strlen are the same address'); Halt(1); end;
  WriteLn('EXTERNAL PROC ADDR OK');
end.
