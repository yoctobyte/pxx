program test_param_cap_method_fail;
{ The 33rd parameter is refused with the cap and the count; it used to crash
  the compiler. Every declaration parser staged parameters into 32-slot arrays
  and wrote the 33rd past the end: SIGSEGV (rc 139) and no diagnostic, on
  ordinary source, at the shipped cap. CheckParamCap (symtab.inc) is now asked
  before each append and before a method's implicit Self shift.
  bug-a-the-33rd-parameter-crashes-the-compiler }

{ 72 declared parameters plus the implicit Self make 73 (cap 72): the method's cap is
  one lower, and the shift that inserts Self is where it overflowed. }
{$mode objfpc}
type
  T = class
    function M(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25, a26, a27, a28, a29, a30, a31, a32, a33, a34, a35, a36, a37, a38, a39, a40, a41, a42, a43, a44, a45, a46, a47, a48, a49, a50, a51, a52, a53, a54, a55, a56, a57, a58, a59, a60, a61, a62, a63, a64, a65, a66, a67, a68, a69, a70, a71: Integer): Integer;
  end;

function T.M(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25, a26, a27, a28, a29, a30, a31, a32, a33, a34, a35, a36, a37, a38, a39, a40, a41, a42, a43, a44, a45, a46, a47, a48, a49, a50, a51, a52, a53, a54, a55, a56, a57, a58, a59, a60, a61, a62, a63, a64, a65, a66, a67, a68, a69, a70, a71: Integer): Integer;
begin
  M := a0;
end;

begin
end.
