# '\xNN' is code point U+00NN, not byte NN: above 0x7f it must encode as
# UTF-8, keep len() == 1 and give ord() == NN. Octal and \u agree; a bytes
# literal keeps the raw byte. (bug-n-the-hex-string-escape-emits-a-raw-byte-not-a-code-point)
for s in ['\x41', '\x7f', '\x80', '\xa0', '\xe9', '\xff', '\351', 'é']:
    print(len(s), ord(s), list(s.encode('utf-8')))
print('\xe9' == chr(233), '\xe9' == 'é', '\351' == '\xe9')
print(len('caf\xe9!'), 'caf\xe9!'.upper().encode('utf-8'))
print(list(b'\xe9\x80\377'))
