program test_ctor_string_literal_arg;
{ bug-i386-try-except-segfault: root-caused to a shared (not per-backend)
  IR-lowering gap. A class instantiation (`TFoo.Create(...)`) lowers with a
  special negative `cpi` (-Ord(tkGetMem)), which the managed-string-argument
  materialization in ir.inc's AN_CALL lowering explicitly gated on
  `cpi >= 0` -- excluding constructors entirely. A string-LITERAL argument to
  a constructor's `const s: string` param therefore reached codegen still
  tagged with its raw frozen-string representation instead of a real managed
  AnsiString heap handle; every backend's by-value call-arg path then pushed
  that raw value as if it already were a heap pointer.

  This explained TWO separately-filed symptoms turning out to share one root
  cause: (1) `E.Message` reading back empty on arm32/aarch64/i386 for
  `Exception.Create('literal')` (a data-correctness bug, no crash), and (2) a
  `try...except` SIGSEGV on i386 in one code-shape but not another (a
  crash) -- both trace to the same bogus non-managed "handle" ending up in
  the exception object's Message field, with the crash happening only when
  something later in the unwind/ARC-release path dereferences/frees it,
  explaining the original ticket's "layout-sensitive" framing (whether that
  dereference is reached depends on subtle codegen differences between
  handler bodies).

  Output is identical on every target (oracle pattern). }
uses sysutils;

type
  TFoo = class
    msg: string;
    constructor Create(const m: string);
  end;
  EMy = class(Exception) end;

constructor TFoo.Create(const m: string);
begin
  msg := m;
end;

var f: TFoo;
begin
  { The two original filed symptoms, both now fixed by the same root-cause fix. }
  f := TFoo.Create('hello');
  writeln('field:', f.msg);

  try raise Exception.Create('a'); except on E: Exception do writeln('c1'); end;
  writeln('after1');

  try raise EMy.Create('a'); except on E: EMy do writeln('c2'); end;
  writeln('after2');

  try raise Exception.Create('a'); except on E: Exception do writeln('c3'); end;
  try raise Exception.Create('b'); except on E: Exception do writeln('c4'); end;
  writeln('after3');

  try raise EMy.Create('hello');
  except on E: EMy do writeln('msg:', E.Message); end;
  writeln('after4');
end.
