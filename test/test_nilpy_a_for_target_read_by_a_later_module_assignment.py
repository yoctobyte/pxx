# A module-level for TARGET read by a later module ASSIGNMENT after the loop:
# `a = i` died "undefined variable (i)" at compile time while `print(i)` worked.
# bug-n-a-module-level-assignment-from-a-for-target-after-the-loop-is-undefined
for i in range(3):
    pass
a = i
print(a, a + 1)
for ch in "xyz":
    pass
s = ch * 2
print(s)
for v in [1.5, 2.5]:
    pass
f = v * 2
print(f)
d = {"k": 1, "j": 2}
for key in d:
    pass
last = key
print(last)
for n, item in enumerate(["p", "q"]):
    pass
pair = (n, item)
print(pair, n + 10)
for x, y in [(1, 2), (3, 4)]:
    x2 = x
y2 = y
print(x2, y2)
for w in sorted([3, 1, 2]):
    pass
t = 7 if w > 2 else 0
print(t)
for z in d.values():
    pass
u = z
print(u)
