---
slug: feature-a-pxx-link-has-no-elf-tls
track: A
prio: 40
type: feature
status: backlog
created: 2026-11-21
found-by: an all-pxx rumpnic (Rainyday 0050 item 2), tried in scratch
tags: [link, elf, tls, threads, rump, rainyday]
owner: "claude-pxx"
blocked-by: []
summary: "DECIDED 2026-11-21 by the owner: option 1, gcc-compatible ELF TLS in pxx --link (\"stay gcc compatible, it's a solved problem, just fix the linker\"). An x86-64 object under --system-libs gives a C `__thread` real ELF TLS (.tdata.<name>, GOTTPOFF/TPOFF32), for a libc's loader to set fs. pxx's own --link has no PT_TLS and resolves neither relocation, and pxx's runtime keeps thread-locals in its own block, not in fs. So an object with ELF TLS links only with gcc. That is the last wall for an all-pxx rumpnic: rump's curlwp is `__thread` (one variable, four GOTTPOFF uses), and without ELF TLS it degrades to a shared copy that panicked at boot. Deciding how pxx --link should carry ELF TLS is a runtime design question, hence decide."
---

# pxx --link has no ELF TLS

## Where it stands

- `--emit-obj --system-libs` on x86-64 writes a `__thread` variable as its own
  `.tdata.<name>` (SHF_TLS) and reaches it with R_X86_64_GOTTPOFF or TPOFF32
  (cparser.inc, "AN x86-64 OBJECT GETS REAL ELF TLS"). A gcc link with a libc
  works: the loader builds the TLS block and sets fs.
- Without `--system-libs` a `__thread` keeps the degraded SHARED copy, because
  there is no fs to rely on.
- `pxx --link` refuses `.tdata.*`, has no PT_TLS, and resolves neither
  relocation. pxx's own threads (crtl's pthread over the thread PAL) set up
  pxx's thread block, not an ELF TLS block in fs.

## Why it matters now

An all-pxx rumpnic (Rainyday asked; today rumpnic and librumpuser are gcc)
compiles completely: 471 rump objects, librumpuser's 12, and rumpnic.c,
vfiodev.c and confine.c. After
feature-a-pxx-link-gives-link-sets-their-bounds-and-places-common-symbols it
links up to `.tdata.curlwp_storage` in librump's lwproc.o: one variable, four
GOTTPOFF uses. rump's curlwp must be per thread. A shared copy made a second
thread's `KASSERT(curlwp == NULL)` panic at boot.

## The question

What does a pxx-linked executable do with ELF TLS? The options as seen from
here (not measured):

1. **pxx --link builds ELF TLS itself.** A PT_TLS segment from the `.tdata`
   and `.tbss` inputs, GOTTPOFF slots and TPOFF32 values (variant II), and a
   thread block with fs set up by the entry stub for the main thread and by
   pxx's thread creation for each new one. This touches the runtime's thread
   start, not just the linker.
2. **Map ELF TLS onto pxx's own thread block.** Relocate `.tdata` into pxx's
   per-thread area and rewrite the access. That is a different access sequence
   from the one the object holds, so it is really a codegen change.
3. **Leave it.** An object with ELF TLS links with gcc and a libc, and rumpnic
   stays gcc-linked (its objects can still be pxx's, as now).

It is the owner's call because (1) and (2) each fix what pxx's thread model
promises to C code.

## Decision (owner, 2026-11-21)

> let's stay gcc compatible, it's a solved problem, just fix the linker.

Option 1. `pxx --link` lays out `.tdata`/`.tbss` as a PT_TLS segment, resolves
the x86-64 TLS relocations the way ld does for an executable (variant II, fs
points at the thread control block), and the main thread and every pxx thread
get a block with fs set. On x86-64 pxx's own thread block is in gs (ARCH_SET_GS,
thread_emit.inc), so fs is free and the two coexist. aarch64 and riscv have one
thread register, which is a later question, not this one.

## Plan (claude-pxx, 2026-11-21), from reading the code

What pxx emits is narrow, and each piece has an ld equivalent:

- `static __thread` (local-exec): `mov rax, fs:[0] ; lea rax, [rax + x@tpoff]`,
  with R_X86_64_TPOFF32 on the lea. The linker writes tpoff(x).
- anything else (initial-exec): `mov rax, [rip + x@gottpoff] ; add rax, fs:[0]`,
  with R_X86_64_GOTTPOFF on the mov. An executable needs no GOT for this: ld
  relaxes the `48 8B 05` load to `48 C7 C0 imm32` (mov rax, imm32) holding
  tpoff(x). pxx --link already relaxes GOTPCRELX loads the same way.
- Variant II, as on every x86-64 ELF: the thread pointer is the END of the
  block, rounded to the segment's alignment, and `fs:[0]` holds the pointer
  itself. tpoff(x) = addr(x) - (tls_start + align_up(memsz, align)).

Linker (elfreader.inc):
1. `.tdata*` / `.tbss*` (SHF_TLS) are laid out together, tdata first, as the TLS
   template; a PT_TLS program header describes it.
2. TPOFF32 and GOTTPOFF resolve as above. Anything else TLS-shaped (TLSGD,
   TLSLD, DTPOFF) is refused by name: pxx does not emit it.
3. The entry stub the linker writes (stage 5) gives the MAIN thread its block
   when the image has PT_TLS: a .bss area of align_up(memsz) + 16, the image
   copied in, the self-pointer stored, `arch_prctl(ARCH_SET_FS)`.
4. A linker-defined descriptor `__pxx_elftls` {image, filesz, memsz, align}
   for the thread start to read; defined only when something references it.

Threads (thread_emit.inc): the child stub, after installing pxx's gs block,
reads `__pxx_elftls` through a WEAK reference (0 when nothing linked a TLS
segment, and in a gcc link where libc owns fs). When it is non-zero it carves
the block from the top of the child's own stack, copies the image and sets fs.
No allocation, and the block lives exactly as long as the thread. pxx's gs
block is untouched: gs is pxx's and fs is ELF's on x86-64.

Test: two objects, an extern and a static `__thread` with initialisers, read
and written from the main thread and two pthreads, under --threadsafe
--system-libs --emit-obj, linked by `pxx --link`. Expected output is the gcc+ld
link of the same objects. Then the real one: rumpnic linked all-pxx in
scratch, booted in QEMU.
