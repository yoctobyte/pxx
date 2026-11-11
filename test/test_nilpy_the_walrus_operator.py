import re
xs = [1, 2, 3, 4]
if (n := len(xs)) > 3:
    print("big", n)
print(n)

def f(x):
    return x * 2 if x % 2 else None

ys = [y for x in xs if (y := f(x)) is not None]
print(ys)

def g(data):
    out = []
    i = 0
    while (chunk := data[i:i + 2]):
        out.append(chunk)
        i += 2
    return out, chunk
print(g([1, 2, 3, 4, 5]))

def h(s):
    if (m := s.find("x")) >= 0:
        return s[m:]
    return m
print(h("abxcd"), h("abc"))
print(max((t := 7), 3), t)
total = 0
for v in [3, 4]:
    total += (sq := v * v)
print(total, sq)
xs = [1, 2, 3, 4]
zs = [y * 10 for x in xs if (y := x - 1) > 0]
print(zs, y)
print([(d := x * 2) for x in xs], d)
print(sum(q for x in xs if (q := x * x) > 4))

def parse(lines):
    out = {}
    for ln in lines:
        if (m := re.match(r"(\w+)=(\d+)", ln)):
            out[m.group(1)] = int(m.group(2))
    return out
print(parse(["a=1", "junk", "b=22"]))

def words(s):
    if (n := len(s.split())) == 0:
        return "empty"
    return "%d words" % n
print(words(""), words("a b c"))
name = "x"
if (u := name.upper()) == "X":
    print(u + "!")
