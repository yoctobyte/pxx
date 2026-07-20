---
prio: 60  # auto — silent dead code on a form FPC accepts; nothing warns, nothing fails
track: A
---

# A unit's `begin ... end.` initialization section is silently never executed

- **Type:** bug — **Track A** (unit initialization in `compiler/parser.inc` /
  the unit-init emission path).
- **Status:** backlog — filed 2026-07-20 (**refiled** — see Correction).
- **Found by:** Track E, building `examples/mandelbrot/mandelkernel.pas`.

## Correction to the original filing

This was first filed as `bug-file-io-silently-fails-in-unit-init`, claiming
Text file I/O did not work in a unit initialization section. That diagnosis was
**wrong**. File I/O was never the problem: the initialization section was not
running at all, so the probe inside it never executed and the variable it
assigned kept its BSS zero value — which looked exactly like "the file read
failed". Narrowing with an integer stage counter instead of a Boolean is what
exposed it.

## Repro

```pascal
unit ubegin;
interface
var BeginRan: Integer;
implementation
begin
  BeginRan := 111;
end.
```
```pascal
unit uinitkw;
interface
var InitRan: Integer;
implementation
initialization
  InitRan := 222;
end.
```
```pascal
program T2;
uses ubegin, uinitkw;
begin
  writeln('begin-form      = ', BeginRan, '   (expect 111)');
  writeln('initialization  = ', InitRan, '   (expect 222)');
end.
```
```
begin-form      = 0   (expect 111)
initialization  = 222   (expect 222)
```

So `initialization ... end.` works and the classic `begin ... end.` form is
parsed, accepted, and then dropped.

## Why it matters

Both forms are legal Pascal and FPC treats them as equivalent — `begin ... end.`
is the Turbo Pascal spelling and is still common in real code, so this will bite
anything ported in. The failure mode is the worst kind:

- No compile error. No warning. No runtime error.
- The variables the section assigns keep their BSS zeros, which very often
  *look* plausible — `nil` pointers, `False` flags, zero counts.
- Consequently a unit can appear to work for a long time and then misbehave the
  first time an init value differs from zero.

The narrowing above is a good illustration: the assigned value happened to be a
Boolean, the zero default was `False`, and that read as a legitimate "capability
not present" answer. It cost a wrong bug report before the real cause surfaced.

## Blast radius in-tree: currently nil, by luck

A sweep of every `unit` in `lib/**` and `examples/**` finds exactly **three**
with a non-empty `begin`-form initialization section, and all three assign only
zero-equivalents, so the dead code is currently harmless:

| unit | body | zero-equivalent? |
| --- | --- | --- |
| `lib/rtl/tls.pas` | `gBackend := nil;` | yes |
| `lib/rtl/tls_openssl.pas` | `gLib := NilHandle; gClientCtx := nil; gServerCtx := nil; gBackend := nil;` | yes |
| `examples/mandelbrot/mandelkernel.pas` | three flag/enum resets to their zero values | yes |

All three have been converted to `initialization` under Track B so the code is
live rather than silently dead, but that is a fix for those consumers — it does
not fix the compiler, and the next person to write the classic form gets the
same trap.

## Suggested handling

Fix is presumably small: emit the `begin`-form body into the same unit-init
chain `initialization` already feeds. While in there, worth settling:

- `finalization` — does it run? Not tested here; the same emission path is
  suspect.
- Unit init **ordering** — the sweep did not establish whether initialization
  sections run in dependency order. Worth a test either way.
- If for some reason the `begin` form is deliberately unsupported, it must be a
  **compile error** naming the alternative, never silent acceptance.

## Acceptance

- The repro prints `111` / `222`.
- A regression test covering both forms, plus one asserting dependency ordering.
- `finalization` checked and either working or ticketed.
- Track A gate: `make test` + self-host byte-identical.

## Links
`examples/mandelbrot/mandelkernel.pas` · `lib/rtl/tls.pas` ·
`lib/rtl/tls_openssl.pas` · [[feature-demo-mandelbrot-gui-threaded]] (where it
surfaced).

## Log
- 2026-07-20 — Filed as `bug-file-io-silently-fails-in-unit-init` with a wrong
  diagnosis (file I/O).
- 2026-07-20 — **Refiled** under the real cause after narrowing with an integer
  stage counter: the whole init section never runs. Added the in-tree sweep
  (3 affected units, all currently harmless) and the `finalization` / ordering
  follow-ups.
