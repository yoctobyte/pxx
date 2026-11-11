# A Pascal RTL routine with a defaulted tail, taken as a value: the wrapper keeps
# the defaults it can bake into its signature record and the real parameter
# names, so f(x) and f(x, indent=2) both work (f(x) segfaulted). min/max as
# values serve both the iterable and the scalar form.
# bug-n-min-and-max-as-a-value-bind-to-the-two-argument-arm-in-the-wrong-unit
import json
h = json.dumps
print(h([1, 2]))
print(h({"b": 1, "a": [True, None]}, indent=2))
print(h({"b": 1, "a": 2}, sort_keys=True))
print(h("é", ensure_ascii=False))
print(list(map(json.dumps, [1, "x", [2]])))
f = min
print(f([3, 1, 2]), f(3, 1))
g = max
print(g([3, 1, 2]), g(3, 9))
print(list(map(min, [[4, 2], [9, 7]])), list(map(max, [[4, 2], [9, 7]])))
