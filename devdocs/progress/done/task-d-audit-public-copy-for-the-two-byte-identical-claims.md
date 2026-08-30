---
track: D
prio: 55
type: task
status: done
owner: frankD
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

## Done — 2026-08-30, frankD

**No conflation found.** Not one sentence in `docs/**` or the README claims or
implies that PXX emits gcc's machine code. Every gcc mention outside `--doctor`'s
toolchain list is one of the two explicit disclaimers, and both are correct.

The defect is the **other** qualifier, and it is everywhere the first one is not:
**five of the six self-host claims in public copy did not name their optimisation
scope.** All five corrected.

### Scope 1 — the identity vocabulary

| site | before | verdict |
| --- | --- | --- |
| `README.md:39` | "requires a byte-identical fixedpoint before replacing it" | **fixed** — scope added |
| `README.md:95` | "only after the self-built compiler reaches byte-identical fixedpoint" | **fixed** — scope added |
| `docs/features/index.md:27` | "Byte-identical fixedpoint builds are part of the development gate." | **fixed** — the tersest instance in the tree, and it named neither the scope nor which of the two claims it was |
| `docs/reference/status.md:28` | "reproduces that binary **byte for byte**" | **fixed** — the definitional passage, so its omission taught the gap |
| `docs/targets/nil-python.md:10` | "the self-host fixedpoint byte-identical" | **fixed** — scope added |
| `docs/dive/index.md:46, :87` · `glossary.md:17, :78` · `cli.md:92-98` | — | **already correct** (corrected 2026-08-29) |

`features/index.md` is the one worth looking at, because it is the shape the
ticket predicted: a single clause, no qualifiers, in a bullet list of selling
points. **The shortest version of the sentence really is the wrong one.** It now
names the level *and* points at `status.md` for the distinction, on the principle
that a feature list is where a reader forms the impression the reference page
later has to correct.

### Scope 2 — comparisons to gcc / FPC / clang / CPython: clean

- Only two substantive gcc references exist and both are disclaimers:
  `status.md:35` (*"PXX does not emit the same machine code as gcc, and does not
  claim to"*) and `cli.md:96-98`. The rest are `--doctor` listing which
  toolchains a box has.
- No "drop-in", "clone", "bug-for-bug", "100% compatible" anywhere. The `clone`
  hits are `git clone`.
- `status.md:71` is exemplary and needs nothing: *"'works' below means this
  dialect compiles and runs the code, not PXX is indistinguishable from FPC."*
- `status.md:122` states the CPython oracle correctly — *the expected output in
  the gate **is** CPython's own output for the same program*.
- Checked rather than assumed: `features/index.md`'s new sentence says "output
  parity against gcc- **and FPC**-built references", so FPC had to actually be an
  output oracle and not merely a dialect reference. It is —
  `tools/fpc_diff_probe.sh` runs it as one, with a documented note that the box's
  stable oracle is FPC 3.2.2 from 2021.

### Scope 3 — and a second qualifier nobody had written down

`docs/dive/index.md:58` said *"x86-64, i386, aarch64, and arm32 self-host
byte-identical."* **The claim is true** — verified in `Makefile:13809`, the
`cross-bootstrap` rules: cross-compile `compiler.pas` for the target, run *that*
binary under QEMU to compile `compiler.pas` again, `cmp` the two.

But the native and cross proofs are **not the same configuration**, and no public
page said so:

| | native | the three cross targets |
| --- | --- | --- |
| build flags | none — `PXXFLAGS` is empty | `-dPXX_MANAGED_STRING` |
| the Makefile's own words | — | *"Managed runtime (`-dPXX_MANAGED_STRING`) is **required**."* |

So "all four self-host byte-identical" reads as one gate and is two. The bullet
now says which is which. **Not explained, only stated** — *why* the managed
runtime is required for the cross bootstrap is a Track A question and asserting a
reason would be inventing one.

This is the same failure mode as the `-O` scope, one axis over: a true claim
whose qualifier lives in a Makefile comment nobody reading `docs/**` will see.

### Nothing was weakened

Per the ticket: turning a strong claim into a weak one is its own defect. Every
edit **adds** a qualifier or a distinction; none removes or hedges a claim. The
fixedpoint claim is still that the compiler reproduces its own binary to the
byte, and the corpus claim is still that a pxx-built zlib's compressed stream
matches a gcc-built zlib's. Both are strong. They are now stated at the precision
that survives an adversarial reader, which is the only precision worth having in
a launch-facing page.

### Gate
`tools/docsnip.py` — 39 complete programs, **BROKEN 0** against v394
`e2ea9034a65ea8b6`. `tools/doclinks.py` — 8 distinct external links, **BROKEN 0**.
No compiler rebuild; no `lib/**`; no code touched.

## Log
- 2026-08-30 — resolved, commit ef229ba7d.
