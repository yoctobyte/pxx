/* Same relative spelling as test/ffi_headers/sub/marker.h and a DIFFERENT value,
   which is the whole assertion: a header sitting beside the source is an
   explicit local choice and must keep beating an include root. The include-path
   fallback runs only after the authoritative path has genuinely missed, so this
   file is what `import "sub/marker.h"` finds from here even with
   `-Itest/ffi_headers/` on the command line. */
#define FFI_MARKER 1111
