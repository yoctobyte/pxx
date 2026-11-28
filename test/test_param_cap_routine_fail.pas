program test_param_cap_routine_fail;
{ The 33rd parameter is refused with the cap and the count; it used to crash
  the compiler. Every declaration parser staged parameters into 32-slot arrays
  and wrote the 33rd past the end: SIGSEGV (rc 139) and no diagnostic, on
  ordinary source, at the shipped cap. CheckParamCap (symtab.inc) is now asked
  before each append and before a method's implicit Self shift.
  bug-a-the-33rd-parameter-crashes-the-compiler }

{ A plain routine with 73 parameters (the cap is 72 since
  bug-c-a-function-with-more-than-32-parameters-is-refused). }
function F(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25, a26, a27, a28, a29, a30, a31, a32, a33, a34, a35, a36, a37, a38, a39, a40, a41, a42, a43, a44, a45, a46, a47, a48, a49, a50, a51, a52, a53, a54, a55, a56, a57, a58, a59, a60, a61, a62, a63, a64, a65, a66, a67, a68, a69, a70, a71, a72: Integer): Integer;
begin
  F := a0;
end;

begin
  WriteLn(F(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72));
end.
