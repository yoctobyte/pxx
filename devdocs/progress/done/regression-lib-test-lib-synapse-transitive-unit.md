---
prio: 70
track: P
summary: "CAUSE FOUND AND FIXED IN TREE, JOB STILL RED — and it stays red until the next pin, because this job builds with $(PXX_STABLE). All three lib_synapse reds are ONE construct: `szDescription := '...'` on an `array[0..N] of Char` FIELD in synapse's ssfpc.inc. ASTCharArrayCap answered only for AN_IDENT, so the char-array-is-a-string conversion never fired for a field and the store was refused as `cannot assign ShortString to Char`. Fixed by bug-p-a-char-array-through-a-field-or-a-deref-is-not-a-string; all four synapse programs now build and match their expected output byte for byte under the tree compiler."
---

> **Track guessed as B from the FAILING STEP** — line 1 of 2, `stable_linux_amd64/default/pinned --mimic-fpc -Fuexternal/synapse -Fulib/rtl -Fulib/rtl/platform/posix test/lib_synapse_`, which names `test/lib_synapse_transitive_unit.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/lib_synapse_transitive_unit.pas at 889bfcf73256 in step 1/2, `stable_linux_amd64/default/pinned --mimic-fpc -Fuexternal/synapse -Fulib/rtl -Fulib/rtl/platform/posix test/lib_synapse…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5ea286a98481`).
  Untriaged.
- **Found:** 2026-09-01T21:55:48Z
- **Test source:** test/lib_synapse_transitive_unit.pas tools/expect_same.sh
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/lib_synapse_transitive_unit.pas`.
  ```
  stable_linux_amd64/default/pinned --mimic-fpc -Fuexternal/synapse -Fulib/rtl -Fulib/rtl/platform/posix test/lib_synapse_transitive_unit.pas /tmp/lib_synapse_transitive_unit
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/lib_synapse_transitive_unit.pas'` at 889bfcf7325633e2c400c82877a9ceef69a48800

## Range
> **The named sha `889bfcf73256` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `889bfcf73256`, last good `12c916c5c9ca`, **22 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
pascal26:0: error: incompatible types: cannot assign ShortString to Char
(tail)
pascal26:0: error: incompatible types: cannot assign ShortString to Char
pascal26:0: error: incompatible types: cannot assign ShortString to Char

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Triaged and fixed (frankZ, plexus, 2026-09-02) — one cause, three jobs

**Reproduced here for the first time.** `external/synapse` was absent on plexus,
which is why this and its two siblings sat wired to
[[umbrella-one-full-tier-run-with-no-red-tier]] as unreproducible. Fetched with
`tools/install_externals.sh` (synapse @ `b3224c3d133a`); all three reproduce on
the first try, with the identical error, and they are **one construct**.

`external/synapse/ssfpc.inc`, in `WSAStartup`'s `with WSData do`:

```pascal
szDescription  := 'Synsock - Synapse Platform Independent Socket Layer';
szSystemStatus := 'Running on Unix/Linux by FreePascal';
```

Both are `array[0..N] of Char` fields. `ASTCharArrayCap` — the ONE oracle the
char-array-is-a-string conversion asks, in both directions and at every site —
answered only for `AN_IDENT` while its header said it answered about a NODE. A
FIELD got -1, the conversion never fired, the store fell through to the scalar
type check and was correctly refused. Full write-up and the six-shape table:
[[bug-p-a-char-array-through-a-field-or-a-deref-is-not-a-string]].

Under the tree compiler (`090042338fc2deae`, `converged after 1 round(s)`), all
four synapse programs build and match their Makefile-expected output byte for
byte:

```
lib_synapse                  b64/b64d/md5/sha1/crc32/url/srv-got/cli-got — all 8 lines exact
lib_synapse_transitive_unit  ok
lib_synapse_ssl              3 x "=ok", last line "SYNAPSE-SSL OK"
lib_synapse_tls_loopback     harness/ssl/data/harness2/verify-rejects/verify-reason — TLS-LOOPBACK OK
```

The TLS one is not in this ticket's scope but is the same construct and is the
arm with teeth: a real handshake, and the second one requires the self-signed
cert to be REJECTED.

## THIS JOB IS STILL RED, AND WILL STAY RED UNTIL THE NEXT PIN

Its recipe line builds with **`$(PXX_STABLE)`** — `stable_linux_amd64/default/pinned`,
sha `954adef93a7b0e9e` — and the pinned compiler still contains the bug. Verified
directly: the pin rejects `test/test_char_array_field_is_a_string.pas` at three
lines, which is also that test's positive control.

So nothing in this tree can turn this job green. **Not resolved**, and
deliberately not: resolving it would claim a verdict the job cannot yet return.
It closes when the owner pins and the job goes green on its own. `make pin` is
irreversible and the owner's alone — nobody should take one to close a ticket.

## Log
- 2026-09-02 — auto-closed by the seven watcher: `lib-test#src:test/lib_synapse_transitive_unit.pas` passes at bb524e1abd1f (tier full); it was red at 889bfcf73256. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.

## Verified at the current pin (frankA, 2026-09-02)

The watcher's auto-close above is a GREEN, and a green in a job that has flapped
is not by itself evidence about the defect. This is the other half: all FOUR
synapse programs built with `$(PXX_STABLE)` = pin v400 (`6c184b4bcc37`) and run
against the Makefile's own expected text rather than against an exit code.

| program | |
| --- | --- |
| `lib_synapse` | eight lines, byte-identical to the recipe's `expect_same` |
| `lib_synapse_transitive_unit` | `ok` |
| `lib_synapse_ssl` | three `=ok` lines and `SYNAPSE-SSL OK`, both assertions |
| `lib_synapse_tls_loopback` | seven lines ending `TLS-LOOPBACK OK`, rc 0 — not 77, so it did not take the SKIP arm |

The fourth is run and reported even though no ticket names it, because the
summary says *"all four synapse programs"*.

**This ticket existed TWICE**, byte-identical apart from the auto-close Log
entry: `backlog/` and `done/`. The `backlog/` copy is removed. That is
[[bug-t-the-watcher-auto-close-copies-a-ticket-into-done-instead-of-moving-it]],
which predicted exactly this and says the mechanism will reproduce on the next
auto-close — it did, twice, on 2026-09-02, and the ranker was still offering the
`backlog/` copies as open work.
