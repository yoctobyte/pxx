# x.bit_length() / x.to_bytes() on a variant that is not an int raises AttributeError.
# bug-n-an-int-method-on-a-none-receiver-returns-0-instead-of-raising
def c(x):
    return x.bit_length()
def tb(x):
    return x.to_bytes(2, "big")
print(c(7), c(True), c(2**70), tb(258))
for v in [None, 2.5, "abc", [1], {'a': 1}]:
    try:
        print(c(v))
    except AttributeError as e:
        print("AttributeError", e)
