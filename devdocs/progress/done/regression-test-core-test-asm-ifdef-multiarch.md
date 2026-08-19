---
prio: 70
track: P
status: done
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_asm_ifdef_multiarch.pas red at 498c6dea3f48 (auto-filed by twatch)

> **TRIAGED 2026-08-19 by the coordinator. Root cause found; it is NOT the test the title
> names, and the compiler is behaving as intended.**
>
> **The job covers TWO sources** — `test_asm_ifdef_multiarch.pas` *and*
> `test_asm_att_reject.pas`. The first compiles and runs clean (prints 42, exit 0) on both
> the v363 pin and a fixedpoint build at HEAD; the log tail in this stub is its success line.
> **The failing one is the second, and it is a compile-time NEGATIVE test:**
>
>     { This program is a compile-time negative test: it must FAIL to compile,
>       checked by the Makefile via `! ./$(COMPILER) ...` }
>     {$asmMode att}
>
> `76b6fb7f1 feat(P): tolerate {$asmMode} values and unit hint directives` made `{$asmMode att}`
> **accepted**, deliberately — the refusal moved to an actual `asm` block. So the negative
> test now compiles, the Makefile's `!` assertion fails, and the job goes red.
>
> **Measured both ways:** HEAD and v363 pinned each compile `test_asm_att_reject.pas`
> successfully. That is the intended new behaviour, so **the fix belongs in the test, not the
> compiler.** The test must be re-pointed at what is still refused: an actual AT&T `asm`
> block under `{$asmMode att}`. Do not "fix" the compiler back — that would undo a landed
> feature to satisfy a test whose premise it deliberately changed.
>
> **This is a recurring class, already recorded:** implementing a feature makes its own
> refusal test compile, and `gate.sh quick` cannot see it because these negative tests live in
> `test-core`, which quick does not run. **When a feature relaxes a refusal, grep for the
> `_reject` / `_fail` test naming it and retire or re-point the recipe in the same commit.**
> That is the second time today a `test-core`-only surface caught something quick could not.
>
> **Owner: Track P** (frank2 authored the change and knows where the refusal moved). This is a
> `test/**` edit and does **not** need the A/P slot, so it can land while the import refactor
> is in flight.

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-19T14:09:54Z
- **Test source:** test/test_asm_ifdef_multiarch.pas test/test_asm_att_reject.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_asm_ifdef_multiarch.pas'` at 498c6dea3f48816144fa8959a6534d131959a68c

## Range
bad `498c6dea3f48`, last good `7364f6c5bdfe`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1799398/test_asm_ifdef_ma26  [code=55229B  data=1528B  bss=9492B  procs=113]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Fixed 2026-08-19 — the test was re-pointed, the compiler was not touched

`test/test_asm_att_reject.pas` now carries an actual AT&T `asm` block under
`{$asmMode att}`, which is what the tolerance feature deliberately left
refused, and the Makefile's log assertion greps for the message that refusal
now prints:

```
pascal26:14: error: {$asmMode att} is accepted, but this asm block cannot be
read: inline asm (asm...end) is Intel syntax only
```

Verified against the v363 pin: the program exits 1 (so the recipe's `!` holds)
and the new `grep -q "asm block cannot be read"` matches. The bare directive
stays accepted, which is the behaviour `76b6fb7f1` was for.

**Class worth keeping:** a feature that relaxes a refusal makes its own
`_reject` / `_fail` test compile, and `gate.sh quick` cannot see it — these
negative tests live in `test-core`. Grep for the matching `_reject` test in the
same commit that relaxes a refusal.
- 2026-08-19 — resolved, commit 155b32957.
