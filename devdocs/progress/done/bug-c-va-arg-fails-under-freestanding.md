---
track: A
tags: [C]
prio: 30
type: bug
blocked-by: []
summary: "Under `--emit-obj --freestanding` a variadic C function failed: \"__pxx_va_start_impl is a pxx-internal runtime symbol and cannot be imported dynamically\" (Gibux kprintf.c). pxx lowers va_start/va_arg to calls to helpers in crtl's stdarg.c, which arrived through the crtl auto-pull that --freestanding switches off. stdarg is now exempt from that refusal: it is compiler support, and the helpers have no state. They are emitted WEAK, so every object may carry them."
status: done
owner: unassigned
---

# va_arg fails under --freestanding

`--freestanding` stopped crtl headers from pulling in their implementations.
A kernel brings its own memcpy, and crtl implementations carry tables that are
initialised at run time. That also cut off stdarg.c, which holds
`__pxx_va_start_impl` and the `__pxx_va_arg_*` helpers. pxx's va_start and
va_arg lower to calls to those helpers.

In C, stdarg.h is a freestanding header, and gcc's va_arg is a builtin that
needs no library. CPAutoPullCrtlImpl now lets stdarg through under
--freestanding. It is the only freestanding header with an impl file.

The helpers are WEAK in each object, so about ten kernel objects that each
format text link without a duplicate-symbol clash.

## Test

The c_freestanding_object_has_no_runtime_hooks.c row now:

- adds a variadic `fs_vsum`;
- requires `__pxx_va_arg_gp` to be defined in the object
  (tools/check_freestanding_object.sh);
- links the object with gcc against
  test/c_freestanding_object_has_no_runtime_hooks_main.c and runs it. The
  output is `321 36`; 8 arguments, so the last ones come off the stack.

The d9a0d9a599 compiler refuses the file, naming `__pxx_va_start_impl`.
