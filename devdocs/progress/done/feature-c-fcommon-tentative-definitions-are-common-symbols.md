---
track: C
tags: [c, object, link, symbols, rump, netbsd]
prio: 10
type: feature
blocked-by: []
summary: "-fcommon was ignored, so every C tentative definition was a strong .bss definition. NetBSD's net_stub.c needs -fcommon: its tentative ifnet_pslist & co. collided with the real ones (multiple definition). Under -fcommon an x86-64 object now writes an uninitialised exported C global as SHN_COMMON, as gcc does."
status: done
owner: claude-dupwt
---

# -fcommon: tentative definitions are COMMON symbols

pxx always uses -fno-common semantics (gcc 10+ default): `int x;` at file
scope is a .bss OBJECT. NetBSD builds `librumpnet`'s `net_stub.c` with
`-fcommon` (Rainyday's rump-nic.md: on that file only). Its tentative
`ifnet_pslist`, `ifnet_list`, `altq_input`, ... are placeholders that the real
definitions in libnet, libnetinet and others replace. Strong definitions
collided: "multiple definition of rumpns_ifnet_pslist" when linking rumpnic.

## Fix

- `-fcommon` / `-fno-common` set `CObjCommon`.
- The C frontend records `SymCHasInit` for any declaration with an
  initialiser, on both the main and the function-pointer declarator paths.
- In the x86-64 object writer, an exported C global that is not initialised,
  not in .data, not in a named section, not thread-local and not weak gets
  `st_shndx = SHN_COMMON`, value = alignment, size = size. Every reference
  already names the global's own symbol, so nothing else changes. Its unused
  .bss slot stays, unnamed.

## Proof

`test/c_fcommon_tentative.c`: three tentative globals (a struct, an int, a
function pointer), one initialised and one static. The gcc main defines the
three with values. `nm` shows the same C/B(D)/b pattern as gcc -fcommon, and
the program prints 42, hosted and freestanding (rows c_fcommon26,
c_fcommon26_sym, c_fcommon26_f). Without -fcommon nothing changes.
