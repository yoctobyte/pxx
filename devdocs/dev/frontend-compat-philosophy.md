# What "compatible" means, per frontend

Three frontends, three DIFFERENT answers, and confusing them produces confident
wrong work — an agent chasing FPC parity in Pascal where the dialect is
deliberate, or filing a permanent NilPy limit as a bug that stays open forever.

Stated by the project owner, 2026-08-17. This is the lookup for the roster's
"philosophy check before escalating": most compat questions are settled here and
should be DERIVED, not escalated.

---

## C — compliance. No dialect.

> *"C is straightforward — no dialects, just compliance."*

gcc / ISO C is the oracle and there is nothing to negotiate. A difference from
gcc is a **bug**, full stop. There is no "pxx's C dialect" and there should never
be one: the value of the C frontend is that real-world C compiles unmodified, so
every divergence is a subtraction from the only thing it is for.

Practical consequence: `tools/gcc_diff_probe.sh` settles arguments. If gcc and
pxx disagree, pxx is wrong until someone proves the program is relying on
undefined behaviour.

## Pascal — its own dialect, ON PURPOSE.

> *"Pascal IS its own dialect. Because I want it, because it is the 'cement' in
> between all languages, and because it's the language I know best."*

This is the one most likely to be got wrong, because it inverts the usual
instinct. **"FPC does X" is not by itself an argument for pxx doing X.** The
Pascal frontend is a language we are designing, not a reimplementation we are
scoring against a reference.

Three reasons, and the middle one is the load-bearing one:

1. It is wanted. That is sufficient on its own — this is the owner's language.
2. **It is the cement between the frontends.** Pascal is what the compiler is
   written in and what the RTL is written in, so it has to be expressive enough
   to serve every other frontend's runtime. That pulls it AWAY from historic FPC
   restrictions rather than toward them.
3. It is the owner's strongest language, so design judgement is best there.

FPC parity is still available and still valued — behind the `--strict-*` family,
and as the `compat` work-tag. See `meta-dialect-extensions-and-fpc-strict` for
the contract every extension follows. The default stays deliberately lax.

**The line that still holds:** a *silent wrong VALUE* is a bug in any dialect.
Being our own dialect licenses different SEMANTICS chosen on purpose; it never
licenses a wrong answer nobody chose. CLAUDE.md's escape rule says exactly this,
and it is what makes the unary-minus truncation a bug rather than a dialect
choice.

## NilPy — upward compatible with CPython, minus what a static compiler cannot do.

> *"NilPy has some unsolvable issues, since we are a static compiler. Most have
> (sane) workarounds, but some issues have not — in which case we just need to
> eat and document the incompatibility."*

The standing rule is one-directional: **a program CPython accepts and runs must
work under NilPy.** NilPy accepting something CPython rejects is a feature, not a
defect.

What the owner has now made explicit is a **third category**, which
`nilpy-semantics-divergences.md` was not written to hold:

| category | what it is | what to do |
| --- | --- | --- |
| **bug** | CPython accepts it, NilPy gets it wrong, and it is fixable | file it, fix it |
| **chosen divergence** | differs on purpose, unobservable to an accepting program | `nilpy-semantics-divergences.md` |
| **permanent limit** | CPython accepts it, an accepting program CAN observe the difference, and **static compilation cannot express it** | document it as permanent; do NOT leave it open as a bug |

The third one matters because of what it costs to get wrong. A permanent limit
filed as an ordinary bug sits in the backlog forever, gets re-diagnosed by each
new session, and quietly implies the project is failing at something it never
promised. Naming it as permanent is not defeat — it is the honest boundary of
"compile Python statically", which is the whole premise.

**Before declaring one permanent, the bar is high**: show that the workaround
space is genuinely empty, not merely that the obvious approach failed. "Most have
sane workarounds" is the owner's own framing, so the default assumption is that a
workaround exists and has not been found yet. A permanent-limit claim is a
Track U escalation, not a worker's call.

---

## What a CORPUS is for — and why difficulty in one is not a defect

Stated by the project owner, 2026-08-17, after a session built a case for compiler
work on a justification that did not hold.

**A corpus is a measuring instrument, not a dependency.** It earns its place by
being code we could not have unconsciously shaped to fit what we already support.
It does not have to be pleasant to integrate against, because nothing integrates
against it.

Worked example, Synapse:

> *"We already implemented our own TCP stack, including SSL. Synapse is a TEST
> library, not something we will build on in practice. It serves to test Pascal.
> Anything written there is native for Python these days. If we ever need it, we
> chase it when the time comes."*

So the value of Synapse is **real third-party Pascal that compiles as-is**, with
byte-exact codec vectors against FPC. Its SMTP/FTP/etc are genuinely good code and
are not the point. This cuts two ways and both matter:

**1. Do not justify core work with a corpus.** Before proposing a compiler change,
ask what actually DEPENDS on the thing that motivated it. A case can be built
where every observation is correct, every measurement sound, and the whole thing
aimed at a library we will never ship against — the repo's recurring
"true fact about the wrong subject", arriving as misplaced PRIORITY rather than a
wrong conclusion. See `decide-what-synapse-actually-needs-vs-mimic-fpc`, kept at
prio 20 as the worked example.

**2. Difficulty compiling an OLD corpus is expected cost, not a bug signal.**

> *"Compiling Synapse as-is already takes hacks because it's full of
> platform/compiler dependent ifdefs."*

Two decades of Pascal means a thicket of directives probing for compilers, RTLs
and platforms that are not us. When such a library needs coaxing, the default
reading is **the library is identity-probing**, not **our compiler is wrong**. So
a `--mimic-fpc` define set is a legitimate answer, not a workaround to be
apologised for or narrowed by hand.

The line that still holds, because it is the one the platonic-code rule protects:
if the compiler produces a **silently wrong value** on corpus code, that is a bug
in any corpus, however old. Ugliness getting it to *compile* is expected;
wrongness once it *runs* never is.

**Where this does NOT apply:** a corpus we intend to build on is a dependency, and
the calculus flips — then integration friction IS worth fixing. Ask which kind you
have before spending.

---

## Why these differ at all — the thing worth understanding

The three positions are not inconsistent; they follow from what each frontend is
FOR.

- C exists to compile the world's existing C. Divergence destroys the purpose.
- Pascal exists to be the substrate the rest is built in. Constraint destroys the
  purpose.
- NilPy exists to compile Python **statically**, which is a thing CPython is not.
  Some of the gap is the point, not a defect.

`ir-as-substrate.md` is the north star behind all three: push generality down
into the IR, keep frontends thin. A frontend that needs a special case is usually
telling you the IR is missing something.
