---
summary: "`def __init__(self, tag, *rest)` — a fixed parameter BEFORE `*args` segfaults on ordinary construction. `*args` alone works, so only the mixed shape is broken; no diagnostic, the crash is inside the constructor."
type: bug
track: N
prio: 55
found-by: claude-AN
status: done
owner: claude-AN
---

# A fixed parameter before `*args` segfaults

- **Type:** bug (crash, no diagnostic) — Track N (Nil-Python frontend)
- **Opened:** 2026-08-10
- **Found by:** writing the gate cases for [[feature-nilpy-class-as-a-value]];
  the shape is unrelated to that feature (it fails identically without it).

## Repro

```python
class P:
    def __init__(self, tag, *rest):
        self.tag = tag
        self.n = len(rest)
    def show(self):
        print("P", self.tag, self.n)

o = P("u", 9)
o.show()
```

CPython prints `P u 1`. pxx compiles clean and **SEGFAULTS**.

Confirmed pre-existing at `stable_linux_amd64/default/pinned` (v256), so it is
not the class-as-a-value work.

## The boundary, measured

| shape | result |
| --- | --- |
| `def __init__(self, *args)` | **works** (`S(1, 2)` → `n == 2`) |
| `def __init__(self, tag, *rest)` | **segfault** |

So it is not `*args` in a constructor and not construction — it is a fixed
parameter *before* the star that breaks. Worth checking the plain-`def` twin
(`def g(a, *rest)`) before deciding the fix belongs to the ctor path: if that
fails too, the packing is wrong wherever the star index is not 1, and the
constructor is only where it was noticed.

## Why it rates a 55

It is the standard thin-wrapper shape — `def __init__(self, name, *opts)` — and
it crashes rather than diagnosing, which is the expensive kind. It is also
narrow: the star-index-0 case works, so this is very likely one off-by-one in
the argument packing rather than missing machinery.

## Related

[[feature-nilpy-star-args-kwargs]] is the broad callee-side `*args`/`**kwargs`
feature (unfinished). This is filed separately because it is a SILENT CRASH in
a shape that already parses and already half-works, not a missing feature.

## Gate

`make test-nilpy` + self-host byte-identical, with a `.npy` case covering
`(self, a, *rest)`, `(self, a, b, *rest)` and the plain-`def` twin, diffed
against CPython via `tools/pydiff.py run`.

## Resolution (2026-08-11)

### The ticket's boundary was measured through the wrong door

It recorded `def __init__(self, *args)` as **working**. It is not — that row was
measured through a class VALUE (`k = S; k(1, 2)`), which goes through pyeval's
`PyClassRefNew` and packs the star itself. Ordinary construction `S(1, 2)`
segfaulted too. So the real statement is broader and simpler:

**`*args` on a constructor was never packed at all.**

| shape | before |
| --- | --- |
| `def g(a, *rest)` — plain def | works |
| `def m(self, a, *rest)` — ordinary method | works |
| `def __init__(self, *args)` | **segfault** |
| `def __init__(self, a, *rest)` | **segfault** |

The two working twins are what said the packing machinery is fine and one path
skipped it — `devdocs/dev/normalise-dont-special-case.md`'s shape exactly.

### Cause

`PyClassCreate` assembles the construction call itself — GetMem size node, then
the user arguments — and, as its own comment already said about the DEFAULTS
loop, "never passes through the shared path". That shared path is also where
`PyPackStarArgs` runs, so the surplus arguments were emitted as ordinary
positionals and the callee read one of them as its packed `TPyList` pointer.

A probe settled it in one build: instrumenting `PyPackStarArgs` to Error on
entry, compiling the repro produced **no error at all** — the packer was never
reached, rather than reached with wrong indices.

### Fix

`PyPackStarArgs` gained a `selfSlots` parameter and `PyClassCreate` calls it
with 1.

That offset is the whole subtlety. Everything in the packer counts in PARAMETER
space — `si`/`ki` are signature indices, the container node carries an explicit
slot, `PyFillDefaultsUpTo` walks slots — except `pos` and `nKept`, which are
derived from the argument chain. A method call carries Self as the chain's first
node so those already line up; a construction does not, so both now start at
`selfSlots`. Without it even the star-only ctor stayed broken, because
`pos >= si` compared a chain position against a signature index counting Self.
Every pre-existing call site passes 0 and is unchanged.

Packing runs before the trailing-defaults loop, which then finds the slots
filled and does nothing — the packer fills the gap itself, keyword bindings
included.

### Verified

`test/test_nilpy_star_args_ctor.npy` (`.expected` from CPython), wired into
`make test-nilpy`: star-only at arities 0-3 (and `type(args).__name__` is
`tuple`), one and two fixed parameters before the star, a DEFAULTED parameter
before it (omitted, given, overrun), and the plain-`def` and ordinary-METHOD
twins kept as the controls that name which path was short.
Gate: `tools/gate.sh quick` GREEN + `make test-nilpy`.

### Found in the same sweep, filed not fixed

[[bug-nilpy-kwargs-and-star-unpack-at-a-construction-are-refused]] — `C(**kw)`,
`C(*xs)`, and a keyword colliding with a same-named field when the ctor takes
`**kw`. Same cause one step further along (the construction path still does not
reach the kwargs container or the call-site unpack), but all three are a
DIAGNOSTIC rather than a crash, so they are their own ticket at a lower
priority.

Also seen and not filed: `self.args = args` — storing the star tuple in a field
— reports "cannot infer the type of field self.args". That is field-type
inference for a star parameter, which is [[feature-n-nilpy-ast-typing-module-scope]]'s
territory rather than an argument-passing bug.

## Log
- 2026-08-11 — resolved, commit PENDING-COMMIT.
