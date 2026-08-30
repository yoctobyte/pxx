---
track: A
prio: 70
type: bug
status: done
owner: "frankA"
blocked-by: []
resolved: PENDING-COMMIT
summary: "`make pin` replaced the blessed binary with `cp ... stable_pinned`, overwriting IN PLACE the exact inode that `pinned` resolves to and that every $(PXX_STABLE) consumer executes. Measured: with a reader running, cp fails ETXTBSY -- and because the recipe was semicolon-chained, the pin then REPORTED SUCCESS, printed the OLD sha as if it were new, wrote a pin.log entry for a pin that never happened, and exited 0 so make saw nothing wrong. Fixed to cp-to-temp + mv (rename(2)), which is atomic and leaves the old inode untouched for readers already executing it."
---

# `make pin` overwrote the running `pinned` binary in place

- **Found:** 2026-08-30 by frank-rust, while checking for stray processes of its
  own before a pin lock closed. Relayed by the coordinator; fixed by frankA.
- **Trigger:** a `lib-test` run was five minutes into execing `pinned` when a pin
  was about to fire.

## The construct

```make
cp  $(STABLE_DEFAULT_DIR)/stable_latest $(STABLE_DEFAULT_DIR)/stable_pinned
ln -sfn stable_pinned $(STABLE_DEFAULT_DIR)/pinned
```

The `ln -sfn` is atomic and was never the problem. The `cp` is: `pinned` is a
symlink to `stable_pinned`, `PXX_STABLE ?= $(STABLE_DEFAULT_DIR)/pinned`, and
that variable has **255 references in the Makefile**. So the copy truncates and
rewrites the exact inode another session is executing.

## Measured, not reasoned — and the real failure is worse than the predicted one

A standalone sleeping binary was installed as `stable_pinned`, launched through
the `pinned` symlink exactly as `$(PXX_STABLE)` does, and the old recipe's
control flow replayed **verbatim** against it:

```
cp: cannot create regular file '.../stable_pinned': Text file busy
    pinned -> stable_pinned (v99, ddb749466801e3f...).
recipe exit status: 0            <- what make sees
was=ddb749466801  now=ddb749466801
binary actually replaced: NO
```

**The pin announced success, and nothing about the output says otherwise.** The
prediction was "the pin dies part-way"; it does not die at all. Because the
recipe is semicolon-chained, a failed `cp` does not stop the line, so:

- `ln -sfn` relinks `pinned` to the **unchanged** old `stable_pinned`;
- `SHA` is read from `pinned` **after** that, so the success line prints the
  **old** binary's sha as though it were the new one;
- `pin.log` gains an audit entry for a pin that never occurred;
- make sees exit 0 and the caller proceeds to `git add` and commit, blessing the
  **previous** binary under a new VERSION.

Every downstream check passes. This is the same shape as
[[bug-a-a-pin-that-adds-a-builtin-unit-cannot-commit-it-with-git-add-u]], fixed
hours earlier: the pin path being **correct by convention rather than by
construction**, and failing silently when the convention does not hold.

## The other outcome, and an honest limit on it

If no process is executing the inode at the instant of the `cp` but one execs
during the write, it can exec a partially written binary — surfacing as ordinary
test failures in a session that owns neither the pin nor the fault. That is the
expensive outcome and it is the *reason* the fix matters.

**It was not demonstrated here.** Truncating a binary and exec'ing it did not
reproduce a visible corruption in the one probe tried (the stump kept a valid
ELF header and exited 0), so this row is reasoned from truncate-then-write
semantics, not measured. The ETXTBSY path above is the one that actually occurs
when a reader is running, and it is measured.

## Fix

```make
cp $(STABLE_DEFAULT_DIR)/stable_latest $(STABLE_DEFAULT_DIR)/stable_pinned.new || \
  { rm -f $(STABLE_DEFAULT_DIR)/stable_pinned.new; \
    echo "pin: could not stage the new binary -- nothing moved"; exit 1; }
mv -f $(STABLE_DEFAULT_DIR)/stable_pinned.new $(STABLE_DEFAULT_DIR)/stable_pinned
ln -sfn stable_pinned $(STABLE_DEFAULT_DIR)/pinned
```

`mv` within one directory is `rename(2)`: atomic, and it does not touch the old
inode. A reader that started before the swap keeps executing the binary it
opened and finishes on it; a reader that starts after gets the new one; there is
no instant at which either sees a half-written file. Verified same-filesystem
(`/dev/sdb3`), which `rename(2)` requires.

The `|| ... exit 1` is the second half of the fix and closes the silent-success
path above: a staging failure now aborts the pin instead of announcing one.

Same replay, new recipe, reader running:

```
pinned -> stable_pinned (v99, 77bb02277a62...).
recipe exit status: 0
was=ddb749466801  now=77bb02277a62
binary actually replaced: yes
reader survived: yes
temp file left behind: none
```

## `stable_latest` — checked, and deliberately NOT changed

`stabilize-record` writes it with the same construct
(`cp $(TESTTMP)/pascal26-s5 .../stable_latest`). Checked rather than assumed
before widening: **nothing execs `latest` or `stable_latest`.** `$(PXX_STABLE)`
is `pinned`, and the only other reference is `pin` itself reading
`stable_latest` as a copy *source*. So the hazard needs a reader that does not
exist, and the pattern was not copied there. A comment on the `pin` target says
to re-check that before anyone does.

## Why a comment was left on the target

`cp` is the obvious spelling and `temp + mv` reads like ceremony, so the note
says explicitly why it is not, and names this ticket. Without it the next reader
simplifies it back.
