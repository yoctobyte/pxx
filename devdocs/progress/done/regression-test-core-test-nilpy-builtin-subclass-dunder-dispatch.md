---
prio: 70
track: N
status: done
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_builtin_subclass_dunder_dispatch.npy red at c28e07a89f03 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-27T14:05:25Z
- **Test source:** test/test_nilpy_builtin_subclass_dunder_dispatch.npy

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_builtin_subclass_dunder_dispatch.npy'` at c28e07a89f036f56d3bb860e62045b1103e22aae

## Range
> **The named sha `c28e07a89f03` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `c28e07a89f03`, last good `0842d9684f7f`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:55: error: unexpected token
(tail)
Expected: ), but got: i (Kind: 1, Line: 55)
pascal26:55: error: unexpected token
  near: list  __getitem__  self  >>> i   

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

---

## Resolution (2026-08-27) — caused by 5a996b4b2, fixed in the same lane

**Mine, and Track T found it within the hour.** `5a996b4b2`
([[bug-n-the-zero-argument-form-of-a-builtin-type-constructor-is-rejected]])
gave `list`, `tuple` and `bytes` zero-argument overloads in `pylib.pas`, copying
the one `bytearray` has always had. This dialect lets a **parameterless function
be called by its BARE NAME**, so the bare word `list` became a complete call and

```python
list.append(self, x)          # how a subclass reaches the base it overrode
```

parsed as `list().append(self, x)` — an instance `append` handed two arguments:
`Expected: ), but got: x`.

### The fix, and why the mechanism was wrong rather than the code

Both jobs are green again. The three overloads are reverted and all seven
zero-argument constructors now answer in the PARSER, keyed on the
`name` `(` `)` **shape** — which by construction cannot capture a bare name, or a
name before a `.`. That is the property the pylib route could not have: an
overload is reachable by every spelling that resolves the name.

The containers build their zero value from `PyParseListLiteralT`, which parses
the same `(` `)` as an empty display, so no new pylib entry point exists whose
bare word could be called. `list()` and `bytes()` then have to undo that
parser's paren-implies-TUPLE stamp with `pylist_mark_list` — caught because the
verification checked `type(x).__name__`, not just `repr`.

Both regression tests now carry a matching row in
`test/test_nilpy_zero_argument_builtin_constructors.npy` (a `Stack(list)` whose
methods call `list.append` and `list.__getitem__` unbound), so the shape is
gated from the constructor side too and cannot come back through this door.

### What it exposed, filed separately

`bytearray.append(self, x)` was **already broken at v383** for exactly this
reason, and has been for as long as its overload has existed — nobody had
written that spelling. `bytearray` is deliberately left on its old path here
(its overload also stamps `FIsByteArray`, which the parser arm cannot reproduce
without a new pylib entry point, and routing it through changed
`repr(bytearray())` to `b''`).
[[bug-n-bytearrays-zero-argument-overload-makes-the-bare-name-a-call]]

### Note for Track T

The stub's range header was right and useful: it said the named sha
`c28e07a89f03` "CANNOT be the cause — it touches no buildable file", which
pointed straight at `5a996b4b2` one commit below. No bisect was needed.

Gate: `make compiler/pascal26` + `tools/gate.sh quick` GREEN, both named jobs
verified by hand against their inline expected strings.
- 2026-08-27 — resolved, commit PENDING-COMMIT.
