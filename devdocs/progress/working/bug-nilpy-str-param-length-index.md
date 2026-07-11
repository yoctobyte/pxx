---
prio: 55  # auto — hard-blocks feature-demo-portable-userland phase 1 (any string fn)
---

# NilPy: `str` parameter breaks Length / indexing / codegen

- **Type:** bug (frontend — Nil-Python; obeys Track A's gate like the Pascal
  frontend)
- **Track:** A (`compiler/pyparser.inc` / NilPy str-param lowering)
- **Status:** working
  shell ([[feature-demo-portable-userland]] phase 1).
- **Owner:** opus-a

## Symptom (three faces, one root)
A `str`-annotated function parameter is not a working string inside the body.
Locals initialized from string LITERALS work; the same operations on a param
(or on a local copied from a param) fail. Verified identical at stable v194 and
HEAD (a4f1261c-era).

1. **`Length(param)` returns garbage** (compiles, wrong value):
```python
def f(line: str) -> int:
    n = Length(line)
    return n
print(f("ab"))        # prints 1, want 2
```
2. **`param[i]` segfaults at runtime**:
```python
def g(line: str) -> str:
    c = line[1]
    return c
print(g("ab"))        # SIGSEGV
```
   Copying to a local first (`s = line; c = s[2]`) segfaults the same way —
   the local inherits the param's representation.
3. **Compile-time ICE** when the two combine in a scanning loop:
   `pascal26:N: error: Unsupported linear node in IR codegen` — repro: a
   function with `n = Length(line)` + `c = line[i]` in a while loop (the
   `tok()` helper in `examples/shell/shell0.npy`).

Note `return line` (pass-through, r2-style) and `print(param)` DO work — the
breakage is specifically treating the param as an indexable/measurable string.
Suspicion: NilPy `str` params lower to a different representation (char? raw
pointer without length?) than string locals/literals, and Length/index pick
the wrong path.

## Impact
Any NilPy function that processes a string argument — i.e. every helper in the
[[feature-demo-portable-userland]] shell (`examples/shell/shell0.npy` is
committed blocked on this). Also likely behind the sysutils-import failure
(`import sysutils` → "array of const requires the builtinheap unit"), filed
separately if it survives this fix.

## Gate
`make test` + self-host byte-identical. Land `.npy` regression tests for all
three faces; `examples/shell/shell0.npy` compiling and running is the
end-to-end check.

## Links
Blocks [[feature-demo-portable-userland]] · sibling gap
[[feature-nilpy-collections-and-string-methods]].
