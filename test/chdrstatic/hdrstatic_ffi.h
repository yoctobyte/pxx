/* THE POSITIVE CONTROL FOR THE TWO SONAME ASSERTIONS NEXT DOOR, and it exists
 * because those assertions had no way to fail on a compiler you can build
 * today.
 *
 * hdrstatic.h and hdrstatic_stdio.h each assert that the binary has NO
 * DT_NEEDED on an invented lib<stem>.so. On a fixed compiler those binaries
 * have no dynamic section AT ALL, so the grep matches nothing -- which is the
 * right answer and is also indistinguishable from a grep that could never
 * match anything. Validating them in the other direction used to need a
 * PRE-FIX compiler, and the pin now postdates the fix, so that control had
 * quietly become uncheckable.
 *
 * This file supplies the missing direction WITHOUT one. A bare declaration is
 * the FFI surface and must KEEP its old treatment -- it is supposed to become
 * an external import, so calling it legitimately produces exactly the artefact
 * the bug produced: a DT_NEEDED on lib<stem>.so. Correct behaviour here, a
 * defect two files over, identical observable.
 *
 * So the row next door asserts the pattern is ABSENT and this row asserts the
 * same pattern is PRESENT, both on the same compiler, both from headers
 * reached by `uses`. If this one ever stops firing, the other two are proving
 * nothing and should not be believed.
 *
 * THE BINARY IS NEVER RUN. It cannot load -- libhdrstatic_ffi.so does not
 * exist and is not meant to. Only readelf reads it.
 *
 * SINCE e53eff428 (2026-09-10) NO BINARY IS PRODUCED HERE AT ALL, and this file
 * now serves the other half of the same control. That commit made the compiler
 * REFUSE a soname it derived from a header's file name when the host cannot
 * resolve it -- which is exactly what this file asks for, so the refusal is
 * correct and it took this control's original job with it.
 *
 * What this file proves now is BETTER AIMED than what it proved before: the
 * compile is refused with a diagnostic that NAMES libhdrstatic_ffi.so, so the
 * machinery which would invent libhdrstatic.so if the static-body bug regressed
 * is demonstrably running. The old row inferred that from an ELF; this one reads
 * it off the compiler.
 *
 * The half this can no longer answer -- "can `readelf -d | grep` match the
 * pattern the two assertions look for AT ALL" -- moved to
 * test_header_static_body_ffi_control_explicit.pas, which reaches the same
 * soname through an EXPLICIT `external` clause. e53eff428 deliberately does not
 * touch those: a soname the user wrote is intent. */
#include <stdio.h>

int hs_ffi_declared_only(int v);
