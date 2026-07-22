---
prio: 50  # auto — blocks Synapse SSL end-to-end, the last open item of the dynlib loader
track: A
---

# `cdecl` indirect call with more than 6 integer args is rejected

- **Type:** bug — **Track A** (call ABI / `ir_codegen.inc`, the cdecl indirect
  path).
- **Status:** done
- **Found by:** Track B, attempting item (d) of
  [[feature-real-dynlib-loader]] — compiling Synapse's `ssl_openssl3_lib.pas`.

## Repro

```pascal
program Cd7;
type
  TFn7 = function(a, b, c, d, e, f, g: PtrInt): PtrInt; cdecl;
var p: TFn7; r: PtrInt;
begin
  p := nil;
  if p <> nil then r := p(1, 2, 3, 4, 5, 6, 7);
  writeln('compiled');
end.
```
```
pascal26:11: error: cdecl indirect call: more than 6 integer args not supported yet
```
The same program with six parameters compiles and links fine. So the boundary is
exactly the six System V integer argument registers — anything that has to spill
to the stack is refused.

## Why this matters now

It is the remaining blocker for the last open item of the dynlib-loader ticket.
`external/synapse/ssl_openssl3_lib.pas` binds OpenSSL 3 through `dlopen` +
function pointers, and OpenSSL has plenty of 7+ argument entry points, so the
unit cannot be compiled at all — which means the Synapse-SSL end-to-end test
that would actually exercise the loader cannot be written.

At least it fails **loudly**: a compile error naming the limitation, not silent
mis-marshalling. That is the right behaviour for an unimplemented case and worth
keeping until the real thing lands.

## Note on [[feature-cdecl-indirect-cross-targets]] (marked done)

That ticket's acceptance list includes:

> A `cdecl` proc-type indirect call with float and >6/>4 args marshals correctly

which is not true today on x86-64 — the case is rejected outright. Either the
acceptance was written for the direct-call path and the indirect one was never
covered, or a later change narrowed it. Worth reconciling while fixing this:
if that ticket's tests do cover >6 args, they are not exercising the indirect
path, and the gap that let this through is itself worth closing.

## Scope

- x86-64 System V: args 7+ go on the stack, right to left, with the 16-byte
  alignment requirement at the call. The direct-call path already does this;
  the indirect path needs the same treatment.
- Check the float side too (`>4` xmm args) — the message only mentions integers,
  so floats may be separately limited or separately broken.
- Other targets have different register counts (aarch64 8, i386 all-stack);
  the cross-target ticket above is the natural home for those.

## Acceptance

- The repro compiles, links, and calls through correctly with 7, 8 and 12
  integer args, verified against a C callee built by gcc.
- Mixed int/float beyond both register files.
- `external/synapse/ssl_openssl3_lib.pas` compiles.
- Track A gate: `make test` + self-host byte-identical, plus cross.

## Links
[[feature-real-dynlib-loader]] (item d, blocked on this) ·
[[feature-cdecl-indirect-cross-targets]] (marked done; acceptance overlaps).

## Log
- 2026-07-20 — Filed from Track B with the minimal repro.
- 2026-07-22 — resolved, commit 58e0a7a5.
