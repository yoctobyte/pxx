---
slug: decide-c-frontend-iso-c-or-gnu-c-by-default
title: "C frontend: is the DEFAULT dialect the C standard, or GNU C?"
track: U
prio: 45
type: decide
blocked-by: []
status: backlog
owner: unassigned
created: 2026-08-27
summary: "The owner's 2026-08-27 refinement says the reference is the SPEC and an implementation's habits go behind --strict-<impl>. For C that collides with the frontend's stated purpose — real-world C compiles unmodified — because real-world C (busybox, zlib, QuickJS) is full of GNU extensions no standard describes. And --strict-gcc does not exist: C is the only frontend with no flag for its reference implementation. Recommendation: follow gcc's own precedent — default to the extended dialect, make SPEC-ONLY the opt-in (--strict-c), not the reverse."
---

# C frontend: standard-by-default, or GNU-by-default?

## The fork

The owner refined the compat philosophy on 2026-08-27:

> *"we rather work for specs (what does formal pascal/c/python spec say) as
> compliance"* — with an implementation's own behaviour reached through
> `--strict-<impl>`.

Applied to Pascal and NilPy this is clean: `--strict-fpc` and `--strict-python`
both exist, and the default is our own dialect / upward-compatible NilPy.

**Applied to C it collides with the C section of
`frontend-compat-philosophy.md`,** which says the C frontend exists so that
*"real-world C compiles unmodified"* and that *"a difference from gcc is a bug,
full stop."*

Both cannot be the default at once:

- Real-world C is **GNU C**. busybox, zlib and QuickJS use `__attribute__`,
  statement expressions, `__builtin_*`, anonymous unions, `case a ... b` ranges.
  No C standard describes these.
- Standard C is the **spec**. Complying with it is what the refinement asks for,
  and it is the only stable written reference — "what gcc does" is a moving
  target defined by an implementation.

## Measured state

`--strict-gcc` **does not exist.** The shipped family is `--strict-case`,
`--strict-fpc`, `--strict-ir`, `--strict-operator`, `--strict-overload`,
`--strict-overload-width`, `--strict-python`, `--strict-uses`,
`--strict-visibility`, plus `--mimic-fpc` / `--mimic-fpc-compiler`.

So **C is the only frontend with no flag naming its reference implementation**,
and the refinement's C half currently has no mechanism at all. Whatever is
decided here, something has to be built.

## Options

**A. Spec by default; GNU extensions behind a flag (`--gnu` / `--strict-gcc` inverted).**
Literal reading of the refinement. Cost: every C corpus needs the flag from day
one, so the flag is always on in practice and the "default" is a mode nothing
uses. Risk: a default no real program compiles under is a default in name only.

**B. GNU C by default; spec-only behind `--strict-c` (RECOMMENDED).**
Follows **gcc's own precedent** — gcc defaults to `-std=gnu17` and makes strict
ISO (`-std=c17`) the opt-in. This satisfies the refinement's *structure* (the
spec is a mode you can demand, and it is the written reference) while keeping the
frontend's purpose intact (the world's C compiles unmodified). It also makes the
flag name honest: `--strict-c` says "hold me to the standard", which is a thing
someone actually wants, whereas `--strict-gcc` would mean "be bug-compatible with
a specific implementation", which is not what anyone was asking for.

**C. Two axes: `--std=` for the language level, `--strict-c` for pedantry.**
Most faithful to how C actually works, and the most build-out. Probably where B
ends up eventually; the question is whether to pay for it now.

## Recommendation

**B.** It is the only option under which both stated goals stay true at once, and
it has a strong precedent in the implementation the C frontend is measured
against. It also inverts the flag the owner named — `--strict-c`, not
`--strict-gcc` — which is worth confirming explicitly, since the owner's message
said `--strict gcc`.

## What is NOT in scope here

- **A silent wrong VALUE stays a bug** under any answer. This decides which
  *dialect* is the default, never whether a wrong answer is acceptable.
- **The gcc differential probes stay valid.** `tools/gcc_diff_probe.sh` compares
  behaviour of a compiled program, not conformance of the source; a divergence
  there is still a bug regardless of this decision.
