---
prio: 70
track: A
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

---

## SECOND SITE 2026-08-29 (claude-N) — the same defect, one blob over

Worked in parallel with frankA (the coordinator dispatched this ticket twice;
see the note at the end). frankA's `df19c72a7` is correct and is the fix for the
reported red. This section is the part it does **not** reach, measured against
`df19c72a7` itself rather than reasoned from the diff.

The section above closes with:

> **The latent bug is older than my change and outlives this ticket:** a
> Pascal-mode `SetLength` growing a known-ASCII string and then writing high
> bytes through `s[i]` had the same staleness. ... **Now fixed for everyone**,
> not just NilPy.

True of the `SetLength` route, and that route is fixed. But the staleness does
not need a `SetLength` at all:

```pascal
a := 'abc';        { known = 1, ascii = 1 -- honest }
a[1] := Chr(200);  { still known = 1, ascii = 1 -- a lie, and the fast kind }
```

Built at `df19c72a7`, that block still claims ASCII while holding a byte >= $80.

### Why — a third helper x86-64 inlines past

`PXXStrUnique`'s own comment states the invariant the cache rests on:

> the caller is about to WRITE bytes through the handle we return, so any cached
> ASCII answer stops being true ... **this is the single choke point for byte
> mutation, which is what makes the cache sound.**

It is that choke point on i386 / arm32 / aarch64 / riscv32 / xtensa, which all
`FindProc('PXXStrUnique')`. **x86-64 has never called it.** Indexed writes reach
`AnsiStrUniqueAddr`, a hand-emitted blob in `ir_codegen.inc`, which does the
refcount check and the clone and never touches the meta word. The clone arm
needs the clear as much as the in-place arm, because `AnsiStrFromLiteral` stamps
the flag from the **old** bytes — which is exactly why the Pascal version
forgets at *both* of its exits.

So this is the same asymmetry the section above names twice ("the same asymmetry
that made site 3 of the original fix necessary, showing up a second time in one
day") — appearing a **third** time, in the one place whose comment claims to be
the reason the whole cache is sound. The pattern is now specific enough to state
as a rule: **when a `builtinheap.pas` helper's comment asserts an invariant,
check whether x86-64 calls it.** Three of three so far did not.

### Fix

`AnsiStrUniqueAddr` clears `ASCII_KNOWN|ASCII` on the handle it returns, at the
single shared exit, guarded on nil (`done_nil` returns 0). `PXX_ASCII_CACHE_BITS`
in `defs.inc` names the mask, in the style of `PXX_OBJ_MAGIC_TAG`, with the
"MUST match builtinheap.pas" note. **Follow-up for A, deliberately not done
here:** `df19c72a7` spells the same mask as four literal `EmitB`s; folding that
site onto the constant would leave one spelling instead of two, but those lines
landed minutes ago in a file another agent is live in, so it is not mine to
touch mid-flight.

### What the existing pin could not see

`test_managed_block_meta.pas` already claimed to cover this:

```pascal
Check(not IsAscii(both), 'inline-allocated string carries no flag (unknown)');
```

`IsAscii` reads only `PXX_FLAG_ASCII`, which is False for **both** "scanned, has
high bytes" **and** "nobody looked". The assertion could not distinguish the
state it names from the state that is the bug, so it passed throughout against a
block stamped KNOWN and non-ASCII. An assertion whose two outcomes are the
answer and the defect pins nothing.

Added `IsAsciiKnown`, strengthened that assertion, and added two cases: a bare
indexed store with no `SetLength` near it, and an in-place `SetLength` grow.
**All five fail against `stable_linux_amd64/default/pinned`**; the two
indexed-store ones **also fail at `df19c72a7`** and pass after this change,
which is what separates the two sites.

### Verification

- `test_managed_block_meta` green; the 2 new indexed-store assertions confirmed
  RED at `df19c72a7` and green after.
- `test_nilpy_str_ascii_cache` green.
- Three shape probes (repeat by count, by source shape, by result byte length
  2..13) byte-identical to **live CPython**.
- The cache still pays: reads never invalidate, only writes do, and NilPy strings
  are immutable — indexing all 200k characters of a long ASCII string runs in
  **0.10s** against CPython's 0.09s.
- Self-host fixedpoint converged, `9133bfccd790`.
- `gate.sh quick`: `testmgr --tier quick` PASS (201s). Its one FAIL is the FPC
  seed canary on `rparser.inc`'s duplicate forward — pre-existing, Track R's
  file, already filed by frankA at p85.
- x86-64 only. The other five backends call the helper; stated from the call
  sites, not measured.

### Coordination note

Two agents held this ticket at once. No source conflict occurred — the rebase was
clean and the two fixes are at different sites — but the duplicate SetLength
clear I had written was discarded in favour of `df19c72a7`, which landed first.
Flagged to the coordinator: the ticket's auto-guessed `track: N` (taken from the
`.npy` test source) is what let it be dispatched as a frontend item when the
defect and the fix are both **Track A** shared-backend files, and the sole-A
guard keys off that field.
