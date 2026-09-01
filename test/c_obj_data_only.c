/* A translation unit of PURE DATA. busybox's libbb/ptr_to_globals.c is exactly
   this and nothing else, and --emit-obj refused it: "this object would define
   no linkable symbol". That refusal was correct about the object and wrong
   about the program -- a data-only TU is ordinary C. The refusal is kept for a
   genuinely empty object; it now counts data. */
struct globals;
struct globals *ptr_to_globals;
