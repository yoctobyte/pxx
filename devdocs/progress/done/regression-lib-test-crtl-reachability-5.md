---
prio: 70
track: C
status: done
---

> **Track guessed as C** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/master has advanced 16 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:tools/crtl_reachability.py red at 7227f3e0f1f8 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T19:49:31Z
- **Test source:** tools/crtl_reachability.py tools/gen_crtl_map.py +37

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:tools/crtl_reachability.py'` at 7227f3e0f1f8343547d85f7fc3a32c2f440686dd

## Range
> **The named sha `7227f3e0f1f8` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `7227f3e0f1f8`, last good `d24df3f09efb`, **27 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
lib track pinned to: stable_linux_amd64/default/pinned -> stable_pinned   (newest checkpoint: latest -> stable_latest)
frozen builtin RTL: stable_linux_amd64/default/builtin/ (11 src) -- isolates track A's compiler/builtin/ edits
=== lib-test: library smoke against stable_linux_amd64/default/pinned ===
crtl-reachability: 2 unreachable declaration(s)

  <sys/wait.h> declares wait(), defined in unistd.c
  <sys/wait.h> declares waitpid(), defined in unistd.c

A program that includes only that header will NOT get the definition.
It will silently import the symbol from the system C library instead.
Fix by one of: move the definition to the header's sibling .c; make the
header include the header whose sibling .c defines it; or add a bridge
sibling .c that does nothing but include that header (see
lib/crtl/src/sys/socket.c for the guard-order trap that shape has).

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## 2026-08-30, frankA — already fixed at HEAD; closing on evidence, not on a green

Reproduced the tool, not the tier: `python3 tools/crtl_reachability.py` at
current HEAD prints
`OK -- 42 headers, 26 modules, every declared function reachable from its own header`,
exit 0. The two rows this ticket names — `wait()` and `waitpid()` declared in
`<sys/wait.h>` and defined in `unistd.c` — are gone.

**Attributed by artifact rather than by ancestry**, which is the check that
cannot be asked backwards:

```
git log --diff-filter=A -- lib/crtl/src/sys/wait.c   -> 42f7a4040
git show 7227f3e0f1f8:lib/crtl/src/sys/wait.c        -> does not exist
```

So `lib/crtl/src/sys/wait.c` was **created after** the tested sha, and it is the
sibling `.c` the tool's own message asks for. The fault and the fix are both
established from the tree; nothing here rests on a bisect, which this ticket
already records as unsound (the named sha builds with `$(PXX_STABLE)` and moved
no `stable_linux_amd64/**`).

**Not claiming a green tier.** `lib-test` is full-tier and this session does not
run it; what is verified is the exact check that produced the signal, which is
the tool itself.

**The track guess was right for the wrong reason.** The ranker read `C` off the
test path `tools/crtl_reachability.py` — a Python tool, which is Track T's file.
The defect was in `lib/crtl`, so `C` is correct, but the path it was inferred
from points at the wrong lane. Worth knowing when the next auto-filed stub lands.
- 2026-08-30 — resolved, commit PENDING-COMMIT.
