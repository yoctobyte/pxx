program FieldFold;
{ IR_LOAD_MEM / IR_STORE_MEM fold an IR_FIELD offset into the instruction's
  displacement (x86-64, -O1 and up): offset 0 is [rax], a small one disp8, a
  large one disp32. Every load and store width at each, through a pointer and
  through a class, so a wrong ModRM byte shows as a wrong value. }
type
  PRec = ^TRec;
  TRec = record
    b0: ShortInt;
    w: SmallInt;
    d: LongInt;
    q: Int64;
    ub: Byte;
    uw: Word;
    ud: LongWord;
    s: Single;
    f: Double;
    pad: array[0..299] of Byte;
    bigB: ShortInt;
    bigW: SmallInt;
    bigD: LongInt;
    bigQ: Int64;
    bigS: Single;
    bigF: Double;
  end;
  TObj = class
    a: Int64;
    pad: array[0..199] of Int64;
    z: Int64;
  end;
var
  r: TRec;
  p: PRec;
  o: TObj;
begin
  p := @r;
  p^.b0 := -5; p^.w := -1234; p^.d := -123456; p^.q := -1234567890123;
  p^.ub := 250; p^.uw := 65000; p^.ud := 4000000000; p^.s := 1.5; p^.f := 2.25;
  p^.bigB := -7; p^.bigW := -2345; p^.bigD := -234567; p^.bigQ := -9876543210;
  p^.bigS := -0.5; p^.bigF := 3.125;
  WriteLn(p^.b0, ' ', p^.w, ' ', p^.d, ' ', p^.q);
  WriteLn(p^.ub, ' ', p^.uw, ' ', p^.ud, ' ', p^.s:0:2, ' ', p^.f:0:3);
  WriteLn(p^.bigB, ' ', p^.bigW, ' ', p^.bigD, ' ', p^.bigQ, ' ', p^.bigS:0:2, ' ', p^.bigF:0:3);
  o := TObj.Create;
  o.a := 11; o.z := 22;
  o.z := o.z + o.a;
  WriteLn(o.a, ' ', o.z);
  o.Free;
end.
