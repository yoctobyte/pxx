# NilPy str escapes are CODE POINTS stored as UTF-8, as in CPython; in a
# bytes literal a numeric escape is one raw byte and \u / \U / \N are text.
# Printed as len plus the encoded bytes, so a raw byte cannot pass for UTF-8.
x = 1
strs = ["\xe9", "\u00e9", "\U0001F600", "a\x41b", "\u20ac", "é", "\x7f\x80", "\n\t\x00", "\351"]
strs.append(f"\u00e9{x}\xe9")
strs.append("""\u20ac\U0001F600""")
for s in strs:
    print(len(s), list(s.encode("utf-8")))
byts = [b"\xe9", b"\u00e9", b"a\x41b", b"\x00\xff", b"\U0001F600", b"\351", b"a\N{x}b"]
byts.append(b"\xe9"  # joined
            b"\x41")
for b in byts:
    print(len(b), list(b))
print("\u00e9" == "\xe9", "\xe9" == "é")
