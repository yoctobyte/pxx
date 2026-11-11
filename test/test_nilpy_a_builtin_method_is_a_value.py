# A builtin str/list/dict/int/float method read as a VALUE -- through getattr,
# a bare attribute read, a string literal -- then called, mapped and passed.
# bug-n-getattr-with-a-literal-method-name-on-a-builtin-container-or-str-is-refused
s = "ab"
f = s.upper
print(f())
print(getattr(s, "upper")(), getattr(s, "replace")("a", "z"))
d = {"a": 1}
print(hasattr(d, "keys"), list(getattr(d, "keys")()))
l = [3, 1]
getattr(l, "sort")()
print(l)
csv = "a,b,c"
sp = csv.split
print(sp(","))
fl = 2.5
print(fl.is_integer(), getattr(fl, "is_integer")())
print(callable(f))
print(repr(f).startswith("<built-in method upper of str object at"))
words = ["x", "y"]
up = [w.upper for w in words]
print([u() for u in up])
try:
    getattr(s, "nope")
except AttributeError as e:
    print("AttributeError", e)
s = "ab"
print(getattr(s, "upper", None)(), getattr(s, "nope", "dflt"))
s2 = "  Hello World  "
for name in ["strip", "lower", "upper", "title", "swapcase", "lstrip", "rstrip"]:
    print(name, repr(getattr(s2, name)()))
t = "a-b-c"
print(getattr(t, "split")("-"), getattr(t, "rsplit")("-", 1), getattr(t, "partition")("-"))
print(getattr(t, "count")("-"), getattr(t, "find")("b"), getattr(t, "replace")("-", "+", 1))
print(getattr("7", "zfill")(3), getattr("ab", "center")(6, "*"), getattr("x", "ljust")(3) + "|")
print(getattr("12", "isdigit")(), getattr("ab", "isalpha")(), getattr("  ", "isspace")())
d = {"k": 1, "j": 2}
g = d.get
print(g("k"), g("z"), g("z", 9))
print(sorted(getattr(d, "values")()), sorted(getattr(d, "items")()))
l = []
add = l.append
for i in range(3):
    add(i * i)
print(l)
words = ["b", "A", "c"]
print(list(map("x".join, [["1", "2"], ["3"]])))
low = "ABC".lower
print(low(), low())
n = 10
print(getattr(n, "bit_length")(), getattr(2.0, "is_integer")(), getattr(1.5, "as_integer_ratio")())
print(type(low).__name__)
ex = {}
exec("r = 'a,b'.split(',')\nq = ' x '.strip()\nz = 'abc'.rfind('c')", ex)
print(ex["r"], ex["q"], ex["z"])
f = "x".join
print(f(["a","b"]))
print(list(map("-".join, [["1","2"]])))
g = "AB".lower
print(g())
