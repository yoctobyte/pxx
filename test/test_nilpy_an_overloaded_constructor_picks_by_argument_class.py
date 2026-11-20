# Two same-arity constructors on a Pascal shim class, told apart only by the
# argument's CLASS (TPyBytes vs TPyList). The free functions are the control:
# they always resolved by class; the constructors ran the first-declared body.
# bug-n-an-overloaded-constructor-is-picked-by-name-ignoring-argument-type
import ovprobe
print("func list ->", ovprobe.which([1, 2]))
print("func bytes->", ovprobe.which(b"ab"))
print("ctor list ->", ovprobe.K([1, 2]).tag)
print("ctor bytes->", ovprobe.K(b"ab").tag)
