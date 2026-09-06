---
track: A
prio: 40
type: bug
blocked-by: []
status: backlog
tags: [wasm32, nilpy, cross-target, naming]
summary: "A NilPy program containing `def main()` fails to build for wasm32 with `wasm: duplicate export \"main\" — two different slots (1770 and 1777) want one name`, and builds clean for every other target. The user's function and the module's entry point are both exported as `main` and nothing renames either. `main` is the single most likely name in a Python program, so this is not an edge case; it is the first thing a newcomer writes."
---

# A NilPy `def main()` is refused on wasm32 only

## Reproducer

```python
def main():
    print(1)

main()
```

```
$ pascal26 --target=wasm32 m.npy m.wasm
pascal26:4: error: wasm: duplicate export "main" — two different slots (1770 and 1777) want one name
  near:   main ( )  >>>
$ pascal26 m.npy m            # every other target
ok: m  [...]
```

Renaming the function to anything else builds and runs. Found while building a
census fixture for the object-local leak (d58828d8c) — the fixture had to be
renamed `run()` to compile, which is how this surfaced.

## What is claimed and what is not

CLAIMED: the build is refused, on wasm32, for this source, and is not refused
on x86-64. Measured at d58828d8c.

NOT claimed: which of the two slots should yield. That is the actual design
question and it is not obvious from outside — the wasm entry point is exported
as `main` because a WASI host calls it, and a NilPy user function named `main`
is an ordinary user symbol that happens to collide. Either the entry export
takes a reserved internal name, or user exports get a namespace. Both are
choices about the module's public surface, so the answer belongs with whoever
owns wasm32's export table.

## Why it ranks where it does

Not a wrong answer and not a leak — a clean refusal, which is the good failure
mode. But it is a refusal of the most ordinary program shape in the language on
exactly one target, and the whole point of the cross axis is that a program
compiling on one target and not another is the defect. It is also almost
certainly cheap: one name, one table.
