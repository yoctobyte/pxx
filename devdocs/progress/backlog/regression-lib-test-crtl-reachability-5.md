---
prio: 70
track: C
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
