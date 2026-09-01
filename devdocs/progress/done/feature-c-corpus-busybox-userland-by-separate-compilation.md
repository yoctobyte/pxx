---
slug: feature-c-corpus-busybox-userland-by-separate-compilation
title: "A busybox userland built busybox's own way: one object per translation unit, a real link, no unity"
track: C
prio: 70
type: feature
status: done
created: 2026-09-01
found-by: frankD
owner: frankD
blocked-by: []
summary: "MET 2026-09-01 on x86-64. `tools/busybox_diff.sh --separate` builds the 26-applet userland as busybox builds it -- 82 translation units, 82 objects, ONE REAL LINK with no -Wl,-z,muldefs -- and the result is byte-identical to the gcc oracle over 154 cases. That is this ticket's own gate: match the unity before exceeding it. Cost two fixes found by attempting it, both filed and closed: crtl was defined globally in every object (frankA), and `static` on a C FUNCTION was ignored by the object writer so every TU exported libbb.h's private helpers (bug-a-static-c-functions-are-emitted-as-global-symbols). aarch64 stays OUT until --emit-obj has an object writer for it; GROWING the applet set past 26 is rung 3's business, not this ticket's."
---

# Busybox the way busybox builds

[[feature-c-corpus-busybox-multi-applet]] is done. It resolved at twelve
applets; the unity has since been pushed to **twenty-six applets, 82
translation units, 154 cases, byte-identical to gcc on x86-64 and aarch64**.
It got there on a UNITY build, and the unity is still the wrong long-run model.

## Why the unity cannot be the answer

Not capacity — twenty-six is a lot more than the twelve this section was
written about, and the argument did not depend on the number. Three busybox files assume they own their
namespace, and **gcc rejects the unity too**, so none of this is a pxx defect:

| file | what it claims | who it breaks |
| --- | --- | --- |
| `include/common_bufsiz.h` | `enum { COMMON_BUFSIZE = 1024 }`, no include guard | `ls`, `tail` |
| `shell/ash.c` | 40 `#define`s of ordinary names (`optlist`, `eflag`) | whatever follows it |
| `coreutils/uname.c:112` | `#define options "snrvmpioa"` | whatever follows it |
| `coreutils/test.c` | globals macros over ordinary identifiers | `ash`, in BOTH orders |

The harness orders around the second, refuses the fourth, and can do nothing
about the first or third. Every applet added from here meets more of them.

**Measured at scale 2026-09-01, and this is the number that settles it.** A
34-applet unity (the twelve plus `grep sed sort touch chmod ln du df sync env
dd tr cut basename dirname readlink true false seq tee md5sum stat`) does not
compile AT ALL, and every error is **gcc's**:

```
./coreutils/du.c:104:1     redefinition of struct or union 'struct globals'
./findutils/grep.c:196:1   redefinition of struct or union 'struct globals'
./editors/sed.c:172:1      redefinition of struct or union 'struct globals'
include/common_bufsiz.h:1  redeclaration of enumerator 'COMMON_BUFSIZE'   (x8)
./coreutils/dd.c:399       #define skip (Z.skip) -- expanded inside shell/ash.c
./coreutils/cut.c:57       two or more data types; conflicts with /usr/include/regex.h
./libbb/ptr_to_globals.c   conflicting types for 'ptr_to_globals'
```

`struct globals` is not an edge case — it is busybox's STANDARD pattern, one
per applet, and a unity can hold exactly one. `dd.c` defining `skip` and having
it expand inside `ash.c` is the ash-macro problem in the other direction, and
no include order fixes a pair that each claim the other's identifiers.

So the unity's limit is not twelve and not any number: it is one applet per
namespace-claiming pattern, and busybox's whole design is that pattern. This
is why the rung is separate compilation and not "more applets".

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

## MET 2026-09-01 — x86-64

```
busybox-diff: applets=cat echo ash mkdir rm cp mv pwd wc head sleep printf sort
              chmod ln sync env tr cut basename dirname readlink true false seq
              md5sum   translation units=82
  ORACLE  gcc unity build (154 cases)
  ORACLE  busybox agrees with the gcc unity
  note    x86_64   82 objects linked separately (27765544 bytes)
  PASS    x86_64   byte-identical to the gcc oracle over 154 cases
  note    aarch64  skipped: --emit-obj has no object writer for this target
busybox-diff: GREEN
```

compiler `816f18f7784d`. `-Wl,-z,muldefs` is **gone** from the harness rather
than merely unneeded — the flag was the thing hiding the second bug.

Against the four completion bullets above:

1. The blocker landed (frankA) and `-z muldefs` came out. That exposed the
   SECOND link failure, which the flag had been suppressing all along:
   `multiple definition of bb_ascii_isalnum / bb_strtoi32 / is_tty_secure /
   new_tls_state` — `static` functions in `include/libbb.h`, emitted GLOBAL.
   Filed and fixed as
   [[bug-a-static-c-functions-are-emitted-as-global-symbols]].
2. `--separate` is GREEN against the oracle on the **twenty-six** applets the
   unity does, not the twelve this ticket was written against. Gate met.
3. Growing the applet set is rung 3's.
4. aarch64 unchanged: out until
   [[feature-a-object-output-for-arm32-and-aarch64]].

**Worth keeping:** the errno/optind divergence this ticket was mostly about is
gone, and the smoke test would never have told anyone. `--list`, `echo` and
`ash` arithmetic were all correct through both bugs. Only the 154-case
differential moved.
