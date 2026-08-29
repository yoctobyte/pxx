---
prio: 70
track: N
status: done
owner: frankA
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_str_ascii_cache.npy red at a6698ac28e8b (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-29T19:00:03Z
- **Test source:** test/test_nilpy_str_ascii_cache.npy tools/expect_same.sh +1

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_str_ascii_cache.npy'` at a6698ac28e8b5dd3a62c2fd79b0c1d8b5c4be12a

## Range
> **The named sha `a6698ac28e8b` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `a6698ac28e8b`, last good `ee62e6dc0582`, 17 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1154419/test_nilpy_asciicache26  [code=1258808B  data=55220B  bss=50652B  procs=1859]
expect_same: MISMATCH [test_nilpy_asciicache26.2]
--- expected
+++ actual
@@ -6,7 +6,7 @@
 2 False ['é', 'l']
 True 0
 5 x True
-3 é False
+6 � True
 ['a', 'b', 'c', 'd', 'e', 'f'] ['h', 'é', 'l', 'l', 'o']
 500 50
 100 25 é é

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

---

## RESOLVED 2026-08-29 (frankA) — mine, and the quick gate could not have caught it

**I caused this**, in `8be3c6d06` (the NilPy empty-string fix,
[[bug-nilpy-empty-str-and-none-are-the-same-value]]). Attributed by measurement,
not by proximity: rebuilt with `PXX_NILPY_STR` neutralised and the test passes;
restored, and it fails. The watcher's `last good ee62e6dc0582` is the commit
immediately before mine, which pointed the right way.

The same probe **exonerated my change of the other two NilPy reds** ranked
beside this one — `test_nilpy_parent_call_after_instantiation` and
`test_nilpy_relative_import_in_package` fail with the define ON *and* OFF, so
they are pre-existing and still open. Worth stating because three NilPy reds
appearing together after one NilPy commit is exactly the shape that gets all
three attributed to it.

## Mechanism — a stale cache my change made reachable

`pystr_repeat` (pylib.pas) builds its result as:

```pascal
  Result := '';
  ...
  SetLength(Result, total);      { then per-byte writes }
```

- **Before:** `Result := ''` published **nil**. `SetLength` on a nil slot always
  took the ALLOC branch, which builds a fresh block through `PXXHdrInit` →
  `PXX_KIND_LEGACY`, i.e. *ASCII not looked at yet*. A later `isascii()`
  rescanned and answered correctly.
- **After:** `Result := ''` is a real zero-length block stamped
  `PXX_FLAG_ASCII_KNOWN | PXX_FLAG_ASCII` — **true of a zero-length string, and
  the claim is honest when it is made.** `SetLength(Result, 6)` then finds a
  unique block with spare capacity and takes the x86-64 **in-place** branch,
  which updates the length and the nul terminator and *leaves the meta word
  alone*. Six bytes nobody described now carry a claim made about zero bytes.

`"é" * 3` therefore answered `isascii()` **True** and `len()` **6** instead of
3 — the character path keys on exactly that flag to decide whether character
offsets equal byte offsets, which is this test's whole subject.

## Fix — invalidate at the resize, not at the literal

The tempting one-liner is to stop stamping ASCII on a zero-length block. That is
a microfix: it papers over an in-place resize that preserves a cached answer
about bytes it just replaced, and leaves the same staleness reachable by any
`SetLength` growth on a known-ASCII block.

So the fix clears `ASCII_KNOWN|ASCII` in the header at the **in-place growth
branch** (`ir_codegen.inc`), returning the block to "not looked yet" so the next
query rescans. The alloc branch needs no equivalent — `PXXHdrInit` already
stamps LEGACY. x86-64 only, because x86-64 is the only backend that inlines the
symbol-target resize; every other backend calls `PXXStrSetLen`, which allocates
a fresh block. **That is the same asymmetry that made site 3 of the original fix
necessary**, showing up a second time in one day.

**The latent bug is older than my change and outlives this ticket:** a
Pascal-mode `SetLength` growing a known-ASCII string and then writing high bytes
through `s[i]` had the same staleness. It was unreachable in practice only
because the empty-string collapse meant builders started from nil. Now fixed for
everyone, not just NilPy.

## The gate lesson, stated against myself

`tools/gate.sh quick` was **GREEN on the commit that introduced this**, and it
would be green again — that tier runs 29 Pascal/C jobs and **zero `.npy` jobs**.
I measured that gap and reported it to the coordinator hours before writing this
regression, then landed a change to the NilPy string model behind that same
green. Knowing a gate's blind spot is not the same as compensating for it.

What would have caught it, and what I will do next time: **when a change is
scoped to one language by construction, run a handful of that language's tests
by name.** I ran ten NilPy tests for `8be3c6d06` and picked them by *string
method* — `str_methods`, `format`, `adjacent_string_literals` — none of which
exercised the ASCII/character-count path. `test_nilpy_str_ascii_cache` is
named for the mechanism I changed. Choosing canaries by the MECHANISM touched,
not by the topic, is the cheap version of breadth.

## Verification

- `test_nilpy_str_ascii_cache` passes; the expectation is unchanged.
- The other two NilPy reds still fail identically with the define off — not
  attributed here.
- The original fix's evidence re-run and still green: the 12-row `is None` repro
  and the 19-row empty-string semantics sweep both match CPython;
  `test_nilpy_none_str_field` and `test_forward_decl_case_insensitive` pass;
  Pascal's empty string still collapses to nil.
- `make compiler/pascal26` converged; `tools/gate.sh quick`.
- 2026-08-29 — resolved, commit 6b6190d2c.
