---
slug: feature-a-pxx-link-has-no-elf-tls
track: A
prio: 40
type: feature
status: done
created: 2026-11-21
found-by: an all-pxx rumpnic (Rainyday 0050 item 2), tried in scratch
tags: [link, elf, tls, threads, rump, rainyday]
owner: "claude-pxx"
blocked-by: []
summary: "DONE 2026-11-21: pxx --link lays .tdata.* out as a PT_TLS template, resolves R_X86_64_TPOFF32 and relaxes R_X86_64_GOTTPOFF to an immediate as ld does, gives the main thread its fs block in the entry stub, and crtl's pthread_create gives every new thread one from the __pxx_tls_* symbols the link defines; output matches gcc+ld (test/c_link_elf_tls.c). DECIDED 2026-11-21 by the owner: option 1, gcc-compatible ELF TLS in pxx --link (\"stay gcc compatible, it's a solved problem, just fix the linker\"). An x86-64 object under --system-libs gives a C `__thread` real ELF TLS (.tdata.<name>, GOTTPOFF/TPOFF32), for a libc's loader to set fs. pxx's own --link has no PT_TLS and resolves neither relocation, and pxx's runtime keeps thread-locals in its own block, not in fs. So an object with ELF TLS links only with gcc. That is the last wall for an all-pxx rumpnic: rump's curlwp is `__thread` (one variable, four GOTTPOFF uses), and without ELF TLS it degrades to a shared copy that panicked at boot. Deciding how pxx --link should carry ELF TLS is a runtime design question, hence decide."
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

## Done (claude-pxx, 2026-11-21)

As planned above, with one change of place: the per-thread block is made in
crtl's `pthread_create` (lib/crtl/src/pthread.c), not in thread_emit.inc's
clone stub. Every thread a C program starts comes through it (rumpnic's come
from librumpuser's pthread_create), it is C, and C already has weak data
references; the clone stub has no symbol to refer to one from.

- compiler/elfreader.inc: a new section kind, ELFLNK_K_TDATA, between .data
  and .bss. `.tdata.*` must carry SHF_TLS and anything with SHF_TLS must be
  `.tdata.*`; a NOBITS `.tbss` is still refused (pxx writes none). PT_TLS
  header, a `.tdata` section header, STT_TLS symbols valued as their offset
  in the template (as ld writes them: tx 0, tz 8, ty 0x14 in the test, the
  same as gcc+ld's).
- TPOFF32 = S + A - tp; GOTTPOFF's `mov r64, [rip+disp]` becomes
  `mov r64, imm32` (ld's IE->LE relaxation), anything else under it refused.
  tp = template start + its size rounded up to its alignment (variant II).
- The entry stub grows a 70-byte prologue when there is a template: a block
  carved from the initial stack, zeroed, the image copied in, the
  self-pointer stored, arch_prctl(ARCH_SET_FS).
- `__pxx_tls_image/_filesz/_memsz/_align`, linker-defined only when there is
  a template. crtl refers to them weakly; elfwriter.inc's ObjDataIsImport lets
  them stay undefined in a runtime copy, as for __init_array_start, because a
  private slot is a nonzero "template" of garbage size (measured: a memcpy
  far past the image).
- pthread_create allocates the block (failure is EAGAIN), the new thread
  fills and installs it before anything else, and frees it when it ends.

Test: test/c_link_elf_tls.c, rows c_ltls (pxx --link), c_ltls_pt (one PT_TLS)
and c_ltls_g (gcc+glibc over the same objects), expected output from gcc.
Before the crtl half, the two threads read and wrote the main thread's block.

### The all-pxx rumpnic, after this

It links past TLS, and past two more walls that are not TLS:

1. `pxx --link` counted undefined references from sections its GC drops. ld
   --gc-sections does not: rump's members name ~50 kernel functions only from
   header `static inline` copies nothing calls. Fixed beside this
   (test/c_link_gc_dead_undefined_ref.c).
2. virtif_user.c is a RUMPCOMP_USER file (the host side of virtif, like
   librumpuser) and needs the host libc: under --system-libs it asks for
   glibc's `pthread_create`, `__errno_location` and `__assert_fail`. Compiled
   hosted like librumpuser, it links. That is how the all-pxx build must
   classify it, a build-harness fact, not a pxx gap.

What was left was `backtrace()`, which rumpnic's crash handler calls and crtl
did not have (glibc and NetBSD's libexecinfo do): crtl now has <execinfo.h>.

With those, the all-pxx rumpnic LINKS (scratch, 2026-11-21): 473 objects, an
11 MB static image with an 8-byte PT_TLS, curlwp's. One more emulation
detail of the scratch link: librumpuser is an ordinary archive in the gcc
link, so ld never pulls rumpuser_mem.o (rumpnic.o defines all four of its
functions); pxx --link reads no archives, so the scratch link leaves that
member out by hand. Not run here: rumpnic takes the first network card under
/dev/vfio, so its boot belongs in Rainyday under QEMU, Rainyday's harness.
