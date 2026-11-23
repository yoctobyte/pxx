// The fixed aarch64 sequences of compiler/ir_codegen_a64_i128.inc. tools/a64_i128/gen.py
// encodes them. Value model: x0:x1 = (low, high); a binop has left in x2:x3.
// feature-c-int128-other-targets-float-and-narrow-modes
// SNIP A64I128Add
adds x0, x2, x0
adc x1, x3, x1
// SNIP A64I128Sub
subs x0, x2, x0
sbc x1, x3, x1
// SNIP A64I128And
and x0, x2, x0
and x1, x3, x1
// SNIP A64I128Or
orr x0, x2, x0
orr x1, x3, x1
// SNIP A64I128Xor
eor x0, x2, x0
eor x1, x3, x1
// SNIP A64I128Mul
mul x4, x2, x0
umulh x5, x2, x0
madd x5, x2, x1, x5
madd x1, x3, x0, x5
mov x0, x4
// SNIP A64I128CmpEqNe
eor x4, x2, x0
eor x5, x3, x1
orr x0, x4, x5
cmp x0, #0
// SNIP A64I128CmpLR
cmp x2, x0
sbcs xzr, x3, x1
// SNIP A64I128CmpRL
cmp x0, x2
sbcs xzr, x1, x3
// SNIP A64I128Shl
and x4, x0, #127
tbnz x4, #6, big
lsl x1, x3, x4
lsr x5, x2, #1
mvn x6, x4
lsr x5, x5, x6
orr x1, x1, x5
lsl x0, x2, x4
b done
big:
lsl x1, x2, x4
mov x0, xzr
done:
// SNIP A64I128Shr
and x4, x0, #127
tbnz x4, #6, big
lsr x0, x2, x4
lsl x5, x3, #1
mvn x6, x4
lsl x5, x5, x6
orr x0, x0, x5
lsr x1, x3, x4
b done
big:
lsr x0, x3, x4
mov x1, xzr
done:
// SNIP A64I128Sar
and x4, x0, #127
tbnz x4, #6, big
lsr x0, x2, x4
lsl x5, x3, #1
mvn x6, x4
lsl x5, x5, x6
orr x0, x0, x5
asr x1, x3, x4
b done
big:
asr x0, x3, x4
asr x1, x3, #63
done:
// SNIP A64I128Neg
negs x0, x0
ngc x1, x1
// SNIP A64I128Not
mvn x0, x0
mvn x1, x1
// SNIP A64I128LogNot
orr x0, x0, x1
cmp x0, #0
cset x0, eq
// SNIP A64I128SignsSigned
asr x12, x3, #63
asr x13, x1, #63
eor x2, x2, x12
eor x3, x3, x12
subs x2, x2, x12
sbc x3, x3, x12
eor x0, x0, x13
eor x1, x1, x13
subs x0, x0, x13
sbc x1, x1, x13
// SNIP A64I128SignsUnsigned
mov x12, xzr
mov x13, xzr
// SNIP A64I128DivCore
mov x6, xzr
mov x7, xzr
mov x9, #128
loop:
extr x7, x7, x6, #63
extr x6, x6, x3, #63
extr x3, x3, x2, #63
lsl x2, x2, #1
subs x10, x6, x0
sbcs x11, x7, x1
b.lo skip
mov x6, x10
mov x7, x11
orr x2, x2, #1
skip:
subs x9, x9, #1
b.ne loop
// SNIP A64I128TakeQuot
eor x12, x12, x13
mov x0, x2
mov x1, x3
eor x0, x0, x12
eor x1, x1, x12
subs x0, x0, x12
sbc x1, x1, x12
// SNIP A64I128TakeRem
mov x0, x6
mov x1, x7
eor x0, x0, x12
eor x1, x1, x12
subs x0, x0, x12
sbc x1, x1, x12
// SNIP A64I128ToDoubleSigned
asr x9, x1, #63
eor x0, x0, x9
eor x1, x1, x9
subs x0, x0, x9
sbc x1, x1, x9
// SNIP A64I128ToDoubleCore
cbnz x1, big
ucvtf d0, x0
fmov x0, d0
b sign
big:
clz x10, x1
mov x11, #64
sub x11, x11, x10
cmp x11, #64
b.eq s64
lsl x13, x0, x10
lsr x0, x0, x11
lsl x14, x1, x10
orr x0, x0, x14
b stick
s64:
mov x13, x0
mov x0, x1
stick:
cmp x13, #0
cset x14, ne
orr x0, x0, x14
ucvtf d0, x0
fmov x0, d0
add x0, x0, x11, lsl #52
sign:
and x9, x9, #0x8000000000000000
eor x0, x0, x9
// SNIP A64I128FromDouble
mov x12, x0
ubfx x9, x0, #52, #11
cmp x9, #1086
b.hs big
fmov d0, x0
fcvtzs x0, d0
asr x1, x0, #63
b done
big:
ubfx x10, x0, #0, #52
orr x10, x10, #0x10000000000000
sub x9, x9, #1075
cmp x9, #64
b.hs wide
mov x11, #64
sub x11, x11, x9
lsr x1, x10, x11
lsl x0, x10, x9
b sign
wide:
sub x9, x9, #64
lsl x1, x10, x9
mov x0, xzr
sign:
tbz x12, #63, done
negs x0, x0
ngc x1, x1
done:
