---
track: N
prio: 60
type: bug
blocked-by: decide-sole-a-guard-for-unattended-sessions
---

# A class used as a VALUE: SEGFAULT from a container, compile errors from a name

Python treats a class as an ordinary object — you can bind it, put it in a list
or dict, pass it, and call it. That is how registries and factories are written,
and every shape of it is broken here. **One of them segfaults.**

## The segfault — a class reached through a container

```python
class A:
    def __init__(self, v):
        self.v = v

for cls in [A]:
    x = cls(3)          # SEGFAULT
    print(x.v)
```

Compiles clean (`ok:`), then dies with SIGSEGV. Same with an exception class:

```python
class A(Exception):
    pass

for cls in [A]:
    try:
        raise cls("x")   # SEGFAULT
    except Exception as e:
        print(type(e).__name__)
```

Printing the loop variable shows what it is: `print(cls)` emits a bare integer
(`5781693`) where CPython prints `<class '__main__.A'>`. So the class is
travelling through the container as a raw number and is then CALLED as if it
were a constructor.

**A segfault from ordinary, valid Python is the worst outcome available** —
worse than the compile errors below, which at least name themselves. If the full
feature is too big to land at once, making this shape a NAMED REFUSAL is a
complete and worthwhile fix on its own.

## The compile errors — a class bound to a name

```python
cls = A
x = cls(3)
print(x.v)      # error: "v": a pointer has no members
```

The call is accepted but its result is typed `pointer`, so the very next member
access fails. The instance is real; only its type is lost.

```python
cls = A
raise cls("x")  # error: Nil Python: expected newline after statement
```

`raise` does not accept a non-literal class at all.

```python
for cls in [A, B]:
    print(cls(1).v)   # error: Expected: ), but got: (Kind: 81)
```

## Confirmed pre-existing

Both the segfault and the `pointer has no members` error reproduce with
`stable_linux_amd64/default/pinned`. Not a regression from this session's work.

## Notes toward a fix

pxx already has a runtime metaclass — `AN_CLASSREF` lowers to the class's RTTI
blob address, `BuildMetaclassNew` constructs through it, and the Pascal side uses
this for the fpcunit `Suite` idiom, so *construction through a class reference*
is a solved problem. What is missing is treating the classref as a **value**:
giving it a type that survives being stored in a variant container, recovering
that type on the way out, and routing `cls(...)` and `raise cls(...)` through
`BuildMetaclassNew` instead of through the ordinary call path.

`print(cls)` showing a bare integer is the direct evidence that the value is
currently untagged — a variant holding a class reference needs its own tag, the
way callables needed one (see the three-representations note on `Callable`).

## Gate

`make test-nilpy` + self-host byte-identical, with a CPython-diffed test over:
a class bound to a name and called; a list of classes iterated and called;
a dict of name→class; a class passed as an argument and returned; `raise cls(m)`
in both spellings; `type(x).__name__` on the result; and `print(cls)` /
`cls.__name__`. If the scope is narrowed to a refusal, the test asserts the
diagnostic instead and this ticket stays open for the feature.

## Recon 2026-08-09 — located to the line, BLOCKED on the sole-A guard

A bare class name used as a value is built at **`compiler/parser.inc:4409`**:

```pascal
{ Class identifier used as a value (metaclass / class reference) }
node := AllocNode(AN_CLASSREF);
ASTIVal[node] := ci;
ASTTk[node] := Ord(tyPointer);
```

That is the shared expression parser — a Track A file under the sole-A guard —
so neither the full fix nor the interim NAMED REFUSAL can be written from an
unattended Track N session. Same block as the four tickets already behind
`decide-sole-a-guard-for-unattended-sessions`; marked `blocked-by` so the queue
stops offering it.

**What the refusal cannot be:** a blanket "class name as a value" error. The
same node is what `isinstance(x, A)` and `except SomeError:` produce, and both
work today. The refusal has to be narrower — the classref being stored into a
variable or a container element, i.e. where it becomes an untagged integer — and
that distinction is exactly why it belongs with someone who can see the whole
expression path rather than being bolted on.

**Also measured, and it constrains the eventual fix:** the runtime cannot
recover here either. `pyvar_callv0..3` guard only `Payload = 0`, and a plain
compiled def is *its code address boxed as a plain integer*, so a class
reference and a callable are indistinguishable by tag — see
`bug-nilpy-calling-a-non-callable-segfaults` for the measurement and for the
guard I built, found inert, and reverted. Both tickets therefore want the same
thing: **a distinct callable/classref variant tag.**
