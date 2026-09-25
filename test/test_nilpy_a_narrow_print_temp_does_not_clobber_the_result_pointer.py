# A def whose result is a Variant gets a hidden result pointer in its frame,
# and a print() of an int mints a 4-byte argument temp beside it. The
# prologue zeroed that temp with an 8-byte store, wiping the pointer's low
# half, and the epilogue's copy-out SIGSEGVed. Every shape below died.
def d():
    print(1)
    return None
def e(*args):
    print(len(args))
    print(*args)
def g():
    print(2)
d()
x = d()
print(x)
e()
e(1, 2)
print(g())
print("end")
