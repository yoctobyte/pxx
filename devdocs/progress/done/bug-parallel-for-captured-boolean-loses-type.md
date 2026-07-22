---
prio: 50  # auto — compile-time error, not silent, but blocks an ordinary pattern
track: A
---

# Captured Boolean loses its type inside a parallel-for body (overload resolution fails)

- **Type:** bug — **Track A** (parallel-for capture lowering; `parser.inc`
  capture-frame path).
- **Status:** done
- **Found by:** Track E, building `examples/mandelbrot/mandelzoom.pas`
  ([[feature-demo-mandelbrot-asm-autozoom]]).

## Repro

```pascal
program Cap2;
uses palparallel;
procedure Sink(i: Integer; flag: Boolean);
begin if flag then ; end;
procedure Run;
var i: Integer; lflag: Boolean;
begin
  lflag := True;
  parallel for i := 0 to 99 do Sink(i, lflag);
  writeln('ok');
end;
begin Run; end.
```
```
    param[0] = 1
    param[1] = 2
pascal26:9: error: no overload of Sink matches these arguments ()
  near:  i  lflag   >>>
```

The diagnostic's own dump gives it away: the callee's parameter 1 is kind **2**
(Boolean) but the argument arrives as kind **1** (Integer). `lflag` is a plain
Boolean local — the supported Phase-A scalar-capture shape — and reading it in
the body (`if lflag then ...`) works; only passing it to a `Boolean` parameter
fails. So the capture rewrite is dropping the declared type and re-materialising
the slot as an Integer.

Presumably every non-Integer scalar (Char, enums, subranges, Byte…) is worth
checking at the same time — Boolean is just the one this hit first.

## Secondary: the error message is unhelpful

`no overload of Sink matches these arguments ()` — the parenthesis is empty
where the argument types should be, and the numeric `param[n] = k` dump above it
is internal type-kind numbering with no legend. For a non-overloaded procedure
the message should say which argument mismatched and in what way. Worth fixing
alongside; it cost more time here than the bug itself.

## Acceptance

- The repro prints `ok`.
- A regression test extending `test/test_parallel_for_capture.pas` to cover a
  captured Boolean (and Char / enum) both read in the body and passed as an
  argument.
- Track A gate: `make test` + self-host byte-identical.

## Links
[[bug-parallel-for-captured-dynarray-var-arg-segfault]] (same session, same
capture path, worse failure mode) · [[feature-demo-mandelbrot-asm-autozoom]] ·
`test/test_parallel_for_capture.pas`.

## Log
- 2026-07-20 — Filed from Track E. Demo works around it by reading the flag from
  a global instead of a captured local.
- 2026-07-22 — resolved, commit 49f4eb55.
