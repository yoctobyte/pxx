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
 * exist and is not meant to. Only readelf reads it. */
#include <stdio.h>

int hs_ffi_declared_only(int v);
