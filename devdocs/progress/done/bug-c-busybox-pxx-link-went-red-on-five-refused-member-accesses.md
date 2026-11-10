---
slug: bug-c-busybox-pxx-link-went-red-on-five-refused-member-accesses
track: C
type: bug
prio: 60
status: done
owner: ""
created: 2026-11-10
found-by: claude (pxx session working on gibix, tools/busybox_diff.sh --pxx-link)
blocked-by: []
summary: "busybox_diff --pxx-link at the 394-applet scope went RED (5 of 521 TUs refused) after being GREEN on 2026-09-19. Not a codegen regression: the 2026-09-24 member check (134d68dfe3, 690d3859ff) started refusing accesses pxx used to read at offset 0. Causes: `__aligned__(N)` parsed as alignment 0 so the struct went OPAQUE (tls_sp_c32, wget), and crtl lacked st_atim/st_mtim/st_ctim (stat), ipc_perm.key + msg_cbytes (ipcs) and struct in_pktinfo (udp_io)."
---

# busybox --pxx-link went red on five refused member accesses

## Report

The gibix session ran `tools/busybox_diff.sh --targets x86_64 --pxx-link` on
tools/busybox-applets-394.txt with latest b368bf15 (commit 51fdc7bb): RED,
5 of 521 TUs failing to compile. The same scope was GREEN on 2026-09-19 with
compiler d43f5c29 (source 401c308ac), per
done/feature-a-pxx-cannot-link-its-own-objects-so-a-freestanding-multi-object-program-needs-gcc.

## Not a regression in the usual sense

Every frozen compiler back to rv32-a (ea41c11, 2026-10-12) and the v455 pin
fail the same way, and pairing latest with the 09-19 crtl still fails. The
cause is the member check landed on 2026-09-24 (134d68dfe3: a member taken
from a type of unknown layout is refused, not read at offset 0; 690d3859ff: a
struct whose layout pxx dropped is a third state). Before it, these five TUs
compiled and read the wrong bytes; the 09-19 GREEN did not exercise them.

## Causes and fixes

| TU | error | cause | fix |
|---|---|---|---|
| networking/tls_sp_c32.c | no member named 'x' | `sp_digit x[8] __attribute__ ((__aligned__(8)))`: CAttrAlignedValueOf found `aligned`, expected `(` and met the trailing `__`, returned 0; an unparsed alignment marks the body not simple, so the struct went OPAQUE | skip trailing underscores (compiler/clexer.inc) |
| networking/wget.c | 'wget_buf' is unreachable (OPAQUE) | the same: busybox's ALIGNED(16) expands to `__aligned__` | same |
| coreutils/stat.c | no member named 'st_atim' | crtl's struct stat had only second-resolution st_atime | struct timespec st_atim/st_mtim/st_ctim with glibc's `#define st_atime st_atim.tv_sec`; nanoseconds carried from statx through TPalFileStat, TPxxStatBuf and __pxx_statbuf (appended fields) |
| util-linux/ipcs.c | no member named 'key', then 'msg_cbytes' | crtl copies glibc's `__key`, but busybox picks `__key` only when `__GNU_LIBRARY__` is defined, which crtl does not claim | `union { key_t __key; key_t key; }` (and `__seq`/`seq`), same layout; `#define msg_cbytes __msg_cbytes` as glibc |
| libbb/udp_io.c | sizeof INCOMPLETE struct in_pktinfo | crtl had no struct in_pktinfo | struct in_pktinfo and in6_pktinfo, glibc layout |

Also fixed on the way: bare `__attribute__((aligned))` (no argument) took the
same OPAQUE path; it now means gcc's __BIGGEST_ALIGNMENT__ (16; 8 on arm32).

Still refused, deliberately: an alignment given as an expression,
`aligned(sizeof(long))`. The struct goes OPAQUE and every member access is
refused by name, so it fails loudly rather than miscompiling.

## Tests

- test/c_reserved_aligned_spelling_keeps_the_struct_layout.c (+ .expected =
  gcc's output): sp_point as busybox writes it, `__aligned__(16)`, bare
  `aligned`, bare `__aligned__`, spaced `__aligned__ ( 8 )`. latest refuses it
  with 8 errors.
- test/c_crtl_busybox_struct_members.c: utimensat a file to fixed
  nanoseconds and read st_atim/st_mtim back; ipc_perm key/seq through both
  names; msg_cbytes; in_pktinfo layout. Output equals gcc + glibc's.
- The behavioural bar: tools/busybox_diff.sh --pxx-link at the 394 scope,
  result recorded below.

## Result (2026-11-10)

`tools/busybox_diff.sh --targets x86_64 --pxx-link --applets <394 list>`,
compiler b469ff66d89d (this fix, on top of 5f11a77638): 521 objects linked by
`pascal26 --link` (194,165,000 bytes), freestanding (no PT_INTERP, entry ==
_start, no libc), byte-identical to the gcc oracle over 938 cases.
busybox-diff: GREEN.
