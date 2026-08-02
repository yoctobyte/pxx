---
summary: "A one-off `Text file busy` on exec red the self-host chain job; selfhost is single-shot by policy, so a harness-level OS race is indistinguishable from real compiler nondeterminism"
type: bug
track: T
prio: 60
status: done
owner: claude@xeon
---

# ETXTBSY on exec permanently reds a single-shot self-host job

- **Type:** bug (Track T — retry policy / harness race)
- **Found:** 2026-08-02 05:10Z, `test-core#src:compiler/compiler.pas@1` at
  `1476a0162fb9`.

## What happened

The self-host chain built `pascal26-next`, then failed executing it:

```
ok: .../pascal26-next  [code=6020619B ...]
ok: .../next-string_compare26 ...
sh: 99: /tmp/testmgr-scratch-3862724/pascal26-next: Text file busy
```

`ETXTBSY` — the kernel refuses to `exec` a file some process still holds open
for **writing**. Not a compiler fault: nothing was miscompiled, and every
artifact before it reported `ok`.

**Transient and confirmed so:** one occurrence in the entire daemon log, and the
same job re-run at HEAD **passes in 68.5s**.

## Why it produced a RED rather than a retry

`selfhost` is deliberately excluded from `RUN_RETRY_CLASSES`, and the reasoning
in `testmgr.py` is sound as written:

> `selfhost` (build + byte-identical fixedpoint, where a flake is a genuine
> nondeterminism bug to reseed, not retry) — stays SINGLE-SHOT.

That is right for **compiler** nondeterminism. `ETXTBSY` is not that: it is an
OS-level exec race in the harness, it says nothing about the binary's contents,
and it cannot recur deterministically. Single-shot turns a harness race into a
permanent red on the tier that gates every push.

## Contributing factor — my own changes, stated plainly

Two changes landed 2026-08-01 that raise concurrency, and both make an
fd-inheritance race strictly more likely:

- cgroup `MemoryMax` 8G → 36G (`ba3249e34`), so more jobs are admitted at once
- `OPT_SHARDS` 6 → 12 (`6ba5d0e9e`)

The classic ETXTBSY mechanism is exactly concurrency-sensitive: process A opens
the binary for writing, process B `fork()`s and inherits the descriptor, A
closes but B's child still holds it, and the `exec` fails. More concurrent jobs,
more windows. This was the first occurrence in the log, so it is not proof — but
it is the honest first suspect and should not be discovered later as a surprise.

The snapshot ticket also predicted this exact failure while discussing hardlinks
vs copies: *"a reader can currently see a half-written binary or hit ETXTBSY."*

## Two fixes, different owners

**1. Root cause (recipe, not T's fence).** Write the binary under a temp name
and `rename()` it into place. Inside `RUN_TMP` that is a same-filesystem rename,
so it is atomic and produces a **new inode** — an exec can never observe a
partially written or still-open file. Note this works *because* `RUN_TMP` is one
filesystem; the top-level build's `mv $(BUILD_COMPILER) $(COMPILER)` crosses
tmpfs → ext4 and therefore degrades to copy-in-place, which is precisely why
that one truncates (measured in `feature-t-snapshot-compiler-binary-per-run`).

**2. Signature-scoped retry (Track T, mine).** Retry a single-shot job **only**
when the failure signature is `Text file busy` / `ETXTBSY`. This cannot mask the
thing single-shot exists to catch: a real fixedpoint mismatch or genuine
nondeterminism fails every attempt, whereas an exec race cannot. Blanket-retrying
`selfhost` would be wrong; scoping the retry to a signature that provably is not
about binary contents is not.

## Gate

Hard to force deliberately — that is the nature of it. Acceptance is that the
signature-scoped retry path is unit-tested against a synthetic `ETXTBSY`, and
that a real fixedpoint mismatch still fails on the first attempt with no retry.

## Log
- 2026-08-02 — **fix 2 (Track T's half) landed in `faa64cd4a`**: a
  signature-scoped retry that applies in ANY class, including the single-shot
  ones, gated on the failure text rather than on `job.cls`. Devtest
  `tools/testmgr_retry_signature_devtest.py` asserts both directions — a
  selfhost ETXTBSY retries, a selfhost fixedpoint MISMATCH does not.
- **It recurred before the fix landed**, which strengthens the case: a second
  hit at `b11e604f8043` red `test-smoke#src:compiler/compiler.pas`, so this is
  not the one-off the ticket originally described. Two gated reds in one day,
  both after `ok:` compile lines.
- **Fix 1 (root cause) is still OPEN and is not T's to make.** The recipe must
  write the binary under a temp name and `rename()` it into place — atomic
  within `RUN_TMP` (one filesystem) and a new inode, so an exec can never
  observe a file another process still holds open. Re-filed as
  [[bug-a-selfhost-recipe-should-rename-not-write-in-place]] so closing T's
  fence does not close the underlying race.

- 2026-08-02 — resolved, commit faa64cd4a.
