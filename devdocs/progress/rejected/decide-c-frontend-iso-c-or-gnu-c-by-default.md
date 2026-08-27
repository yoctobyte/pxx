---
slug: decide-c-frontend-iso-c-or-gnu-c-by-default
title: "C frontend: is the DEFAULT dialect the C standard, or GNU C?"
track: U
prio: 45
type: decide
blocked-by: []
status: rejected
owner: unassigned
created: 2026-08-27
summary: "REJECTED 2026-08-27, same day, by the coordinator who filed it — the fork does not exist. Measured: the C frontend ALREADY accepts __attribute__, __extension__, __builtin_*, statement expressions, __asm__ and __inline, so GNU-by-default is the implemented status quo, not a pending decision. And accepting a SUPERSET of the standard is not a divergence from it — the same rule Pascal and NilPy already run on. Owner: 'C is well defined by formal standards... gcc is an oracle, we use it as. but it has not been an issue so far.' Original framing follows. The owner's 2026-08-27 refinement says the reference is the SPEC and an implementation's habits go behind --strict-<impl>. For C that collides with the frontend's stated purpose — real-world C compiles unmodified — because real-world C (busybox, zlib, QuickJS) is full of GNU extensions no standard describes. And --strict-gcc does not exist: C is the only frontend with no flag for its reference implementation. Recommendation: follow gcc's own precedent — default to the extended dialect, make SPEC-ONLY the opt-in (--strict-c), not the reverse."
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

---

## REJECTED the same day, by the coordinator who filed it

Owner, 2026-08-27, on the C half of the spec-vs-implementation refinement:

> *"C is well defined by formal standards. it may be that gcc is wrong, unlikely
> but.. so gcc is an oracle. we use it as. but. it has not been an issue so far
> since C is well defined."*

That plus one measurement dissolves the fork. **Both halves of what I called a
tension are already true at once, and they were never in conflict.**

### 1. The conformance half was never open

The standard is the **authority**; gcc is the **instrument**. Those are different
roles and the owner has now named both. gcc could in principle be wrong, in which
case the standard wins — but *"it has not been an issue so far since C is well
defined"*, which is the practical reason `tools/gcc_diff_probe.sh` settles
arguments without anyone having to adjudicate the two. Nothing to decide.

### 2. The extension half is already implemented — I filed a decision about the status quo

Measured in `compiler/clexer.inc`, `cparser.inc`, `cpreproc.inc`:
`__attribute__`, `__extension__`, `__builtin_*`, statement expressions, `__asm__`
and `__inline` are **all already handled**. GNU-by-default is not a proposal; it
is what ships. Option B of the original ticket was a recommendation to adopt what
the code already does.

*(Incidental, and deliberately not filed as anything: `__GNUC__` is **not**
predefined, so a library probing `#ifdef __GNUC__` takes the non-GNU path. That
looks right — we accept GNU syntax without claiming to be gcc, which is exactly
the posture `frontend-compat-philosophy.md` recommends toward identity-probing
libraries. If it ever costs a corpus something, that is an ordinary Track C
ticket with a named program, not a philosophy question.)*

### 3. The framing error — a superset is not a divergence

The real mistake was treating "accepts more than the standard describes" as a
*deviation from* the standard. It is not, and the project already says so twice:

| frontend | the rule already in force |
| --- | --- |
| Pascal | *"we accept a form FPC rejects → **not a defect**"* (CLAUDE.md compat table) |
| NilPy | *"NilPy accepting something CPython rejects is a **feature, not a defect**"* |
| **C** | **same shape**: accepting `__attribute__` takes nothing away from a program that does not use it |

So the C position is consistent with the other two and needs no new flag: **the
standard is the authority for the programs the standard describes, and accepting
a superset costs conformance nothing.** A `--strict-c` that rejected extensions
would be a *feature request* — and one nobody has asked for, with no program whose
behaviour it would fix.

### What would have made this a real ticket

A named program that compiles wrong — not merely differently — because of an
extension decision. There isn't one. Per CLAUDE.md's compat table, *"a ticket that
cannot name a program whose behaviour changes is a `rejected/` ticket, not a
low-prio one"*; parking it at prio 45 would have kept it in the ranker's scan
forever at zero value.

**Lesson for the coordinator, since the mandate is fresh:** *derive, don't
escalate* has a second half — **measure before escalating.** One grep of the C
frontend would have shown the fork was closed before the ticket was written, and
the ticket cost the owner a round trip. Escalating a question the code already
answers is the same error as guessing at one it does not; both spend the scarce
resource, which is the owner's attention.
