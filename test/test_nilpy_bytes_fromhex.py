# bytes.fromhex -- the pair of bytes.hex: either case, whitespace between
# bytes, and CPython's two ValueError messages.
# feature-nilpy-str-surface-gaps-2026-08-09
print(bytes.fromhex("0aff"))
print(bytes.fromhex("DE ad\tBE ef"))
print(bytes.fromhex(""))
b = bytes.fromhex("48656c6c6f")
print(b, b.hex(), len(b))
for bad in ["0g", "0a f", "a", "zz"]:
    try:
        bytes.fromhex(bad)
    except ValueError as e:
        print("ValueError:", e)
