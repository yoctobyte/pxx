# Handover: Next Compiler Work

**Snapshot:** 2026-05-31

Use this as the resume checklist after the set / `inherited` / `shl` batch.
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

Regression gates:

```text
test/test_sets.pas
test/test_set_shapes.pas
test/test_inherited.pas
test/test_shl.pas
```

## Confirmed Boundary

Set-valued function results compile but are not supported: a minimal
`function MakeSet: TByteSet` returning `[1, 9]` crashes when the caller assigns
the result. Do not add a set-only scratch-buffer workaround. Implement a
deliberate aggregate-return ABI that can serve records and future aggregate
types consistently.

## Recommended Order

1. **Aggregate-return ABI.** Decide hidden-result parameter semantics for
   records and sets, then cover set-valued and record-valued function results.
2. **Interfaces.** Start the lightweight CORBA-style no-refcount model from
   [`todo.md`](todo.md) section 3. Class/VMT, RTTI registry, and explicit
   `inherited` prerequisites are in place.
3. **Qualified unit symbols.** Add `UnitName.Symbol` resolution before unit
   namespaces grow further.
4. **Full metaclass syntax.** Generalize the narrow class-reference behavior
   into `class of` typing.
5. **Scaled pointer arithmetic.** Make `p + n` stride by the pointed-at type;
   pointer indexing already has the necessary size logic.
6. **Access-control enforcement.** Visibility sections and published RTTI
   exist; private/protected checks remain intentionally unenforced.
7. **Directive breadth.** Add conditional expressions, switch state,
   warning/error directives, and conditional-include semantics deliberately.

## Deferred Arcs

- **Float conversions and float `Str`/`Val`:** handle with the math-library
  design rather than as isolated intrinsics.
- **Dynamic-array depth:** improve after the allocator arc. Scalar arrays work;
  record/string elements, params/results, ownership, copy-on-grow, and reclaim
  remain incomplete.
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
