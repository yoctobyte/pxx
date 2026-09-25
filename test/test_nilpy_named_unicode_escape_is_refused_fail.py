# \N plus a braced name needs the Unicode name table, which is not carried:
# refused at compile time rather than kept as text.
s = "a\N{EURO SIGN}b"
print(s)
