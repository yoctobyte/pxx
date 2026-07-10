---
prio: 68  # auto — a whole bug class (silent miscompile → runtime SIGSEGV) that
          # cost a full session to diagnose per occurrence; cheap, contained fix
---

# libc-free link: unresolved external symbol patched to 0 instead of a link error

- **Type:** bug (compiler linker / diagnostics) — **Track A** (`compiler/elfwriter.inc`,
  `compiler/symtab.inc`, C-side marking in `compiler/cparser.inc`).
- **Status:** backlog
- **Found / Opened:** 2026-07-10, sqlite file-VFS wall 4
  ([[task-sqlite-libc-free-runtime-bringup]],
  [[project_sqlite_file_vfs_wall4_null_syscall_slot]]).

## Symptom

A libc-free C program (0 `DT_NEEDED`) that references a libc function the crtl
does NOT provide **links cleanly** and then **SIGSEGVs at runtime with a call to
address 0** the first time that symbol's code path runs. No compile error, no
link error, no warning. `gdb` shows `call 0x0`; the binary has no section
headers so `nm`/`objdump` are empty, making it maximally opaque.

This cost a full session on sqlite's file VFS: `pread` (and behind it
`geteuid`/`fchown`) were missing from the crtl, so `aSyscall[]` slots resolved to
0 and os_unix.c null-called inside `seekAndRead`/`fillInUnixFile`. The fix there
was to add the syscalls (commit d65d95d8) — but the compiler should have said
`undefined symbol: pread` at link time instead of shipping a null-call.

## Root cause

`cparser.inc` marks any undefined C function `ProcExternal[i] := True` with
`ProcLibrary := 'libc.so.6'` (or `libm.so.6` for the math names) — see ~7109 /
7136, and `extLib` at ~6925. `RegisterExternal` (`symtab.inc:5271`) gives it an
8-byte GOT slot **zero-initialised**. `EmitExternalProcAddr` / the external call
path load/call through that slot. The slot is filled at runtime only by the
dynamic linker via `R_X86_64_GLOB_DAT` + the `DT_NEEDED` for its library.

In a **libc-free** link (`forceSystemExternal` false — no `--system-libs`, no
explicit `external 'lib'`), the auto-pull ([[project_c_crtl_autopull_link_model]])
is expected to satisfy every external from crtl sources. Anything it does NOT
satisfy stays external against `libc.so.6` but **no `DT_NEEDED` / GLOB_DAT is
emitted** (the whole point is 0 NEEDED), so the GOT slot is never written →
stays 0. `cparser.inc:6464` even documents the hazard verbatim: *"the prototype
is marked external against libc, and in a libc-free link the call silently does
nothing."*

Direct **calls** to an unresolved *internal* proc already hard-error
(`ApplyCallFixups`: `Error('unresolved forward: ...')`, `symtab.inc:5579`). The
gap is only the **external-symbol** path (call-through-GOT and address-of): it
has no equivalent finalize check.

## Fix (proposed)

At ELF finalize (`writeELF*` in `elfwriter.inc`, after `CPullCrtlForPrototypes`
and after `DynamicNeededCount` is computed), fail on any external that will NOT
be resolved:

- For each `i` in `0..ExternalCount-1`: if the build is libc-free for that
  symbol's soname — i.e. `ProcLibrary[ExternalProc[i]]` is not among the emitted
  `neededLib*` set (equivalently `forceSystemExternal` was false for it and
  `--system-libs` is off) — emit `Error('undefined symbol: ' +
  Procs[ExternalProc[i]].Name)`.
- List ALL unresolved names, not just the first, so one build surfaces the whole
  missing set (sqlite needed 7 — one-at-a-time would be 7 painful sessions).

Guards / do-not-break:
- `--system-libs` and explicit `external 'lib' name 'sym'` must still link
  dynamically (real `DT_NEEDED`) — those are resolved, not errors.
- The legitimate dynamic path (GTK/GLib, `dlopen`) is unaffected: those externals
  DO get a `DT_NEEDED`, so they're in the emitted set.
- Re-check the `aSyscall[]` "address taken but never called with :memory:"
  tolerance mentioned in `EmitExternalProcAddr`: taking the address of a missing
  symbol is exactly what produced the latent null that later crashed, so the
  correct behaviour is still to ERROR (ld does). The `:memory:` build only stayed
  up because it never *called* those slots; that is luck, not correctness.

## Acceptance

- A libc-free C program that references an undefined function (e.g. `int
  main(void){ extern int nope(void); return nope(); }` with no crtl/def) fails to
  compile with `undefined symbol: nope`, exit non-zero, no binary emitted.
- All existing libc-free tests (c-testsuite, crtl guards b234/b235/b238, sqlite
  `:memory:` + file probes) still build — proving auto-pull + the syscall set are
  complete and nothing legitimate now false-errors.
- `--system-libs` builds and the GTK/dynamic demos still link and run.
- Self-host byte-identical + cross unaffected.

## Notes

- Regression test idea: a tiny `.c` expected to FAIL compilation (new
  negative-test lane, or a shell wrapper asserting non-zero exit + the message).
- Diagnostic aside: the emitted ET_EXEC has no section headers, so post-mortem
  `nm`/`objdump` yield nothing. Optionally emit a minimal `.symtab` (or a
  `--emit-symbols` flag) so a runtime `call 0` can at least be traced. Secondary
  to the link-time error, which prevents the crash entirely.
