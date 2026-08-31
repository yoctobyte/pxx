---
track: A
prio: 25
type: feature
blocked-by: []
created: 2026-08-31
summary: "Ruled 2026-08-31: a Pascal-reduced compiler must be able to compile the FULL compiler — it must be a valid seed, not merely self-hosting. Nothing tests this: there is no PXX_NO_* wiring in Makefile or tools/gate.sh at all, so no reduced configuration is built or gated by anything today. Build the pascal-reduced configuration, assert it produces a working umbrella compiler, and wire it where it will actually run."
---

# The Pascal-reduced build must be able to seed the full compiler

Implements the ruling in
`decided/decide-what-a-reduced-compiler-must-still-self-host.md`.

## The rule

A compiler built with every omittable frontend and target switched off — leaving
Pascal and the x86-64 host, which are **not omittable** — must be able to compile
`compiler/compiler.pas` in its FULL configuration and produce a working umbrella
compiler.

**This is a seed property, not a self-host property**, and the difference is the
point. Self-hosting asks a build to reproduce *itself*. This asks the smallest
Pascal build to produce *everything*, which is what makes it a bootstrap anchor
and what would let this project stand up from something other than FPC.

## What exists

Fourteen omission defines ship:

```
frontends  PXX_NO_ADA ALGOL BASIC CFRONT ERLANG FORTRAN LOLCODE NILPY RUST WHITESPACE ZIG
targets    PXX_NO_AARCH64 ARM32 I386
```

There is **no** `PXX_NO_PASCAL` and no way to omit the x86-64 host — verified at
HEAD, and worth restating because a Track U ticket spent eleven days on a fork
that assumed otherwise.

## What does not exist

`grep PXX_NO_ Makefile tools/gate.sh` returns **nothing**. No reduced
configuration is built, run, or gated anywhere in the repo. The parent
(`unfinished/feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets`)
ships the defines; nothing exercises them.

## The work

1. A named `pascal-seed` configuration: all eleven frontend omissions and all
   three target omissions on at once.
2. Build it with the pinned compiler.
3. **Use it to build the full compiler**, and assert the result works — the
   acceptance test is the seed property itself, not a byte comparison against
   the umbrella (a reduced compiler need not emit identical code, and demanding
   that would be a different and much stronger claim).
4. Then, separately, assert the produced umbrella compiler reaches its own
   fixedpoint. That chain — seed builds umbrella, umbrella reproduces itself —
   is the bootstrap claim end to end.

## Where it runs — decide before wiring, do not default it

A pin holds the repo-wide lock, so adding minutes to it taxes every lane and the
human. Two honest homes: in the pin (small, named, always-checked) or in Track
T's async matrix against the pushed sha. **T sweeps zero reduced configurations
today**, so choosing T means filing the work in T's lane, not inheriting it.
Measure the seed build's cost first; that number decides it.

## The trap this must not fall into

Per CLAUDE.md's guard rule, ship with a **positive control**: a deliberately
broken configuration the check is asserted to REJECT. A configuration test that
has never been shown able to fail is the same animal as a guard that cannot
fail, and this one is unusually exposed — the omissions are `{$ifdef}`s, so a
misspelled define name silently omits nothing and the build passes for the wrong
reason, looking exactly like success.

## AMENDMENT 2026-08-31 — Pascal cannot be omitted, and "C only" is a CLI decision

Repriced 55 -> 25 (owner: *"compiler reduction is low prio and more a feature
for low-memory targets"*).

The Pascal frontend is **intrinsic**, not merely un-omitted: `lib/rtl/pxxcio.pas`
(Pascal) implements `__pxx_write` that `lib/crtl/src/stdio.c` calls,
`compiler/builtin/builtinheap.pas` is a Pascal unit linked into every binary,
and the PAL is `lib/rtl/pal*.pas`. **A C program compiled by pxx links Pascal
source that must be compiled**, so omitting Pascal yields a compiler that cannot
emit a working program in any language.

So a "C only" or "NilPy only" product — which the owner says should be
grantable — is a **CLI-surface restriction**: refuse `.pas` as user input, keep
the frontend internally for the runtime. That is a separate, cheap piece of work
and it removes no code. **It is NOT this ticket**, and it must not be
implemented as an omission define.
