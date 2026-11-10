# The numeric methods real code uses: int.bit_length/to_bytes/from_bytes/
# as_integer_ratio, float.is_integer/hex/fromhex/as_integer_ratio. Expected = python3.
# feature-nilpy-methods-on-int-and-float
x = 255
print(x.bit_length(), (10).to_bytes(2, "big"), int.from_bytes(b"\x01\x00", "big"), (6).as_integer_ratio())
y = 3.0
print(y.is_integer(), (3.5).is_integer(), (1.5).hex(), (0.5).as_integer_ratio())
for s in ["0x1.8p+1", "0x1.0000000000000p+1", "-0x1.999999999999ap-4", "0x0.0p+0", "inf", "-Infinity", "  0x10  ", "1p4", "0x.8", "0x1.fffffffffffffp+1023", "0x0.0000000000001p-1022", "3"]:
    print(s.strip(), float.fromhex(s))
for x in [0.1, 1.5, -2.25, 1e300, 5e-324, 123456.789]:
    print(float.fromhex(x.hex()) == x)
try:
    float.fromhex("0xg")
except ValueError as e:
    print("ValueError", e)
print(float.fromhex("nan"))
