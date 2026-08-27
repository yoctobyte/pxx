# What "compatible" means, per frontend

**One rule, three different reference points.** Owner, 2026-08-27: *"in general
we follow de-facto standards. be it formal or not."* The three sections below
look like three policies; they are one policy pointed at three different things,
and reading them as three is what produces confident wrong work — an agent chasing FPC parity in Pascal where the dialect is
deliberate, or filing a permanent NilPy limit as a bug that stays open forever.

Stated by the project owner, 2026-08-17. This is the lookup for the roster's
"philosophy check before escalating": most compat questions are settled here and
should be DERIVED, not escalated.

---

## THE GENERAL RULE — the de-facto standard is the FLOOR, not the ceiling

Owner, 2026-08-27: *"in general we follow de-facto standards. be it formal or
not."*

**Whatever real code actually targets is what must work.** Sometimes that is
codified in a formal spec (C), sometimes it is a dominant implementation with no
spec that matters (CPython), sometimes it is a living ecosystem we are
deliberately extending (Pascal). *Formal or not is not the question* — the
question is what working code in the wild depends on.

And the rule is directional. **The de-facto standard is a floor we must reach,
never a ceiling we must not exceed:**

| frontend | its de-facto standard | the FLOOR (must work) | above the floor |
| --- | --- | --- | --- |
| **C** | the formal C standard, as consulted through gcc | standard C compiles and runs correctly | GNU extensions accepted — already shipped, costs conformance nothing |
| **NilPy** | **CPython**, no formal spec involved | a program CPython accepts and runs must work | accepting more than CPython is a **feature** |
| **Pascal** | FPC / Delphi as the living ecosystem | real third-party Pascal compiles (this is the `compat` tag) | our own dialect, deliberately — *"the cement between the frontends"* |

Read that way, the three sections below stop being exceptions to each other. The
same two sentences generate all of them:

- **Reaching the floor is obligatory.** A form real code uses that we reject is a
  defect — a `compat` ticket ranked by how much real code uses it, or a plain bug
  when the code silently misbehaves.
- **Exceeding it is free.** Accepting a form the reference rejects is never a
  defect. CLAUDE.md's compat table already says this for Pascal (*"we accept a
  form FPC rejects → not a defect"*) and the NilPy section says it below; the C
  case was derived on 2026-08-27 and is the same shape.

**This is why *"we do not chase 100% FPC parity"* and *"Synapse must compile"* are
not in tension** — the long-standing confusion this table resolves. Compiling real
Pascal is the **floor**. Matching FPC's error numbers, message wording and RTTI
spelling is **ceiling behaviour**, which we explicitly do not chase. One is
obligatory, the other is not merely optional but actively deprioritised.

**The two carve-outs, and they are the only ones:**

1. **Static compilation.** *"Since we are a static compiler, not all wishes can be
   granted — that's the nature of pxx"* (owner, 2026-08-27). Some of the floor is
   genuinely out of reach for NilPy, and that is the **permanent limit** category
   below. The bar stays high: show the workaround space is empty, and escalate to
   Track U — a permanent-limit claim is not a worker's call.
2. **Reaching the floor is about COMPILING AND RUNNING, not about dying.** A
   strict flag governs how source is compiled and how values are formatted; it
   does not govern runtime-error numbers, exit codes or fault messages, which stay
   ours by default (CLAUDE.md, owner 2026-08-21).

### Laxness: an INSTANCE of the floor rule, with one real exception inside it

Owner, 2026-08-27: *"there are exceptions. for example, for pascal, we are more
lax by default and don't enforce certain (unnecessary) restrictions."*

**WHY we are lax — corrected by the owner, 2026-08-27, and this is the part to
lead with:** *"us being 'lax' is not intended to be incompatible. it is more
because of the odd design goal of pxx where we intend to be cross-language."*

Laxness is **not a position on compatibility at all.** It is a *consequence* of
the substrate requirement, and reading it as a compatibility stance gets the
causation backwards. Pascal is what the compiler and the RTL are written in, so
it has to be expressive enough to serve **every other frontend's runtime** — C's,
NilPy's, Rust's, Zig's. A restriction that is harmless in a Pascal-only world can
be exactly the thing that stops the RTL expressing what another language's
semantics need. That is the *"cement between the frontends"* reason above, and it
is the load-bearing one.

**This predicts which restrictions to drop, which a mere permission argument
cannot.** The test is not *"is being lax here harmful?"* — it is **"does this
restriction serve a cross-language substrate, or is it an accident of Pascal's
own history?"** Historic FPC restrictions are overwhelmingly the latter: they
constrain a single-language compiler for reasons that never applied to a
substrate serving five frontends. Those are the *"unnecessary restrictions"* — not
unnecessary because nobody is hurt, but unnecessary **to the job Pascal is doing
here.**

And note what laxness is *not*: **FPC-compatible code still compiles.** We accept
more; we reject nothing FPC accepts. So laxness never costs compatibility — it is
orthogonal to it, which is precisely why *"not intended to be incompatible"* is
the right way to say it.

The mechanical framing below is still correct, and still useful for deciding
whether a *specific* laxness is safe. It is just downstream of the reason: it
explains why dropping a restriction is **free**, while the paragraph above
explains why we **want** to.

---

The laxness is real and deliberate — but **most of it is not an exception to the
floor rule, it is the floor rule working.** "Lax" means *accepting source FPC
rejects*, which is exactly "exceeding the floor", which the table above already
calls free. It only looks like an exception if you read "follow the de-facto
standard" as "behave identically to FPC", which is the misreading the floor/
ceiling framing exists to prevent.

**But there is a real exception hiding inside it, and it is the line that
matters:**

| kind of laxness | what changes | free? |
| --- | --- | --- |
| **diagnostic** — we accept source FPC rejects | the set of accepted programs grows; every program both accept means the same thing | **yes, free.** Pure superset |
| **semantic** — the same source produces a different VALUE | the meaning of a program that already compiled everywhere | **NO.** This is the dangerous class |

The shipped flags sort themselves cleanly along that line, and the docs already
say so. `--strict-case`, `--strict-operator`, `--strict-visibility`,
`--strict-overload` and `--require-forward` are **diagnostic**: the lax default
parses visibility markers and grants access anyway, resolves overloads without
the `overload;` marker, permits `=`/`<>` on class operands. Nothing that compiles
under both means anything different. That is the "unnecessary restriction" the
owner is describing, and dropping it costs nothing.

`--strict-fpc`'s own documentation then flags the exceptions explicitly — it
*"switches two rules that change a **value** rather than a diagnostic: FPC shift
widths, and `Variant`→`Char`."* **Those two are not free**, because the same
source computes a different answer depending on the flag. They are behind a flag
precisely because the choice is real.

**The operational rule:** *being lax is free when it strictly enlarges the set of
accepted programs. It stops being free the moment it changes what an
already-accepted program MEANS.* At that point CLAUDE.md's escape rule applies —
a divergence producing a **silently wrong value** is promoted to an ordinary
`bug-` ticket in the owning lane, not filed as a dialect choice or a `compat`
item. Being our own dialect licenses different semantics *chosen on purpose*; it
never licenses a wrong answer nobody chose.

And note laxness is not uniform even in Pascal: `{$DECLORDER}` defaults **ON**
(declare-before-use is enforced), with `--lax-decl-order` as the opt-out. The
default is chosen per feature on whether the restriction earns its keep, not by a
blanket preference for permissiveness.

**Where an implementation's own idiosyncrasies live:** behind `--strict-<impl>`,
opt-in, never the default — `--strict-fpc` / `--mimic-fpc` and `--strict-python`
ship today. There is deliberately **no `--strict-gcc`**: being bug-compatible with
a particular C implementation is not something anyone has asked for, and the
standard is the authority anyway.

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

---

## REFINEMENT (owner, 2026-08-27) — the reference is the SPEC; an implementation's habits go behind `--strict-<impl>`

> *"as far as divergence goes — we have `--strict-` in place. like `--strict-fpc`
> and `--strict gcc`. apart that we rather work for specs (what does formal
> pascal/c/python spec say) as compliance…. python the sortof exception since
> cpython is the de-facto oracle. but since we are a static compiler, not all
> wishes can be granted… that's the nature of pxx."*

This sharpens the three positions above rather than replacing them, and it fixes
a conflation the C section makes. **Two different things had been collapsed into
the word "oracle":**

| | the reference we comply with | how to get an implementation's behaviour |
| --- | --- | --- |
| **C** | the **formal C standard** | *(no flag exists — see the gap below)* |
| **Pascal** | the **formal Pascal spec**, plus our deliberate dialect | `--strict-fpc`, `--mimic-fpc` |
| **NilPy** | **CPython, de facto** — the acknowledged exception | `--strict-python` |

**The default target is the SPEC. A reference implementation's
idiosyncrasies are opt-in, behind a flag, not baked into the default.** That is
what the `--strict-*` family is *for*, and it is why the family is named after
implementations (`fpc`, `python`) rather than after behaviours.

**Python is explicitly the exception**, and for a stated reason rather than by
oversight: CPython is the de-facto oracle because that is what the ecosystem
actually targets. The upward-compatibility rule above is unchanged.

**And the bound that applies to all three:** *"since we are a static compiler,
not all wishes can be granted — that's the nature of pxx."* This is the
**permanent limit** category above, generalised past NilPy. It is not an excuse
available on demand — the bar in the NilPy section still binds (show the
workaround space is genuinely empty, and a permanent-limit claim is a Track U
escalation, not a worker's call) — but it is now explicitly a property of the
project, not a NilPy-specific apology.

### Where this CHANGES the C section above, and the gap it exposes

The C section says *"gcc / ISO C is the oracle"* and *"a difference from gcc is a
**bug**, full stop."* Under the refinement those are two different claims and only
the second half of the first one survives: **a difference from the C standard is
a bug; a difference from gcc is not automatically anything.**

**But that is a distinction without a conflict, and the ticket filed to resolve
it was rejected the same day** ([[decide-c-frontend-iso-c-or-gnu-c-by-default]],
`rejected/`). Two things settle it:

**The standard is the AUTHORITY; gcc is the INSTRUMENT.** Owner, 2026-08-27:
*"C is well defined by formal standards. it may be that gcc is wrong, unlikely
but.. so gcc is an oracle. we use it as. but. it has not been an issue so far
since C is well defined."* If they ever disagree the standard wins — and they
never have, which is why `tools/gcc_diff_probe.sh` settles arguments without
anyone adjudicating.

**Accepting a SUPERSET of the standard is not a divergence from it.** This was the
framing error worth recording, because the project already states the same rule
twice: Pascal — *"we accept a form FPC rejects → not a defect"*; NilPy —
*"accepting something CPython rejects is a feature, not a defect."* C is the same
shape. Accepting `__attribute__` takes nothing away from a program that does not
use it.

Measured, not assumed: `__attribute__`, `__extension__`, `__builtin_*`, statement
expressions, `__asm__` and `__inline` are **already handled** in
`clexer.inc`/`cparser.inc`/`cpreproc.inc`. **GNU-by-default is the shipped status
quo**, and real-world C keeps compiling unmodified. No `--strict-gcc` is needed:
being bug-compatible with a particular implementation is not something anyone has
asked for. A `--strict-c` that *rejected* extensions would be an ordinary feature
request, and no program needs it today.

So the C section above stands exactly as written, with one word sharpened: **the
formal C standard** is the oracle, and gcc is how we consult it.
