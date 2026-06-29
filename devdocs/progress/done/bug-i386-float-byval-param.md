# i386 backend: by-value set parameter unsupported

- **Type:** bug (i386 backend — Track A)
- **Status:** done
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
handle.

Instrumentation showed the actual rejected parameter was not a float:

```
name=Flags type=tySet size=32
```

The failing RTL declaration is `StringReplace(...; Flags: TReplaceFlags)`, where
`TReplaceFlags = set of TReplaceFlag`.

## Fix direction

Extend the i386 param-copy (`parser.inc`, the `if TargetArch = TARGET_I386`
prologue block) and internal-call argument push path to handle a by-value 32-byte
`tySet` param. The other targets already pass, so this is i386-local. Gate =
`make test-float-determinism` green on all four.

## Resolution

- i386 internal calls now push by-value sets as the full 32-byte payload.
- The i386 callee prologue accepts and copies that 32-byte payload into the
  parameter frame slot.
- By-value set params now get full local storage instead of a pointer-sized slot.
- `IR_LEA` for an i386 by-value set param now yields the local slot address, while
  by-ref set params keep the existing forwarded-pointer behavior.
- Added `test/test_i386_byvalue_set_param.pas` to `make test-i386`.

Verified:

```
make compiler/pascal26
make test-float-determinism
make test-i386
```
