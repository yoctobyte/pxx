---
slug: feature-nodisx-toybox-and-a-posix-shell-built-by-pxx
track: C
prio: 70
type: feature
status: backlog
created: 2026-11-25
found-by: Nodisx (installer ISO), via claude session pixx-cc
tags: [nodisx, rainyday, c-corpus, toybox, mksh, recipe]
blocked-by: []
summary: "Nodisx compiles the installed system on the target with the pxx on the ISO; nothing but a small bootstrap set ships prebuilt. Item 1 of its pxx list: the base userland instead of busybox -- toybox (0BSD), every defconfig applet plus gzip, and a POSIX shell (mksh, MirOS licence) -- each a pinned source plus a recipe that builds on the target with only pxx, a shell and toybox-level tools, and a pass/fail test. Then (2) sfdisk/blkid, mke2fs, mkfs.fat compiled on site, (3) GNU make via its build.sh, (4) curl + mbedTLS + the CA bundle, (5) xz, zstd, bzip2, dhcpcd."
---

# Nodisx: toybox and a POSIX shell built by pxx

Asked 2026-11-24 by pixx-cc for Nodisx (`~/nodisx/docs/DESIGN.md`,
`docs/bootstrap.md`): an installer ISO for any kernel plus a compatible
userland, compiled on site. The recipes land in pxx (`tools/nodisx/`);
Nodisx consumes them. Constraint: no gcc, autoconf or make on the target;
what a build would generate with a host compiler is pre-generated on the
build host and shipped in the recipe, and the recipe says so.

The pixx desktop's on-site build (pxx c6be450156) uses from toybox: tar
(`--strip-components`, freetype-2.13.3's pax headers, xorgproto's old-format
tarball), gzip/zcat, sed, sort, grep, cut, find, stat, sha256sum, readlink,
cp, mv, chmod, mkdir.

## The list, in order

1. toybox + a POSIX shell -- this ticket's first part, done below.
2. sfdisk and blkid (util-linux, only those two), mke2fs (e2fsprogs),
   mkfs.fat (dosfstools), compiled on site. A hopeless one is reported, and
   pixx writes a small permissive replacement.
3. GNU make, built by pxx with no make present (its build.sh): Rainyday's
   kernel build needs make on site.
4. curl with mbedTLS (BearSSL as the fallback), the Mozilla CA bundle as data;
   HTTPS GET with TLS 1.3 and 1.2 (cdn.kernel.org, GitHub codeload).
5. xz-utils (xz, xzcat), zstd, bzip2, dhcpcd (or a verdict on toybox's dhcp).
   4 and 5 ship as binaries, so they need only build on the host with pxx.

## Item 1: done (recipes in `tools/nodisx/`)

`record.sh` then `test.sh`, from an empty `NODISX_WORK`, 2026-11-25:

| | pxx build | gcc build |
|---|---|---|
| toybox 0.8.15, defconfig + GZIP, 240 applets | 1604 PASS, 0 FAIL; 1.07 MB text | 1604 PASS |
| toybox tar `--strip-components` vs GNU tar | identical tree | -- |
| mksh R59c, `check.t` | 535 passed, same failures as gcc | 535 passed |

pxx fixes this needed (61174280ea): `case`/`default` labels inside an unbraced
`if` lost their statement (mksh mangled `"$(echo 'a b')"`); crtl `sigsuspend`
was ENOSYS (the shell hung on its first external command); `killpg`, `sig_t`;
file-scope `.section .comment` asm.

**The recipes compile with `--function-sections`.** Without it, each default
`--emit-obj` object keeps a private copy of crtl's `static` state: toybox's
`uselocale` in main.c did not reach `wcwidth` in fold.c (4 UTF-8 failures), and
`srand`/`strtok` do not carry across objects. That breaks the 2026-11-14
object-model decision (one copy of the state) and is a pxx bug of its own.
Also found: a `--link` program that returns from `main` skips its `atexit`
handlers (the synthesised `_start` never calls `exit`), and `--link -o <dir>`
reported success. Both are being fixed next; then the recipes move to
`--shared-runtime`, which the decision names for pxx's own builds and which
removes ~90% of each unit's compile time on site.
