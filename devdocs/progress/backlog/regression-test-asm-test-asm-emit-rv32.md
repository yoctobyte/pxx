---
prio: 70
track: A
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 9 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-asm#src:test/test_asm_emit_rv32.pas red at 108ac182bed6 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T05:56:04Z
- **Test source:** test/test_asm_emit_rv32.pas tools/expect_same.sh

## Repro
`tools/testmgr.py --tier native --job 'test-asm#src:test/test_asm_emit_rv32.pas'` at 108ac182bed6cd40244fd24108d6664d6cf1b2f0

## Range
> **The named sha `108ac182bed6` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `108ac182bed6`, last good `c951ec710b33`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:43: error: undefined variable (AIntToStr)
pascal26:44: error: expected comma or close parenthesis
(tail)
pascal26:43: error: undefined variable (AIntToStr)
  in: compiler/rv32enc.inc
  near:  what   displacement   AIntToStr >>>  v  
pascal26:44: error: expected comma or close parenthesis
  in: compiler/rv32enc.inc
  near: v    is outside the encodable range   AIntToStr >>>  lo  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## 2026-08-30 (coordinator) — RETRACKED P → A, on the error's own text

The auto-file guessed **P** from the test path, and the banner in this ticket says
plainly that the guess is what the ranker reads. The guess is wrong, and the
failing line says so without needing a repro:

```
pascal26:43: error: undefined variable (AIntToStr)
  in: compiler/rv32enc.inc
```

`AIntToStr` is defined in `compiler/util.inc`, pulled in at `compiler/compiler.pas:64`
— *"shared helpers owned by no frontend/backend"*. So this is **an include-order
fault in the compiler's own build, in a reduced configuration**: `rv32enc.inc`
calls a helper that is not in the stream yet. Nothing about it is the Pascal
frontend. Lane **A**, S-flavoured (riscv32 encoder); related to
`feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets`, which
already names this test.

**Why the retrack matters more than the fix here.** At `track: P` and `prio: 70`
this sat near the head of a queue whose agents own `pasparser_*.inc` and would
have opened it, found `compiler/rv32enc.inc`, and handed it back — while the lane
that owns the file never saw it. **A guessed track does not read as a guess in
`ready` output; it reads as a priced decision.** Retracked on the error text, not
on a hunch; if the guess was right after all, the evidence to overturn this is one
grep.

**Not re-verified at HEAD by me.** Track T reports it STILL-RED on every native
report from 06:57Z to 08:45Z, so it is standing rather than flaky, but the
attributing sha `108ac182bed6` is itself a `tstate-ticket(...)` commit — a
docs-only change that cannot have caused this. **A tstate red attributes to the
sha it swept, not the one that caused it.** Whoever takes this bisects; do not
start from that sha.
