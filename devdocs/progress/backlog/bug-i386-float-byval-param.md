# i386 backend: by-value float (Double) parameter unsupported

- **Type:** bug (i386 backend — Track A)
- **Status:** backlog
- **Found / Opened:** 2026-06-27 (Track A+C, while running `make
  test-float-determinism` as the gate for the C double-value-model fixes)

## Symptom

`./compiler/pascal26 --target=i386 examples/mandelbrot/mandelbrot.pas …` fails:

```
pascal26:619: error: target i386: only ordinal/pointer parameters supported yet ()
```

So `make test-float-determinism` is RED on the i386 leg (x86-64, aarch64, arm32
all produce the reference `checksum=3745966`; only i386 won't compile).

## Pre-existing — NOT from the C float work

Confirmed by stashing the C double-value-model changes and rebuilding a clean
compiler: the clean binary fails i386 mandelbrot with the identical error. The
i386 param-copy loop in `parser.inc` (~12450, the `Error('target i386: only
ordinal/pointer parameters supported yet')` guard) rejects a by-value param that
is neither ordinal/float-handled, pointer-sized, nor a string/class/variant
handle. A pulled RTL unit now declares such a param (a by-value `Double`, or a
small record) that the i386 callee-prologue path does not yet copy.

## Fix direction

Extend the i386 param-copy (`parser.inc`, the `if TargetArch = TARGET_I386`
prologue block) to handle a by-value `Double`/`Single` param: copy the 8/4-byte
value from the caller's pushed stack arg into the frame slot (mirroring the
existing tyDouble path that already exists for the i386 *fat-slot* model — the
guard fires before reaching it for some shape). The other targets already pass,
so this is i386-local. Gate = `make test-float-determinism` green on all four.
