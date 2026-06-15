program test_cross_huge_frame;

{ Regression for the AArch64 large-frame prologue: a function whose frame
  exceeds the 12-bit `sub sp,sp,#imm` immediate (a >4 KB local array) must use
  the LSL #12 shifted-immediate form. Before, the immediate overflowed, sp was
  decremented too little, calls/pushes overlapped the locals, and the saved
  x29/x30 were clobbered -> return to address 0. Reads via x29 looked fine until
  a call corrupted the frame. }

var g: array[0..15] of Integer;

procedure Verify;
var i, acc: Integer;
    big: array[0..131071] of Byte;   { ~128 KB frame, well past the imm12 range }
begin
  for i := 0 to 15 do g[i] := i * 7;
  big[0] := 0;
  big[131071] := 9;
  acc := 0;
  for i := 0 to 15 do
  begin
    writeln('g[', i, ']=', g[i]);   { a call inside the huge frame }
    acc := acc + g[i];
  end;
  writeln('sum=', acc, ' big.last=', big[131071]);
end;

begin
  Verify;
  writeln('returned ok');
end.
