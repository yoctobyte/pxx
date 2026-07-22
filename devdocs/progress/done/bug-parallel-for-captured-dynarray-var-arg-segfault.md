---
prio: 60  # auto — compiles clean, crashes at runtime; silent-failure class
track: A
---

# Passing a captured dynamic array by `var` from a parallel-for body segfaults

- **Type:** bug — **Track A** (parallel-for capture lowering; `parser.inc` /
  `ir_codegen.inc` capture-frame path).
- **Status:** done
- **Found by:** Track E, building `examples/mandelbrot/mandelzoom.pas`
  ([[feature-demo-mandelbrot-asm-autozoom]]).

## Repro (compiles clean, segfaults)

```pascal
program Cap3;
uses palparallel;
type TArr = array of Integer;
procedure Sink(i: Integer; var a: TArr);
begin a[i] := i; end;
procedure Run;
var i: Integer; la: TArr;
begin
  SetLength(la, 100);
  parallel for i := 0 to 99 do Sink(i, la);
  writeln(la[42]);
end;
begin Run; end.
```
```
$ pxx --threadsafe cap3.pas /tmp/cap3
ok: /tmp/cap3  [code=73339B  data=1576B  bss=9572B  procs=160]
$ /tmp/cap3
Segmentation fault (core dumped)
```

`la` is a LOCAL of a NAMED type, which is exactly the supported B-1 aggregate
capture shape (cf. `test/test_parallel_for_capture_aggr.pas`). Capturing it and
*indexing it directly in the body* is covered by that test and works; capturing
it and passing it **by `var` to a callee** compiles and then crashes.

The likely shape: the capture frame holds the array by reference, and the
callee's `var` parameter is handed the frame slot (a reference to the reference)
rather than the array's own data pointer — one indirection too many. Worth
checking whether a by-value (`const` / plain) aggregate parameter has the same
problem.

## Why it matters

It is silent: no diagnostic, a clean `ok:` line, and the crash lands at runtime
in whatever the worker touches first. Splitting a parallel loop body into a
helper procedure is the *recommended* pattern (the helper's scratch is private
per worker) — so this bites exactly the code shape the docs steer people toward.

## Acceptance

- The repro above prints `42`.
- A regression test in the `test_parallel_for_capture_*` family covering a
  captured dynamic array passed to a callee as `var`, as `const`, and by value.
- Track A gate: `make test` + self-host byte-identical.

## Links
[[bug-parallel-for-captured-boolean-loses-type]] (found in the same session, same
capture path) · [[feature-demo-mandelbrot-asm-autozoom]] (the consumer; it works
around this by putting the framebuffer in a global, which workers reach directly)
· `test/test_parallel_for_capture_aggr.pas`.

## Log
- 2026-07-20 — Filed from Track E. Workaround used in the demo: globals are not
  captured at all (they are statically addressable), so a global dynamic array
  written from workers behaves correctly — verified.
- 2026-07-22 — resolved, commit 69ebf4bb.
