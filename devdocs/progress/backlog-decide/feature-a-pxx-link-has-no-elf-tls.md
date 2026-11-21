---
slug: feature-a-pxx-link-has-no-elf-tls
track: A
prio: 40
type: feature
status: backlog
created: 2026-11-21
found-by: an all-pxx rumpnic (Rainyday 0050 item 2), tried in scratch
tags: [link, elf, tls, threads, rump, rainyday, decide]
blocked-by: []
summary: "An x86-64 object under --system-libs gives a C `__thread` real ELF TLS (.tdata.<name>, GOTTPOFF/TPOFF32), for a libc's loader to set fs. pxx's own --link has no PT_TLS and resolves neither relocation, and pxx's runtime keeps thread-locals in its own block, not in fs. So an object with ELF TLS links only with gcc. That is the last wall for an all-pxx rumpnic: rump's curlwp is `__thread` (one variable, four GOTTPOFF uses), and without ELF TLS it degrades to a shared copy that panicked at boot. Deciding how pxx --link should carry ELF TLS is a runtime design question, hence decide."
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
