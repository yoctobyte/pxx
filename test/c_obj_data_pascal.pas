program CObjDataPascal;
{ The PASCAL half of the object data-symbol work: a global carrying `cvar` (or
  `public`) is linkable by name from a foreign C main, in BOTH directions -- C
  reads what Pascal initialised, C writes and Pascal sees it, Pascal writes and
  C sees it. Before this, `nm --defined-only | grep -cE ' [BbDd] '` was 0 for
  any Pascal object: the globals were real and lived in .bss, and nothing named
  them to the linker, so there was no spelling that could export one.

  THE MARKED / UNMARKED PAIR IS THE POINT, and both halves are asserted. C
  exports every file-scope variable because C 6.9.2 gives it external linkage;
  Pascal has no such rule, so the directive is the whole condition and an
  unmarked global must stay invisible. GHidden and GName are that control --
  real storage, really read, and absent from the symbol table. Without them the
  row would pass just as well on an object that exported all fifty globals
  `uses sysutils` and the builtin runtime bring in, which is the failure the C
  half met for real: crtl is compiled as C, so exporting its file-scope
  variables put `errno` in the surface and ld refused the object outright over
  glibc's TLS mismatch. The host main touches `errno` and `environ` for that
  reason.
  bug-a-a-pascal-cdecl-program-emits-no-data-symbols-either }
uses sysutils;

var
  GCount: Integer = 7; cvar;
  GPub: Integer = 42; public;     { the other spelling of the same intent }
  GHidden: Integer = 5;           { NOT exported -- and read below, so it is alive }
  GName: AnsiString = 'pascal-global';   { managed, and also not exported }

function obj_readback: Integer; cdecl;
begin
  obj_readback := GCount;
end;

procedure obj_bump; cdecl;
begin
  GCount := GCount + 1;
end;

function obj_hidden: Integer; cdecl;
{ The unmarked global is reachable through an exported ROUTINE. That is the
  distinction being tested: `cvar` controls the DATA surface only, and code
  that cannot see the symbol can still see the value. }
begin
  obj_hidden := GHidden;
end;

function obj_name_len: Integer; cdecl;
{ Reads a managed global too: its slot is a handle, so this says the string
  globals are initialised and reachable without asking C to understand the
  representation. }
begin
  obj_name_len := Length(GName);
end;

begin
end.
