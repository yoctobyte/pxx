---
prio: 70
track: A
---

> **Re-tracked P -> A on 2026-08-20.** The stub guessed P from the test source
> (`compiler/compiler.pas`), but the subject is not the Pascal frontend: it is the
> compiler failing to reproduce itself when built in `--threadsafe` mode. That is
> core self-host/codegen — Track A.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:compiler/compiler.pas@2 red at 57b9b7148d32 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-20T03:46:12Z
- **Test source:** compiler/compiler.pas tools/progress.sh

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:compiler/compiler.pas@2'` at 57b9b7148d3290ac089cd9360c6e4553a4b44bfb

## Range
bad `57b9b7148d32`, last good `003d733936aa`, 7 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
/tmp/testmgr-scratch-3997779/pascal26-threadsafe-self /tmp/testmgr-scratch-3997779/pascal26-threadsafe-next differ: byte 97, line 1
(tail)
ok: /tmp/testmgr-scratch-3997779/pascal26-threadsafe-self.3999198.tmp  [code=8637667B  data=227176B  bss=211128564B  procs=2930]
ok: /tmp/testmgr-scratch-3997779/pascal26-threadsafe-next.3999198.tmp  [code=8637667B  data=227040B  bss=211128564B  procs=2930]
/tmp/testmgr-scratch-3997779/pascal26-threadsafe-self /tmp/testmgr-scratch-3997779/pascal26-threadsafe-next differ: byte 97, line 1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*


## Verified at HEAD — 2026-08-20 (sha `9156a7c37`)

**It still reproduces.** Run by hand rather than through a tier, so it costs ~90s
instead of a suite (the two compiles the Makefile job does, nothing else):

    ./compiler/pascal26 --threadsafe compiler/compiler.pas /tmp/ts-self
    /tmp/ts-self         --threadsafe compiler/compiler.pas /tmp/ts-next
    cmp /tmp/ts-self /tmp/ts-next        # differ: byte 97, line 1

Measured, and this is the part that narrows it:

| binary | built by | code | **data** |
| --- | --- | --- | --- |
| `ts-self` | `compiler/pascal26` (built WITHOUT `--threadsafe`) | 8637475 | **227072** |
| `ts-next` | `ts-self` (built WITH `--threadsafe`) | 8637475 | **227040** |

Same source, same `--threadsafe` flag on both compiles, **identical code size** —
the whole delta is **32 bytes of data**, and the only variable is whether the
*compiling binary* was itself built threadsafe. So this is not "threadsafe output
is wrong"; it is that a threadsafe-built compiler EMITS 32 data bytes fewer than
a non-threadsafe-built one does, for identical input. One of the two is wrong and
the flag is changing compiler behaviour it should not change.

Note `ts-next`'s data size (227040) is exactly the default build's, which suggests
`ts-self` is the odd one out — i.e. the non-threadsafe binary is emitting 32 bytes
the threadsafe one does not. Confirm that direction before hunting: 32 bytes reads
like four pointers or one small table/interned literal. `PXXDBG` and a data-section
diff of the two outputs will say what the bytes are; do not theorise it.

**Scope note it is worth being precise about:** the ordinary self-host gate did NOT
catch this and is not wrong — `make compiler/pascal26` and
`tools/selfhost_fixedpoint.sh` prove the fixedpoint at the DEFAULT flags, and both
are green at this sha (see the sibling ticket). This is the same class as the
`-O0`-only self-compile failure CLAUDE.md's claims section warns about: the
fixedpoint holds *at one build configuration*.
