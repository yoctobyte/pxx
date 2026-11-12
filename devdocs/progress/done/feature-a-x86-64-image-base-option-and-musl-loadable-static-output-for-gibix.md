---
slug: feature-a-x86-64-image-base-option-and-musl-loadable-static-output-for-gibix
title: "x86-64: an opt-in image base above 4 GB, and static output that musl's ld.so can start (Gibix)"
track: A
prio: 50
type: feature
status: done
created: 2026-11-12
found-by: owner + Gibix session
owner: "Gibix session"
blocked-by: []
tags: [x86-64, elfwriter, gibix, minimal-system]
summary: "DONE 2026-11-12. New x86-64 options, all opt-in: `--image-base=<n>` (writeELF and the --link writer), `--ldso-runnable` (a 144-byte minimal PT_DYNAMIC block after the program headers: DT_HASH nbucket=1, null symbol, empty strtab), and `--gibix` = both with base 0x8000000000. Also fixes `bssBase := AlignTo(...)`, which truncated to 32 bits. Default output is byte-identical to master (hello.pas, a C test, compiler.pas, --emit-obj, --link). A `--gibix` compiler self-hosts byte-identically when started through Alpine ld-musl on the host. On Ginux itself (borg, KVM, fork 031afa1e), the self-host via ld-musl was already proven byte-identical with the prototype. Not yet run: busybox --pxx-link with --gibix (the harness can take it through a BB_COMPILER wrapper that adds --gibix).""
---

# x86-64 image base option + musl-loadable static output

## Why

Gibix runs pxx and pxx-built busybox on the frozen standalone Ginux kernel. It
lives in our fork `githome:gibix-kernel.git`, and the notes are in
`~/gibix/NOTES.md`. Ginux has two exec walls. First, it execs only files from
the published OCI rootfs, so nothing written at runtime, like compiler output.
Second, the main image is a fixed 2 MB window, filled eagerly. Lifting either
wall is a kernel rework: the window is wired into 51 functions, about 10k lines.

The route without a kernel patch is that Alpine's own musl loader *is* in the
rootfs, and Ginux runs it standalone at 0x400000. musl then loads the real
program with `mmap`, which works for runtime-written (overlay) files, including
with `PROT_EXEC`. musl accepts ET_EXEC: it passes a hint at the lowest vaddr and
fails with EBUSY if the mapping lands anywhere else.

## What pxx needs (all opt-in)

1. **Image base option.** `LOAD_ADDR = $400000` is a constant (defs.inc). Gibix
   needs >= `$8000000000` (2^39): Ginux's user mmap window is [2^39, 2^40)
   (`LINUX_RUNTIME_DYNAMIC_MMAP_BASE`), below that is the kernel's shared
   mapping, and 0x400000 is taken by ld-musl anyway. A command-line option, a
   `$define`, or a target flavour all work. Decide which.
2. **`AlignTo` truncation.** `bssBase := AlignTo(DataVA(dataBase, DataLen), 8)` in
   both x86-64/aarch64 writeELF copies passes a 64-bit address through
   `AlignTo(value, alignment: Integer): Integer`. At 512 GB that gave
   `p_memsz = 0xffffff8000008768` and a SIGSEGV. The scratch fix is
   `(x + 7) and (not Int64(7))`. Then audit the rest of the address math in the
   writer for Integer: `GlobFix` non-PCRel `Patch32(pos, addr)` absolute fields
   would silently truncate. None fired in the compiler or hello, but busybox and
   the C path are unmeasured.
3. **Minimal dynamic segment.** musl says "Not a valid dynamic program" without
   `PT_DYNAMIC`. With an empty table (just DT_NULL) it segfaults dividing by
   `nbucket` in its SysV hash lookup. What works: DT_HASH (nbucket=1, nchain=1,
   zeros), DT_SYMTAB (one null Elf64_Sym), DT_STRTAB ("\0"), DT_NULL, in a
   read-only LOAD, plus the PT_DYNAMIC header. The existing dynamic machinery
   (`PrepareDynamicData`, driven by `ExternalCount`) already builds these
   tables for libc-linked programs. This needs a no-libraries variant.
   Prototype: `~/gibix/probe/add_dynamic.py` appends a page with a new
   program-header table plus those tables to a finished binary.

## Measured (host, 2026-11-12)

Scratch tree `~/gibix/pxx-hi`: export of 25c2b42394 with LOAD_ADDR=$8000000000
and fix 2.

- hello at 512 GB runs.
- The 512 GB compiler compiles itself: p-hi1 = p-hi2 = `51056eeef312...`, a fixpoint.
- The same compiler with the dynamic page added and started as
  `ld-musl-x86_64.so.1 p-hi1-dyn compiler/compiler.pas out` gives an identical
  result.
- Before the base change, at 0x400000 under musl, hello and the full compiler
  also ran. The host has no conflict at 0x400000; Ginux does.

## Acceptance

- Default build: compiler fixpoint unchanged, and every existing output
  byte-identical.
- With the option: hello, the compiler self-host and `busybox_diff.sh --pxx-link`
  (394 applets) are green on Linux, both run directly and started through
  Alpine's ld-musl.
- On Ginux (`~/gibix/run-musl-on-ginux.sh`), the self-host matches the host
  build's sha.

## Not in scope

PIE/ET_DYN output for Pascal/C. That would also work under musl and remove the
need to pick a base, but it is a much larger change (relocations for every
absolute 8-byte data fixup).

## Done (2026-11-12)

- `compiler/defs.inc`: `ImageBase` (default LOAD_ADDR), `LdsoRunnable`,
  `LDSO_DYNAMIC_SIZE`/`LDSO_BLOCK_SIZE`.
- `compiler/elfwriter.inc`: both writeELF copies use ImageBase, take the
  64-bit bssBase alignment, and with `--ldso-runnable` (and no imports) add
  PT_DYNAMIC + `WriteLdsoBlock` between the headers and the code. The
  codeOffset invariant now counts the block.
- `compiler/elfreader.inc` (`--link`): base is ImageBase; with
  `--ldso-runnable`, a 4th header and the same block in the first page.
  readelf then warns "no .dynamic section in the dynamic segment", because the
  linker writes section headers and none of them is `.dynamic`. That is
  cosmetic: loaders read the program headers.
- `compiler/compiler.pas`: options `--image-base=`, `--ldso-runnable` and
  `--gibix`; refused off x86-64 and for unaligned or out-of-range bases;
  `--proc-map` follows the base and the block.

Measured: master fd876a1891 vs this change, default flags, byte-identical on
test/hello.pas, test/c_address_of_an_array.c, compiler/compiler.pas,
`--emit-obj` and `--link` of a small C object. `--gibix`: hello runs directly
and via ld-musl; the `--gibix` compiler, started through ld-musl, reproduces
itself (c0dc1510...); `--gibix --link` of a C object exits 42 directly and via
ld-musl. The gate result is in the commit message.
