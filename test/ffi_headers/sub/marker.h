/* Fixture for feature-n-a-c-header-import-cannot-name-a-header-in-a-subdirectory.
   Reached as `import "sub/marker.h"` with `-Itest/ffi_headers/` -- a header in a
   SUBDIRECTORY of an include root, which is the shape no spelling could reach
   before: a bare name is stripped to its basename before any probe runs, and the
   only working form was an absolute path that bakes a distribution layout into
   the source.

   The marker is an integer #define rather than a function so the test needs no
   library at all: the point under test is header RESOLUTION, and pulling a real
   .so in would make a resolution failure and a link failure look alike. */
#define FFI_MARKER 4242
