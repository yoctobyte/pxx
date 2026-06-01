# Handover: Next Compiler Work

**Snapshot:** 2026-06-01

Use this as the resume checklist after the set / `inherited` / `shl`,
aggregate-return, and language-gap batches.
Source and `make test` remain authoritative; [`todo.md`](todo.md) keeps the
full inventory.

## Delivered In The Latest Batch

- Sets now use dedicated 32-byte IR operations for copy assignment, union,
  intersection, difference, equality, and subset/superset comparisons.
- Set coverage includes literals, `in`, nested algebra, locals, globals,
  record fields, `var` parameters, and by-value reads.
- Explicit `inherited` calls work for constructors, named methods, bare
  `inherited`, and inherited function results. Calls lower statically to the
  ancestor body so virtual dispatch does not recurse into the override.
- Pascal `shl` is tokenized and lowered beside `shr`.
- Record-valued and set-valued functions share a hidden-destination return
  ABI, including nested calls, explicit `Exit(set)`, and recursive returns.
- Qualified `UnitName.Symbol` resolution now selects symbols and overloaded
  routines from the named imported unit.
- Named metaclass aliases use `TClassRef = class of TBase`; class values retain
  their runtime RTTI identity for `CreateInstance` and `ClassNameOf`.
- Typed-pointer `p + n`, `p - n`, and `n + p` arithmetic scales by the
  pointed-at type, including record pointers, pointer fields, and casts.
- Pascal conditional expressions support `defined(NAME)`, bare symbols,
  `not`, `and`, `or`, parentheses, `0`, and `1`. `{$elseif}`,
  `{$warning}`, `{$message}`, `{$error}`, and active-branch include expansion
  are covered.

Regression gates:

```text
test/test_sets.pas
test/test_set_shapes.pas
test/test_inherited.pas
test/test_shl.pas
test/test_aggregate_results.pas
test/test_qualified_units.pas
test/test_class_of.pas
test/test_ptr_arithmetic.pas
test/test_pascal_directives.pas
test/test_pascal_conditional_include.pas
```

## Delivered Aggregate ABI

Record-valued and set-valued function results now use a deliberate hidden
destination-pointer ABI. The caller allocates result storage in its own frame
or global scope; the callee saves the pointer locally so nested calls cannot
clobber it, copies out at return, and returns the destination address. Coverage
includes nested set calls, explicit `Exit(set)`, record results, and recursive
record returns in `test/test_aggregate_results.pas`.

## Recommended Order

The previous no-excuse language list is complete. Pick the next arc
deliberately rather than pulling deferred work forward accidentally:

1. **C header imports.** Grow preprocessing, typedef, struct, callback, and ABI
   support from concrete GTK/glib header fixtures.
2. **Allocator foundations.** Improve allocation policy before adding managed
   values that depend on predictable reclaim behavior.
3. **Managed `AnsiString`.** Replace the current inline fixed-capacity string
   representation with reference-counted storage before deepening dynamic
   arrays. Decide the threading contract first: shared strings require atomic
   refcount updates or another synchronization policy, while a single-threaded
   contract avoids that overhead but must be explicit. Atomic refcounts protect
   lifetime only; they do not make concurrent mutation or copy-on-write checks
   safe.
4. **Dynamic arrays.** Reuse the managed-value ownership rules after allocator
   and `AnsiString` work settle.
5. **Directive breadth.** Add named checking/optimization switch state only
   when code generation or diagnostics consume it.

## Deferred Arcs

- **Interfaces:** postponed intentionally. No current target source requires
  them, while even a no-refcount model adds substantial dispatch, ABI, and
  lifetime-design surface. Revisit when a concrete compatibility target needs
  them.
- **Access-control enforcement:** visibility parsing stays because
  `published` drives RTTI. Rejecting private/protected access enables no new
  programs, so enforcement is intentionally deferred until compatibility
  pressure justifies it.
- **Float conversions and float `Str`/`Val`:** handle with the math-library
  design rather than as isolated intrinsics.
- **Managed `AnsiString`:** design before dynamic-array depth. Current strings
  are inline fixed-capacity values, not reference-counted heap strings. Decide
  whether cross-thread sharing is supported before fixing the representation:
  atomic increments/decrements add overhead, while mutex-based refcounting is
  likely too expensive for ordinary assignment.
- **Dynamic-array depth:** improve after allocator and managed-`AnsiString`
  work. Scalar arrays work; record/string elements, params/results, ownership,
  copy-on-grow, and reclaim remain incomplete.
- **Allocator:** replace the current simple first-fit free list with splitting,
  coalescing, bins, and large-block `mmap`/`munmap`.
- **Compiler internal split:** move include-heavy internals toward real Pascal
  units late, after behavioral work settles.

## Known Red

- Compiling `test/test_basic_lexer.bas` hangs. BASIC stays experimental and
  outside `make test`.

## Verification Baseline

The latest batch passed:

```sh
make test
git diff --check
```

`make test` includes FPC recovery equivalence, recursive self-hosting, the
expanded regressions above, and final byte-identical fixedpoint comparison.
