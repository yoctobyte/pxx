---
slug: bug-t-the-sort-comm-locale-desync-has-now-been-found-three-times-independently
title: "`sort` collates by locale, `comm` compares bytes — three tools hit this separately and each fixed it locally"
track: T
prio: 40
type: bug
status: backlog
created: 2026-09-02
found-by: coordinator (sweeping a residual frankD named)
owner: ""
summary: "Under a UTF-8 locale `sort` ignores punctuation at the primary level while `comm` compares bytes, so a name containing `-`, `_` or `/` sorts into a position `comm` does not expect. comm prints `file 1 is not in sorted order` to STDERR and KEEPS MERGING out of step, so the caller gets a wrong answer and a zero exit. Three tools here hit it INDEPENDENTLY and each fixed it in place with its own explanatory comment: elf_alloc_same.sh, selfhost_stamp_devtest.sh, and busybox_diff.sh (44e7ea61f, today). All three are correct NOW. This ticket is that there is no shared helper and no lint, so the fourth caller will write the bug again — two is a smell, three is a design flaw."
---

# Three independent discoveries of one collation bug

Swept 2026-09-02 at `44e7ea61f`, after frankD named the residual rather than
claiming it: *"if any other tool here diffs two sorted name lists, it has this
bug until someone checks the locale. I have not swept for that."* This is that
sweep.

**Every `comm(1)` caller in the repo, and all three are correct today:**

| tool | state |
| --- | --- |
| `tools/elf_alloc_same.sh:62-72` | `LC_ALL=C` on both sorts and both comms, with a comment saying the first version left the locale alone |
| `tools/selfhost_stamp_devtest.sh:134-138` | `LC_ALL=C` on both sides and on comm, with its own comment |
| `tools/busybox_diff.sh:315,320,401-402` | `LC_ALL=C` as of `44e7ea61f`, with its own comment |

**Nothing else is exposed.** The remaining bare `sort` calls in
`busybox_diff.sh` either feed a display string (`:380`) or feed `cmp`/`diff`
with BOTH sides sorted by the same `sort` in the same process (`:577-581`,
the cat-only positive control) — one ordering compared against itself, which
is consistent regardless of locale. Checked, not assumed.

## The finding is the repetition, not any live defect

Three tools, three separate discoveries, three local fixes, three comments each
explaining the same mechanism to the next reader who will not be reading that
file. `elf_alloc_same.sh` records that its first version had the bug;
`busybox_diff.sh` found it today only because the desync happened to contradict
itself in one sentence — the same run printed a name under `ASKED FOR BUT NOT
BUILT` and under `BUILT BUT NOT ASKED FOR`.

**That tell is luck, not a property of the bug.** Any set difference over names
containing `-` or `_` can be quietly wrong with no contradiction to notice, and
`comm`'s complaint goes to stderr while its exit stays 0.

## Why it matters more than a tidiness fix

In `busybox_diff.sh` the check is a **GATE**: a wrong answer refuses a
legitimate applet set and the run never reaches the compiler. The failure mode
is a **phantom refusal**, not a wrong number in a report — the shape CLAUDE.md
names as a guard that answers instead of erroring.

## What would end it

One helper both ends call, or a lint that flags `comm` without `LC_ALL=C` on
the same line, or a `LC_ALL=C` export at the top of the tool scripts. Any of
the three; the point is that the fourth caller should not be able to write it.
**Not filed as a fix because all three sites are already correct** — this is
preventive and belongs to whoever owns the tooling's shared shell conventions.

Related: [[bug-a-i386-a-pointer-is-register-and-memory-resident-at-once-across-a-goto-entered-loop]] (RENAMED from `bug-c-busybox-mv-treats-an-existing-plain-file-destination-as-a-directory-on-i386` and re-laned C to A on 2026-09-02 in `fbe1e7809`, once the mv symptom was traced to i386 register allocation; this link was written against the old slug)
was re-laned away from this class after measurement; that ticket's history is
an example of the same "instrument answering about something else" family, not
an instance of this bug.
