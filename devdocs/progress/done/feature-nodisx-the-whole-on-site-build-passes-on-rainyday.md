---
title: "Nodisx: the whole on-site build runs ON Rainyday, byte-identical to the host's"
status: done
owner: claude-dupwt
prio: 70
area: nodisx
---

This was item 6 of umbrella-nodisx-compiles-the-whole-system-on-site-with-pxx,
its acceptance check. tools/nodisx/test-onsite-rainyday.sh,
tools/nodisx/mkiso-tree.sh and tools/nodisx/onsite-all.sh (fa8b5155b5) boot
Rainyday with the ISO tree and pxx-built toybox and mksh only, build every
recipe in the guest, and compare the result file by file with the host's
build.

Runs:
- 2026-11-26: 10 of 14 built. The failures were headers that only the host
  had (pxx2, 1de77b9be1) and an absolute #include in rumpnic (0b92506fc9).
- 2026-11-27: two more e2fsprogs headers and two causes of guest-vs-host
  differences (rumpnic's __FILE__ strings, and the host's ld.so.cache
  sonames in --system-libs objects; 81ca69b3d3, 596166f53d).
- 2026-11-27, final, on 398a2b6cf1: 16 built, 0 failed, 1079 s; 43 files,
  0 differ. PASS.

Console noise, harmless and not a pxx issue: Rainyday logs "unsupported
syscall 444" (landlock_create_ruleset) for every xz/xzcat run; xz carries
on without its sandbox.
