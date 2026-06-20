# C runtime substrate

`lib/crtl` is the small C compatibility layer used by source-backed C library
candidates. It is intentionally not a hosted libc clone.

- `include/` contains project-owned headers that should be preferred with
  `-Ilib/crtl/include`.
- `src/` is reserved for the matching implementations once real candidates need
  them and the C body frontend can compile them.

Add declarations and macros only when a candidate library or regression test
needs them.
