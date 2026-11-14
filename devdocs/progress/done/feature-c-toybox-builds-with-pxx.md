---
slug: feature-c-toybox-builds-with-pxx
track: C
prio: 60
type: feature
status: done
created: 2026-11-14
found-by: claude-opus (toybox port)
tags: [c-frontend, toybox]
blocked-by: []
summary: "PARTIAL. toybox 0.8.15 defconfig (0BSD; https://landley.net/toybox/downloads/toybox-0.8.15.tar.gz, sha256 44e2bab43dfe2c171743297631ce558c6d9ed38b87a66fd751cef617574b375e): all 205 units compile with pxx --emit-obj on x86-64 and i386; x86-64 links with --link and runs. i386 compiles but does not link (no i386 --link). Test-suite parity and the 13 MB size are open (backlog)."
---

# toybox builds with pxx (x86-64)

Owner request relayed by pixx-f2: toybox as the base userland for the pixx live
ISO, then mksh or dash (0.8.15 defconfig has no sh, awk or tr).

Method: replay the gcc `make defconfig; make V=1` compile lines through
`pascal26 --emit-obj --function-sections`, then `pascal26 --link`. The fixes it
needed are the sibling done tickets dated 2026-11-14 tagged `toybox`.

Open: backlog tickets feature-c-i386-link-for-c-objects,
bug-c-toybox-test-suite-failures, bug-c-toybox-netcat-listen-hangs,
feature-c-toybox-binary-is-13-mb.
