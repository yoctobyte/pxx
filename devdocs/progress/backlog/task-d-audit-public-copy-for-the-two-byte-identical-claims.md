---
track: D
prio: 55
type: task
status: backlog
owner: unassigned
blocked-by: []
summary: "CLAUDE.md's claims-discipline section names two DIFFERENT byte-identical claims -- the self-host fixedpoint (our BINARY reproduces itself, at the default -O only) and the corpus oracle (a pxx-built zlib's OUTPUT matches a gcc-built zlib's). Conflating them implies we emit gcc's machine code, which we do not. Nobody has audited docs/** or the README for the conflation, and terse styles drop the qualifying words first."
---

# Audit public copy for the two different "byte-identical" claims

- **Type:** task — **Track D** (prose only: `docs/**`, README, release notes copy).
  Never `compiler/**` or `lib/**`.
- **Filed:** 2026-08-30 by the coordinator, dispatching a dry Track D queue onto
  work that is real rather than manufactured.

## The distinction, from CLAUDE.md

| claim | what is identical | to what | kind |
| --- | --- | --- | --- |
| **self-host fixedpoint** | the **binary** | our own previous output | true binary reproducibility, **at the DEFAULT `-O` level only** |
| **corpus vs the gcc oracle** | the program's **OUTPUT** (e.g. zlib's compressed stream) | the output of a gcc-**built** zlib | *behavioral* parity |

We do **not** emit the same machine code as gcc and must never imply it. The correct
form is *"zlib built with pxx produces compressed output byte-identical to a gcc-built
zlib's"* — never *"zlib byte-identical to gcc"*.

**Both claims are strong. They are strong for different reasons**, and the qualifying
words ("output", "oracle", "built with") carry the entire distinction.

## Why this is worth a ticket rather than a habit

CLAUDE.md says it plainly: *a compiler engineer will catch it in seconds and the
correction costs more than the claim ever gained.* And the failure mode is
**compression** — terse styles drop the qualifiers first, so the shortest version of
each sentence is the wrong one. That is face 173's pressure (the amplified claim is
more quotable than the accurate one) applied to public copy, where there is no peer
to refute it.

**Second qualifier, and it is newer than most of the copy:** the fixedpoint proves
byte-identity **at one optimisation level**. `make compiler/pascal26` builds
`compiler.pas` at the default `-O`, and nothing in the per-fix loop self-compiles at
another level — a `-O0`-only self-compile failure passed the entire gate on
2026-08-19 and was found by a benchmark. So *"it compiles itself"* is a wider claim
than *"it passes the self-host gate"*, and any copy that leans on the property should
say which it means.

## Scope

Audit and correct, in `docs/**` and the README:

1. Every occurrence of "byte-identical", "bit-identical", "identical output",
   "reproduces itself", "reproducible" — classify each as fixedpoint or oracle, and
   check the sentence carries the words that distinguish them.
2. Every comparison to gcc, FPC, clang or CPython: does it claim **output** parity or
   imply **code** parity?
3. Any self-host claim that does not name its optimisation scope.

**Report, do not invent.** Where the copy is ambiguous rather than wrong, propose the
corrected sentence in the ticket and let it be reviewed — rewriting a strong claim into
a weak one is its own defect, and both claims here are genuinely strong.

Out of scope: the website's own repo (Track W), `devdocs/**` (A/B's), and any code.

## Gate

Docs stay internally consistent; any snippet touched compiles against `$(PXX_STABLE)`
(currently v394 `e2ea9034a65ea8b6`) — never rebuild the compiler. A compiler or library
gap found while auditing → file a ticket in the owning lane, do not fix code.

## Method note for whoever takes it

Verify by **fetching or running**, not by reading the doc's description of itself.
frankD's `tools/doclinks.py` (resolved 2026-08-30) is the precedent and the instrument
for the external-link half. And carry frankD's own finding from the same day: **a wrong
command is wrong on every run, agrees with itself every time, and therefore reads as
verification** — so a re-measure command printed beside a figure must be *run* before it
is written down. See face 184 in
[[feature-a-a-refusal-is-a-claim-with-a-date-on-it]].
