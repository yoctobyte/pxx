# Exceptions

PXX implements setjmp-style exceptions with a per-stack handler chain:

- `try … except … end` and `try … finally … end`;
- `raise E` and bare `raise` (re-raise) inside a handler;
- typed handlers `on E: SomeClass do …`;
- exception-unwind release of managed locals (strings, dynamic arrays, managed
  records) on the unwound frames.

```pascal
try
  DoThing;
except
  on E: EMyError do HandleSpecific(E);
  on E: TObject  do HandleRest(E);
end;
```

## Limits

- There is **no built-in `Exception` class hierarchy** with message
  constructors and inherited-handler matching the way FPC's RTL provides — you
  supply the classes you raise/catch.
- The unhandled-exception reporter prints a default message and exits non-zero.
  `--no-unhandled-handler` makes an unhandled exception exit status 1 silently.

## Interaction with generators

The exception frame lives on the stack. A `yield` inside `try`/`except`/
`finally` is therefore **rejected** in both generator backends today (see
[Generators](generators.md)); for the stackless backend it is a permanent
restriction, for the stackful one it is liftable later.
