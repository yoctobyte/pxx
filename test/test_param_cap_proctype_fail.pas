program test_param_cap_proctype_fail;
{ The 33rd parameter is refused with the cap and the count; it used to crash
  the compiler. Every declaration parser staged parameters into 32-slot arrays
  and wrote the 33rd past the end: SIGSEGV (rc 139) and no diagnostic, on
  ordinary source, at the shipped cap. CheckParamCap (symtab.inc) is now asked
  before each append and before a method's implicit Self shift.
  bug-a-the-33rd-parameter-crashes-the-compiler }

{ A procedural TYPE is its own parser, with its own staging arrays. }
type
  TF = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25, a26, a27, a28, a29, a30, a31, a32: Integer): Integer;

var
  f: TF;

begin
  f := nil;
end.
