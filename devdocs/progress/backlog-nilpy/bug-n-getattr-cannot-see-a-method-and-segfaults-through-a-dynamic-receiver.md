---
track: N
prio: 50
type: bug
blocked-by: []
summary: "`getattr(obj, \"name\")` sees FIELDS only. Asked for a method it raises `AttributeError: 'A' object has no attribute 'ping'` about a method the class plainly declares -- and through a DYNAMICALLY-typed receiver the same expression SEGFAULTS the produced binary instead of raising. CPython returns a bound method for both. Compiles clean either way, so the fault has no diagnostic. Reproduces on the pin and at the tip. Found while measuring whether getattr could stand in for open-world dispatch (feature-n-open-world-method-dispatch-on-a-dynamically-typed-receiver); it cannot, and it is a crash on its own account."
status: backlog
owner: —
---

# getattr cannot see a method, and segfaults through a dynamic receiver

## Two repros, one cause, two severities

```python
class A:
    def ping(self, n):
        return n + 1

a = A()
print(getattr(a, "ping")(2))
```

Compiles; at run time:
`Unhandled exception: AttributeError: 'A' object has no attribute 'ping'`,
rc=217. CPython prints `3`. The receiver is statically an `A` and `A` declares
`ping` three lines above.

```python
class A:
    def ping(self, n):
        return n + 1

def use(o):
    return getattr(o, "ping")(2)

print(use(A()))
```

Identical apart from the receiver reaching the call as a variant. Compiles;
**SIGSEGV**, no message.

## The control

```python
class A:
    def __init__(self):
        self.v = 7

def use(o):
    return getattr(o, "v")

print(use(A()))      # prints 7 -- FIELDS resolve, on a variant receiver too
```

So the lookup exists and is wired to the field table only. The two bugs are
one gap at two severities: a wrong `AttributeError` where the class is known,
and an unchecked call through a null where it is not. The segfault is the part
that ranks this -- a compiling program has no diagnostic and no stack.
