// AArch64 inline-asm encodings (compiler/casm_a64.inc), one per line, checked
// against llvm-mc by tools/check_casm_a64_encodings.sh. Every form dropbear's
// sntrup761.c uses is here, plus the rest of the supported set.
asr w10, w11, w12
asr x10, x11, x12
lsl w10, w10, w11
lsl x13, x14, x15
lsr w10, w11, w12
ror x10, x11, x12
asr w10, w11, #3
asr x10, x11, #63
lsl w10, w11, #31
lsl x10, x11, #1
lsr w10, w11, #31
lsr x10, x11, #63
ror w10, w11, #7
ror x10, x11, #40
sxth w10, w11
sxtb w10, w11
sxth x10, w11
sxtw x10, w11
uxth w10, w11
uxtb w10, w11
ubfx w10, w11, #15, #1
ubfx w10, w11, #0, #1
ubfx x10, x11, #0, #1
ubfx x10, x11, #32, #32
sbfx w10, w11, #15, #1
sbfx w10, w11, #0, #1
sbfx x10, x11, #0, #1
ubfiz w10, w11, #4, #8
sbfiz x10, x11, #3, #20
rbit w10, w11
rbit x10, x11
clz w10, w10
clz x10, x10
cls w10, w11
and w10, w10, #15
and w11, w11, #65535
and x10, x11, #0xff00ff00ff00ff00
and w10, w11, w12
orr w10, w11, #-65536
orr x10, x11, #0x5555555555555555
orr w10, w11, w12
eor w10, w11, #0x80000000
eor x10, x11, x12
ands w10, w11, #1
tst w11, #65535
tst x11, #0xfffffffffffffffe
tst w11, w12
add w10, w11, w12
add x10, x11, #4095
add w10, w11, w12, sxth
sub x10, x11, x12
sub w10, w11, #1
subs w10, w11, w12
adds x10, x11, #1
cmp w10, w11
cmp x10, x11
cmp w10, #0
cmp x10, #0
cmp w10, w11, sxth
cmp w10, w11, uxth
cmp x10, w11, sxtw
cmn w10, #5
cset w10, eq
cset w10, ne
cset w10, gt
cset x10, lt
csetm w10, eq
csetm w10, ne
csetm w10, gt
csetm w10, lt
csetm w10, le
csetm x10, le
csel w10, w11, w12, lt
csel x10, x10, x11, lt
csel x10, x11, x10, ge
csinc w10, w11, w12, ne
csinv x10, x11, x12, hs
csneg w10, w11, w12, mi
mov w10, w11
mov x10, x11
mov w10, #0
mov x10, #65535
neg w10, w11
neg x10, x11
mvn w10, w11
mul w10, w11, w12
mul x10, x11, x12
madd x10, x11, x12, x13
msub w10, w11, w12, w13
nop
