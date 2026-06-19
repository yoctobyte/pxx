# Can't pass a function-result temporary to a const/by-ref record param

- **Type:** bug (compiler)
- **Status:** backlog
- **Owner:** — (track A)
- **Opened:** 2026-06-19 (track B, building lib/rtl/bignum)

## Symptom

Passing a function-result temporary (rather than a named variable) to a `const`
record parameter is rejected:

```pascal
p := BigAdd(BigFromInt(999999999), BigFromInt(2));
              ^ pascal26: error: by-reference argument must be a variable ()
```

Works when the arguments are variables:

```pascal
x := BigFromInt(999999999); y := BigFromInt(2);
p := BigAdd(x, y);              { ok }
```

`const` record params are passed by reference, and the compiler will only bind a
real lvalue, not a temporary. (FPC accepts a temporary for a `const` param.)

## Impact

Forces intermediate variables for every nested call over record-typed values —
ergonomic wart for any value-style API (bignum, JSON nodes, vectors, etc.).
Nesting `f(g(x), h(y))` is the natural style and currently illegal for records.

## Direction

For `const` (and by-value) record params, materialize a function-result
temporary into a hidden local and pass its address — i.e. allow temporaries to
bind to `const`-by-ref params, as FPC does. (Plain `var` params should still
require a true variable.)

## Log
- 2026-06-19 — opened by track B from the bignum lib; worked around with named
  locals in the test, but the lib's public API still forces that on callers.
