# TypeInfo(T) in NilPy reports the type the program NAMED. byte and integer
# are one token kind in the Pascal lexer, which once made TypeInfo(Byte) answer
# Integer there; NilPy resolves every type name by spelling. The pair is what
# makes the defect visible, so both rows are here.
# bug-n-typeinfo-reads-the-wrong-token-and-switches-on-kind
import tiprobe

print(tiprobe.tiname(TypeInfo(byte)))
print(tiprobe.tiname(TypeInfo(UInt8)))
print(tiprobe.tiname(TypeInfo(integer)))
print(tiprobe.tiname(TypeInfo(Integer)))
print(tiprobe.tiname(TypeInfo(word)))
print(tiprobe.tiname(TypeInfo(boolean)))
print(tiprobe.tiname(TypeInfo(longword)))
print(tiprobe.tiname(TypeInfo(double)))
print(tiprobe.tiname(TypeInfo(string)))
