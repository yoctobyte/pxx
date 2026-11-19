REM A unit-free BASIC program that CONCATENATES and COMPARES strings.
REM Both lower onto builtinheap bodies (PXXStrConcat, PXXStrEq) through the
REM emitted AnsiString shims. aarch64, arm32, riscv32 and xtensa pulled
REM builtinheap for their own codegen and printed this; x86-64 refused with
REM "call to a runtime stub that was never emitted" and i386 with
REM "PXXStrConcat not found". The driver now scans the source for a string
REM operation and pulls the unit when it finds one. b and c are string
REM valued only through other names, which is the propagation the scan
REM needs. n is the numeric control.
REM bug-a-basic-string-concat-in-a-unit-free-program-is-a-compiler-error
DIM s = "abc"
DIM t = "def"
PRINT s + t
IF s = "abc" THEN PRINT "eq"
DIM a = "x"
DIM n = 3
b = a
c = b + "yz"
IF c = "xyz" THEN PRINT "match"
IF n = 3 THEN PRINT n
PRINT c
