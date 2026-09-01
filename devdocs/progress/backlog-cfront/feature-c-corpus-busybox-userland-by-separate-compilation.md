---
slug: feature-c-corpus-busybox-userland-by-separate-compilation
title: "A busybox userland built busybox's own way: one object per translation unit, a real link, no unity"
track: C
prio: 70
type: feature
status: backlog
created: 2026-09-01
found-by: frankD
owner: ""
blocked-by: [bug-a-every-object-defines-the-whole-of-crtl-globally-so-no-two-objects-link]
summary: "Rung 2's successor. The unity build tops out at twelve applets for reasons that are not pxx's -- three busybox files assume they own their namespace and gcc rejects the unity too. Separate compilation removes all of them and is busybox's OWN model: measured 2026-09-01, all 41 TUs compile to objects and link into a working multiplexer. It is NOT correct yet: crtl state is object-local, so errno and optind split per object and the binary diverges from the gcc oracle while still linking and running. Blocked on the crtl linkage ticket; `tools/busybox_diff.sh --separate` is the harness and already exists."
---

# Busybox the way busybox builds

[[feature-c-corpus-busybox-multi-applet]] is done and reached **twelve
applets, 114 cases, byte-identical to gcc on x86-64 and aarch64**. It got there
on a UNITY build, and the unity is the wrong long-run model.

## Why the unity cannot be the answer

Not capacity — it holds twelve fine. Three busybox files assume they own their
namespace, and **gcc rejects the unity too**, so none of this is a pxx defect:

| file | what it claims | who it breaks |
| --- | --- | --- |
| `include/common_bufsiz.h` | `enum { COMMON_BUFSIZE = 1024 }`, no include guard | `ls`, `tail` |
| `shell/ash.c` | 40 `#define`s of ordinary names (`optlist`, `eflag`) | whatever follows it |
| `coreutils/uname.c:112` | `#define options "snrvmpioa"` | whatever follows it |
| `coreutils/test.c` | globals macros over ordinary identifiers | `ash`, in BOTH orders |

The harness orders around the second, refuses the fourth, and can do nothing
about the first or third. Every applet added from here meets more of them.

## Where this already is

`tools/busybox_diff.sh --separate` exists and works. Measured 2026-09-01,
compiler `825c28a30c31`:

- **All 41 TUs compile to objects. Zero failures.** They link, and the binary
  runs: `--list`, `echo`, and `ash` arithmetic are all correct.
- It needs `-Wl,-z,muldefs`, for the blocker.
- It is **13.7MB**, because every object carries a full crtl.

Getting that far cost exactly one compiler fix: `x & 0` never folded to a
literal, so a constant-false branch kept its dead arm and
`make_human_readable_str` became a real external reference from
`coreutils/ls.c` (`3056e214c`). That was the only undefined symbol across all
41 units.

## Why it is not done, and it is NOT the link error

The link error is loud and is the blocker's business. The interesting failure
is quiet: the binary **links, runs, and diverges from the gcc oracle**.

```
< cat: can't open '.../missing.txt': No such file or directory
> cat: can't open '.../missing.txt'
> cat: can't open '-u'
```

crtl state is object-local with no linkage at all, so a program that touches it
**by name** reads its own untouched copy. The lost reason is split `errno`;
`-u` becoming a filename is split `optind`. Both are measured as two-object
repros in the blocker.

**Read that failure before adding applets here.** The smoke test — links, runs,
`--list`/`echo`/`ash` all correct — passed the whole time. Only the 62-case
differential caught it.

## What finishing this looks like

1. The blocker lands and `--separate` no longer needs `-z muldefs`.
2. `--separate` goes GREEN against the oracle on the twelve applets the unity
   already does. **That is the gate: match the unity before exceeding it.**
3. Then grow the applet set, which is what rung 3's image actually needs, and
   which the unity cannot do.
4. aarch64 is out until `--emit-obj` has an object writer for it
   ([[feature-a-object-output-for-arm32-and-aarch64]]). x86-64 only for now,
   and say so rather than letting `--separate` look like the stronger claim on
   both axes at once.
