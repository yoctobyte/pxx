---
slug: bug-a-shared-reports-an-internal-error-on-four-targets-where-i386-gets-a-clean-refusal
track: A
type: bug
prio: 30
status: backlog
found: 2026-09-05
found-by: frankD
owner: ""
blocked-by: []
summary: "`--shared` is x86-64 only and correctly says so on i386. On aarch64, arm32, riscv32 and xtensa the same deliberate limitation surfaces as `error: internal: no init/fini thunk prologue for --target=<t>` — an internal-error string for a documented, intended refusal. Four of five non-x86-64 targets tell the user the compiler broke; one tells them the truth. Reproduces identically under pin v403 and at HEAD."
---

# `--shared` reports an internal error where i386 gets a clean refusal

Measured under pin v403 (`c31d03b202da`) and again at HEAD `ce19e5482`
(`9bcfd2b4da30`) — identical both times, so this is not a recent regression:

```
$ pascal26 --target=i386    --shared t.pas t.so
error: --shared: shared-library output is x86-64 only
$ pascal26 --target=aarch64 --shared t.pas t.so
error: internal: no init/fini thunk prologue for --target=aarch64
$ pascal26 --target=arm32   --shared t.pas t.so
error: internal: no init/fini thunk prologue for --target=arm32
$ pascal26 --target=riscv32 --shared t.pas t.so
error: internal: no init/fini thunk prologue for --target=riscv32
$ pascal26 --target=xtensa  --shared t.pas t.so
error: internal: no init/fini thunk prologue for --target=xtensa
```

x86-64 works, so the restriction is real and intended.

## Why the wording is the bug and not a cosmetic

The i386 arm is the correct behaviour: a deliberate, documented limitation
reported as one. The other four reach a *later* stage that has no thunk for the
target and fail there, so the user is told **`internal:`** — the string the
compiler reserves for "the compiler is broken". That is a false statement about
whose fault it is, and it routes the reader wrong: the reasonable response to
`internal:` is to file a compiler bug, and the correct response here is "this
feature is x86-64 only", which the docs already say.

It is the same shape as
[[bug-a-the-emit-obj-refusal-names-a-target-set-that-excludes-x86-64]] — the
diagnostic being the instrument a reader trusts over the docs, and being the
thing that is wrong. That one is fixed; `--emit-obj` now answers `--emit-obj: no
object writer for --target=<t>` on aarch64 and arm32, which is exactly the shape
this one wants.

## The fix

The refusal that i386 gets should be reached for every non-x86-64 target, at the
same early point, rather than four targets falling through to the thunk stage.
One target test where the existing one is, not four new arms.

## Aperture

Found by executing the sweep method in
[[bug-d-docs-scope-claims-about-a-flag-are-invisible-to-a-flag-existence-sweep]]
across `docs/**`. **The documentation is correct here** — `docs/reference/cli.md`,
`docs/reference/limits.md` and `docs/reference/objects.md` all say `--shared` is
x86-64 only, and all three are right. This is purely the compiler's message for
a limitation the docs already state accurately.
