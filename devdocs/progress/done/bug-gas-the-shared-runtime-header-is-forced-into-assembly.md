---
slug: bug-gas-the-shared-runtime-header-is-forced-into-assembly
track: gas
prio: 70
type: bug
status: done
owner: pxx2
created: 2026-11-28
closed: 2026-11-28
found-by: pxx2 (libffi replay with --shared-runtime: both .S units failed)
tags: [gasfront, cpreproc, shared-runtime]
summary: "`--shared-runtime` adds a forced `#include \"pxx/shared_runtime.h\"`. It was forced into .S sources too, where crtl's include directory isn't searched ('C include file not found'), and the header is C declarations anyway. It is skipped now when CPAsmSource is set. Test: check_gas_frontend.sh step 7 assembles test/gas_frontend_libffi_shapes.S with --shared-runtime and wants the same .text."
---

# --shared-runtime forced its C header into assembly

`compdb.py replay` with `PXXFLAGS="--shared-runtime --threadsafe"` failed on
every .S unit with "C include file not found: pxx/shared_runtime.h". The
flag registers the header with AddCmdInclude, and cpreproc prepends every
command-line include to the source, assembly included. Assembly has no
runtime to share. The include loop now leaves out that one header when
CPAsmSource is set. A user's own `-include` still applies to .S, as with gcc.
