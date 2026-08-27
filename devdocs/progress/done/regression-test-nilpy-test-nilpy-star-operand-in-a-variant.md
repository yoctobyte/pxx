---
prio: 70
track: N
status: done
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 9 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_star_operand_in_a_variant.npy red at 39d4afb022ce (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-27T12:49:48Z
- **Test source:** test/test_nilpy_star_operand_in_a_variant.npy test/test_nilpy_star_operand_in_a_variant.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_star_operand_in_a_variant.npy'` at 39d4afb022ce9a8f98f30f7a7202ccfa803b4d6f

## Range
> **The named sha `39d4afb022ce` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `39d4afb022ce`, last good `6b59df667fe4`, 12 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3793693/test_nilpy_starvariant26  [code=1280611B  data=56035B  bss=43292B  procs=1808]
Unhandled exception: TypeError: missing 510 required positional argument(s)
--- test/test_nilpy_star_operand_in_a_variant.expected	2026-08-15 08:40:36.359248422 +0200
+++ -	2026-08-27 14:42:25.734556755 +0200
@@ -7,8 +7,3 @@
 ('x', 'y')
 (1, 2, 3)
 (0, 1)
-xy
-(1, 2)
-17
-(4, 3)
-11 pq

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
- 2026-08-27 — resolved, commit a7c4d428d.

## Resolution (2026-08-27)

**Not a NilPy bug at all, and not caused by anything in the bisect range.** The
12-commit window is a red herring: the defect is a compiler zero-init hole that
has been there all along and is invisible on a clean stack, so any commit that
changes a stack frame in front of it makes it appear or disappear.

**Cause:** `ManagedLocalZeroBytes` (`compiler/pasparser_expr.inc:35`) is the one
table that answers "how many bytes must this managed local start zeroed". Its
AnsiString arm asks `IsArray` and multiplies by `ArrLen`; its **variant arm did
not**, returning `TypeSize(tyVariant)` — 16 bytes — for an array of any length.
So a local `array[0..3] of Variant` had element 0 zeroed and elements 1..3
holding stack garbage. A Variant's first word is its TAG, and every assignment
to one releases the old contents first — so when the stale tag read as a kind
the release path recognises, the first store decremented a refcount through a
payload the slot never owned.

This is `bug-a-a-local-array-of-interfaces-is-not-zero-initialised` one type
over: the same arm-shaped hole, the same "add an unrelated routine and it goes
away" red herring.

**The chain, measured end to end** (`test_nilpy_star_operand_in_a_variant`):

1. `fwd2([1,2])` forwards a star operand, leaving a heap layout in which a
   freed block's header overlaps where the next raw block lands.
2. `dyn(two, "xy")` builds a bound pair for `two` at `b`; `pybound_new_sig`
   stores `Sig = 0x5443A1` and reads it back correctly.
3. `PyBoundPairCallKwBody`'s own `av: array[0..3] of Variant` runs
   `for i := nPos to 3 do av[i] := pynone`. A gdb hardware watchpoint on
   `b+24` caught the write: `decq -0x10(%rax)` at `0x400345` with
   `rax = b+40` — the release stub, reached through the variant-release
   helper because `av[3]`'s stale tag was in the promo range (8192..8199).
4. `Sig` becomes `0x5443A0`. The dispatcher reads the signature ONE BYTE
   EARLY, so `two`'s `reqN`/`totN` (2 and 2) come back as 512 and 512, and a
   legal two-argument call is refused as
   `missing 510 required positional argument(s)`.

Step 4's arithmetic is the tell that made this findable: 512 = 2 shifted left
one byte, and `sr^.Code` came back as exactly `code * 256`.

**Every instrumentation hid it** — `-dPXX_HEAP_DEBUG`, `-dPXX_OBJTRACE`, and
each added probe — because each shifts the frame. The link-time address was
verified correct in the emitted `mov rax, imm64` (`0x544012` at code offset
1271731), which is what ruled out the fixup chain and pointed at a runtime
write.

**Fix:** the variant arm now mirrors the AnsiString one — `ArrLen *
TypeSize(tyVariant)` when `IsArray`.

**Gate:** `tools/gate.sh quick` GREEN (self-host fixedpoint `1dbc94c691aa`,
testmgr quick, FPC seed canary). Both auto-filed regressions green, plus the
eight NilPy tests from the bisect range's own commits.

**Test:** `test/test_variant_local_array_zero_init.pas`, registered in the
Makefile beside its interface-array sibling. It dirties its own stack so the
failure is deterministic. FPC 3.2.2 scores 8/8; the pinned binary scores 4/8.

**Also found while measuring, filed separately** (a genuine NilPy bug this
regression sat on top of): a STATIC star operand over a non-list iterable is
not converted — `f(*range(2))` passes zero arguments and `f(*b"ab")` passes
empty ones. `PyIterArgAsList` handles a str and a user iterable and returns
everything else untouched, so a TPyRange/TPyBytes object is stored into a
TPyList-typed slot. `zip(b"ab", ...)` has the same hole in `PyMakeIterOf`.
