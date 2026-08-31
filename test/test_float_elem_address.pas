program test_float_elem_address;
{ Taking the ADDRESS of a float array element is integer arithmetic, and must
  not reach the float lowering.

  bug-a-taking-the-address-of-a-float-array-element-is-a-float-operator-on-32-bit

  An IR_INDEX / IR_FIELD / IR_LEA node computes an ADDRESS, and its IRTk records
  the type of what lives AT that address -- which is what the IR_LOAD_MEM
  stacked on top needs. Every backend's binop dispatch asked
  `TypeIsFloat(IntToTypeKind(IRTk[operand]))`, so `@V[0]` over an `array of
  Double` answered tyDouble and an address computation was dispatched into the
  float path. IRValueKind (ir.inc) is the one place that answers it now.

  TWO FAILURE MODES, ONE DEFECT, AND ONLY ONE OF THEM WAS LOUD:

  * i386 / arm32 / riscv32 -- `PtrUInt(x)` on a 32-bit target is `x and
    $FFFFFFFF`, and no soft-float kernel implements `and`, so this program did
    not COMPILE: "unsupported float operator", with no float operation in it.
  * x86-64 at -O0 -- `PtrUInt(x)` there is `x + 0`, and `+` IS in the float set,
    so it compiled to `movq xmm1, rax / cvtsi2sd xmm0, rcx / addsd xmm0, xmm1 /
    movq rax, xmm0`: the address reinterpreted as a double, added to 0.0, and
    reinterpreted back. It returned the RIGHT ANSWER, because a finite double
    plus 0.0 is bit-preserving and an address is a tiny denormal. At -O1 and
    above an imm-fold arm keyed on the NODE's type caught it first and emitted
    `add rax, 0`. So on the one target everyone develops on, the wrong code was
    invisible at every level: absent at -O1+, and correct-by-luck at -O0.

  WHICH IS WHY THIS TEST IS ALSO WIRED AT -O0. A single default-level run on
  x86-64 could never have failed, and a test that cannot fail is not a test.
  The 32-bit rows are the ones that fail loudly; the -O0 row is the one that
  would have caught the silent half, via the strides rather than the crash --
  under DAZ, or with any bit pattern fadd does not preserve, the denormal luck
  runs out and the stride comes back wrong rather than absent. }

var
  V: array[0..3] of Double;
  S: array[0..3] of Single;
  W: array[0..3] of Int64;
  d: Double;
  bad, checked: Integer;

procedure Check(const nm: AnsiString; got, want: PtrUInt);
begin
  Inc(checked);
  if got <> want then
  begin
    writeln('WRONG ', nm, ' got ', got, ' want ', want);
    Inc(bad);
  end;
end;

begin
  bad := 0;
  checked := 0;
  V[0] := 1.5; V[1] := 2.25; V[3] := 4.5;
  S[0] := 0.5; S[1] := 1.5;
  W[0] := 7;   W[1] := 9;

  { the shape that did not compile at all on the 32-bit targets }
  Check('double stride', PtrUInt(@V[1]) - PtrUInt(@V[0]), 8);
  Check('double span',   PtrUInt(@V[3]) - PtrUInt(@V[0]), 24);
  Check('single stride', PtrUInt(@S[1]) - PtrUInt(@S[0]), 4);
  { the control that always worked -- an integer element type takes the same
    path and must keep taking it }
  Check('int64 stride',  PtrUInt(@W[1]) - PtrUInt(@W[0]), 8);
  { and the two forms either side of the defect's boundary: the whole array,
    and a scalar. Both compiled before; both must still be exactly zero. }
  Check('whole array',   PtrUInt(@V[0]) - PtrUInt(@V), 0);
  Check('scalar addr',   PtrUInt(@d) - PtrUInt(@d), 0);

  { REAL float work must be untouched -- the fix narrows what counts as a float
    OPERAND, so an actual float operand had better still count. A value read is
    an IR_LOAD_MEM over the index and keeps its own type; if that regressed,
    these come back as integer garbage rather than as a compile error. }
  d := V[0] + V[1];
  if d <> 3.75 then begin writeln('WRONG float add ', d:0:4); Inc(bad); end;
  Inc(checked);
  d := V[1] / V[0];
  if d <> 1.5 then begin writeln('WRONG float div ', d:0:4); Inc(bad); end;
  Inc(checked);
  d := Double(S[0]) * 3.0;
  if d <> 1.5 then begin writeln('WRONG single mul ', d:0:4); Inc(bad); end;
  Inc(checked);
  if not (V[1] > V[0]) then begin writeln('WRONG float cmp'); Inc(bad); end;
  Inc(checked);
  d := W[0] / 2;
  if d <> 3.5 then begin writeln('WRONG int div ', d:0:4); Inc(bad); end;
  Inc(checked);

  { The count is the variable, so dropping a Check cannot leave the token
    claiming coverage that is gone. }
  if bad = 0 then writeln('FLOAT-ELEM-ADDR OK checked=', checked);
end.
