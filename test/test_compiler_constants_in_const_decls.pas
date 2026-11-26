{ The compiler constants a source may read (__pxxTlsFsEntrySlotOff and the
  rest) fold in a `const` declaration exactly as in an expression -- bare,
  with `()`, and inside a larger constant expression. The ABI translators
  define NB_TLS_SLOT_CTID = __pxxTlsFsEntrySlotOff div 8, and the const
  evaluator did not know the names: every --os=netbsd / openbsd / dragonfly
  compile failed with "not a constant".
  bug-p-a-compiler-tls-constant-is-not-a-constant-in-a-const-declaration }
program test_compiler_constants_in_const_decls;
const
  FsSlot  = __pxxTlsFsEntrySlotOff div 8;
  FsOff   = __pxxTlsFsEntrySlotOff();
  Init2   = 2 * __pxxTlsInitImageSlotOff;
  Owner   = __pxxTlsOwnerFsSlotOff;
  Block   = __pxxTlsBlockSize - __pxxTlsUserBytes;
  UserOff = __pxxTlsUserOff;
  AltSt   = __pxxSigAltStackSize;
var ok: Boolean;
procedure Check(const what: AnsiString; c, e: Int64);
begin
  if c <> e then begin writeln(what, ': const ', c, ' expr ', e); ok := False; end;
end;
begin
  ok := True;
  Check('FsSlot', FsSlot, __pxxTlsFsEntrySlotOff div 8);
  Check('FsOff', FsOff, __pxxTlsFsEntrySlotOff);
  Check('Init2', Init2, 2 * __pxxTlsInitImageSlotOff);
  Check('Owner', Owner, __pxxTlsOwnerFsSlotOff);
  Check('Block', Block, __pxxTlsBlockSize - __pxxTlsUserBytes);
  Check('UserOff', UserOff, __pxxTlsUserOff);
  Check('AltSt', AltSt, __pxxSigAltStackSize);
  Check('FsOff mod 8', FsOff mod 8, 0);
  if ok then writeln('compiler constants fold in const declarations: yes');
end.
