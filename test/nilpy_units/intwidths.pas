unit intwidths;
{ One function per MACHINE INTEGER kind, so a NilPy local can be rebound across
  each of them. This is the ordinary shape of NilPy calling Pascal or C: the
  callee declares the width, not the caller, and `gl.LINEAR` in the lekkerzeilen
  demo is exactly a C `int` constant arriving as tyInt32.
  Values are chosen to be WIDER THAN THE NEXT KIND DOWN wherever the kind allows
  it, so a join that narrows prints a different number rather than the same one.
  test_nilpy_pascal_integer_widths_join.npy }
interface

function r_i8: ShortInt;
function r_u8: Byte;
function r_i16: SmallInt;
function r_u16: Word;
function r_i32: LongInt;
function r_u32: Cardinal;
function r_i64: Int64;
function r_u64: QWord;
function r_ni: NativeInt;
function r_nu: NativeUInt;
function r_int: Integer;
function r_sgl: Single;

implementation

function r_i8: ShortInt;   begin r_i8  := -7; end;
function r_u8: Byte;       begin r_u8  := 200; end;
function r_i16: SmallInt;  begin r_i16 := -30000; end;
function r_u16: Word;      begin r_u16 := 60000; end;
function r_i32: LongInt;   begin r_i32 := 9729; end;   { GL_LINEAR }
function r_u32: Cardinal;  begin r_u32 := 4000000000; end;
function r_i64: Int64;     begin r_i64 := 4000000000000000000; end;
function r_u64: QWord;     begin r_u64 := 9000000000000000000; end;
function r_ni: NativeInt;  begin r_ni  := -1234567890123; end;
function r_nu: NativeUInt; begin r_nu  := 1234567890123; end;
function r_int: Integer;   begin r_int := 42; end;
function r_sgl: Single;    begin r_sgl := 1.5; end;

end.
