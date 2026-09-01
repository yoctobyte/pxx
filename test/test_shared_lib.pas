program test_shared_lib;
{ --shared for a COMPILED source (feature-a-shared-library-output-for-compiled-
  sources). Until 2026-09-01 --shared only described .asm-frontend output: the
  writer built its export list from AsmGlobalSym*, which a compiled source never
  populates, so it produced a valid ET_DYN that exported nothing and carried no
  relocations. It was blocked on the backend, not the writer -- a shared library
  IS relocated at load, so the absolute operands that -no-pie rescued in an
  object could not work here at all.

  WHAT THIS SOURCE HAS TO CONTAIN, and why each one is here rather than in a
  smaller program. The .so's correctness rests on R_X86_64_RELATIVE being
  emitted for every absolute pointer stored in .data, and a source without such
  pointers would load and run correctly with none of them -- the empty
  population that cost this ticket's sibling two corrections. So:

    so_virtual   a class with a virtual method: the vtable slot is a data->code
                 pointer (MethodFixups). Wrong base -> a call into nowhere.
    so_dynarray  the pxx heap, through SetLength.
    so_strcat    managed AnsiString concatenation, which walks RTL data.
    so_libc      an external call: the GOT slot is R_X86_64_GLOB_DAT against an
                 UND symbol, a different relocation from all of the above.
    so_tag       a string literal returned as PChar: data->data (DataPtrFix).

  The Makefile asserts RELACOUNT > 0 before trusting any run, because every
  behavioural check below passes trivially on a library that needed no
  relocations. Control, executed when this landed: suppressing the RELATIVE
  entries and rebuilding segfaults the dlopen host. }

type
  TBase = class
    function Name: AnsiString; virtual;
  end;
  TDerived = class(TBase)
    function Name: AnsiString; override;
  end;

function TBase.Name: AnsiString;
begin
  Result := 'base';
end;

function TDerived.Name: AnsiString;
begin
  Result := 'derived';
end;

function strlen(s: PChar): PtrInt; cdecl; external 'libc.so.6';

var
  lastTag: AnsiString;

{ Returns 'derived', not 'base': the answer is wrong in a READABLE way if the
  vtable pointer is misrelocated but still lands on a valid method. }
function so_virtual: PChar; cdecl;
var
  b: TBase;
begin
  b := TDerived.Create;
  lastTag := b.Name;
  b.Free;
  so_virtual := PChar(lastTag);
end;

function so_dynarray(n: Integer): Integer; cdecl;
var
  a: array of Integer;
  i, s: Integer;
begin
  SetLength(a, n);
  for i := 0 to n - 1 do
    a[i] := i * i;
  s := 0;
  for i := 0 to n - 1 do
    s := s + a[i];
  so_dynarray := s;
end;

function so_strcat(n: Integer): Integer; cdecl;
var
  s: AnsiString;
  i: Integer;
begin
  s := '';
  for i := 1 to n do
    s := s + 'ab';
  so_strcat := Length(s);
end;

function so_libc: Integer; cdecl;
begin
  so_libc := strlen('hello world');
end;

function so_tag: PChar; cdecl;
begin
  so_tag := 'pxx-shared';
end;

{ The body is EMPTY, and that is now a property of this test rather than of the
  output mode. It used to carry a comment saying "No initialisation runs when a
  foreign program loads this library, exactly as for an object -- so nothing
  above may depend on the main body. It is empty to say so." That sentence was
  wrong about the mode and it DOCUMENTED A DEFECT AS IF IT WERE THE DESIGN: a
  .so has DT_INIT for exactly this, we were not emitting it, and every piece of
  pre-main state in every pxx library silently stayed unset. Written as a
  decision, it stopped the next reader looking -- which is worse than an
  untested path, and is why this file could never have caught the bug it sat
  next to. Fixed in the commit that added test_shared_lib_init.pas, which is
  where initialisation IS asserted.

  It stays empty here so that this file keeps testing ONE thing -- the export
  surface, the relocations and the two consumers -- rather than quietly
  depending on initialisation for its own results. }
begin
end.
