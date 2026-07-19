---
track: N
prio: 75
type: bug
---

# NilPy: a method returning `str` returns garbage

Found 2026-07-19. **Pre-existing and independent** of the class-field work it
was found alongside — reproduced on the PINNED stable compiler, which predates
all of that. Silent: prints an integer, no diagnostic.

## Repro

```python
class Inner:
    def __init__(self, name: str) -> None:
        self.name = name
    def shout(self) -> str:
        return self.name

i = Inner("dup")
print(i.shout())     # CPython: dup      pxx: 1853882416
print(i.name)        # CPython: dup      pxx: dup   (the FIELD is fine)
```

Reading the field directly works; going through a `-> str` method does not.
Confirmed on `stable_linux_amd64/default/pinned` as well as HEAD.

## What it is NOT

It is not about class-typed fields or member resolution — the receiver here is
a plain local built by a direct constructor call, no field chain involved.
`bug-nilpy-class-typed-field-loses-identity` is a different bug that happened
to surface this one; `o.inner.shout()` failing is this bug, not that one.

## Where to look

The integer-shaped result suggests the call node is not taking the method's
return type, or the managed-string result is not marshalled through the
method-call path. Note `PyRegisterClassMembers` registers every method with
`RegisterProc(fullName, not isCtor, tyInteger, ...)` — a hardcoded `tyInteger`
return type — and the real return type is presumably patched in later (or not,
for `str`). That is the first thing to check.

## Why it is urgent

uforth is full of `-> str` methods (word names, token text, the whole
tokenizer surface). Any of them silently yields an integer today, so a corpus
run cannot be trusted. Blocks [[feature-nilpy-corpus-uforth]] milestone 1.
