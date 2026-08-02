---
track: B
prio: 40
type: feature
---

# The environment's write side — SetEnvironmentVariable, and the child sees it

- **Type:** feature (RTL) — **Track B** (`lib/rtl/sysutils.pas`)
- **Filed and landed:** 2026-08-02, re-filing decided policy into the owning
  lane. [[decide-env-write-side]] was resolved **2026-08-01** (option 3), but no
  implementation ticket was ever created, so — exactly like
  [[decide-ipv6-dualstack-and-aaaa-ordering]] the same week — the decided work
  sat in nobody's queue.

Its stated prerequisite,
[[bug-subprocess-spawns-child-with-empty-environment]], was fixed earlier the
same day (commit 11e6b3e19), which is what made this actionable.

## The decision, and why the pairing matters

> **Option 3.** Write to our own buffer, and teach the spawn path to pass it to
> `execve` — landed as one change, never option 2 alone.

Option 2 (process-local write only) was rejected specifically because it gets
`setenv` then spawn *silently* wrong, which this project treats as worse than a
missing feature. The spawn hand-off already existed as of 11e6b3e19, so this
change had only to make writes land in that same buffer.

## Implementation

`EnvVars` (the parsed `NAME=VALUE` records) is the single source of truth.
`GetEnvironmentVariable` already read it; `EnvironmentBlock` now rebuilds the
`execve` table from it on every call, so a write made since the last spawn is
included.

The table is rebuilt at use rather than maintained incrementally on purpose:
its entries are pointers into Pascal strings, and a string reassigned by a
write can move, so a table cached across a mutation could dangle. It is at most
1024 pointer stores.

Name matching stops at the `=`, so `PXX_P` does not match `PXX_PEXT` —
the classic prefix bug in this shape of code. Unset compacts the array, order
carrying no meaning in an environment.

## Verified — every assertion in PAIRS

In `test/lib_child_env.pas`, because asserting only what *we* see would pass
under option 2, the outcome the decision rejected:

| | self | child spawned after |
| --- | --- | --- |
| set | `hello` | `hello` |
| replace | `second` | `second` |
| unset | empty | empty |
| inherited `HOME` untouched | yes | yes |

Plus `PXX_P` / `PXX_PEXT` not matching each other, and unsetting one leaving
the other.

## NOT done here: the C side

`lib/crtl` has its own environment buffer, independent of this one, so C
`setenv`/`unsetenv` are a separate piece with a real hazard attached — see
[[feature-crtl-libc-gap-batch-2026-08]], which measured that crtl currently
exposes no spawn surface at all (so a C-local write is safe *today*) and records
the constraint for whoever adds one.
