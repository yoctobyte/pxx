#!/usr/bin/env python3
"""A FIXED synthetic ticket corpus for `progress_near_devtest.py`.

WHY THIS FILE EXISTS. The two calibration properties in that devtest — a slug
reaches its own ticket, and a short unrelated query does not saturate against
the longest document — are properties of the METRIC. They were measured on the
live board, and a metric property measured on a moving population is not
reproducible: the same named check printed 0.098 and then 0.089 hours apart
with the metric untouched, and on 2026-09-06 the worst probe changed identity
outright (`feature-dynamic-compiler-tables` 0.089 -> `feature-pascal-corpus-
expansion` 0.076) because tickets were filed and closed in between. IDF is
computed over the corpus, so EVERY score moves when ANY ticket moves.

That check also had both failure directions. Its probe slice was the first 25
open tickets in board order — 4% of the board — so it reds when a long summary
happens to land inside the slice and goes GREEN, with the identical condition
present, the moment that ticket drifts out of it. A guard whose population is
chosen by board order is sampling, not measuring.

The two rejected alternatives and why they are worse are recorded in
`bug-t-progress-near-devtest-measures-a-ticket-summary-length-so-the-board-
turns-the-tool-devtest-red`: raising the floor erases the finding and fixes
neither direction, and normalising the score by document length changes what
`near` ranks — a behaviour change to a tool people use, decided by a devtest.

WHAT MAKES THIS CORPUS VALID, and it is the only thing that does: the two
REJECTED metrics must still fail against it. Jaccard must still collapse on a
short query, and containment must still saturate against the long document. If
a corpus is written so tidily that the wrong metrics pass, it has stopped being
a control and become decoration. The devtest asserts both, against this corpus,
in the same run — so the corpus cannot silently rot into agreement.

Which is why the heads here carry REALISTIC SUMMARIES rather than one-liners.
`_ticket_head` is slug + title + summary, and Jaccard's documented failure is
that the union becomes "the whole ticket" and a short query rounds away. A
corpus of terse heads scores 0.364 under Jaccard — the control passes and the
guard above it stops guarding. Length here is load-bearing, not padding.

Nothing in this file reads the repo. Add a document when a metric property
needs a shape the corpus lacks; do not edit one to move a number.
"""

# slug -> (title, summary, body)
#
# head = slug words + title + summary   (what `near` compares a filer's title to)
# full = head + body                    (what `dupes` compares between tickets)
DOCS: dict[str, tuple[str, str, str]] = {
    "bug-a-variant-shift-is-arithmetic-where-the-static-shift-is-logical": (
        "a variant shr is arithmetic where the static shr is logical",
        "Shifting a negative value held in a variant sign-extends before the shift, so the "
        "vacated high bits come back set, while the same expression written against a "
        "statically typed operand of the same width fills them with zero. Both readings are "
        "defensible and the two paths disagree, which is the defect: one program, two "
        "answers, decided by whether a temporary happened to be boxed. The variant path "
        "goes through a helper and the static path lowers to an instruction, so nothing in "
        "the shared lowering sees the divergence and no test that stays on one side of it "
        "can fail. The measurement that settles it stores the result in its declared type and "
        "compares that; every divergence visible only in an intermediate is latitude.",
        "Reproduced on x86-64 and i386. The helper takes the operand as a signed 64-bit "
        "value regardless of the declared width and the widening is where the sign arrives.",
    ),
    "bug-a-an-open-array-parameter-records-a-placeholder-length": (
        "AllocParam stamps a placeholder length on every open array parameter",
        "Allocation writes a fixed sentinel length into every array parameter as the "
        "open-array placeholder, unconditionally, so a parameter's recorded length is "
        "untrustworthy in both directions: a genuinely fixed-length parameter reads back as "
        "the sentinel, and a parameter that really is open is indistinguishable from one "
        "whose length was never recorded. Anything that branches on the recorded length is "
        "therefore reading a constant. Two separate checks were written against it before "
        "anyone noticed, and both were correct about the sentinel and wrong about the "
        "parameter.",
        "The sentinel is written at allocation and never revised, including for parameters "
        "whose length is known at the declaration.",
    ),
    "feature-c-cache-the-include-guard-so-a-repeated-header-is-skipped": (
        "cache the include guard so a repeated header is skipped",
        "A large translation unit reaches the same header dozens of times and the "
        "preprocessor re-tokenises it in full on every visit, because the guard macro is "
        "only observed after the file has been opened and scanned. Recording the guard "
        "identifier on first read lets a later visit stop at the open. The measurement that "
        "prompted this is a profile in which header re-scanning dominates every other "
        "preprocessor cost on real sources, and the fix does not change any observable "
        "behaviour, only the time.",
        "Guard detection must handle the trailing-comment and the pragma-once spellings, "
        "and must refuse to cache a header whose guard is conditional on something else.",
    ),
    "bug-n-a-nilpy-generator-loses-its-frame-across-a-yield": (
        "a nilpy generator loses its frame across a yield",
        "The generator's locals live in the caller's stack frame, so the first resume after "
        "a yield reads slots that the intervening call has already reused. The values that "
        "come back are plausible rather than obviously wrong, which is why this survived a "
        "green suite: a counter reads as a small integer and a string reads as a valid "
        "string, just not the one that was stored. Every generator that yields more than "
        "once from inside a loop is affected, and the failure depends on what the caller "
        "did in between.",
        "The frame must be heap-allocated and owned by the generator object, released when "
        "the generator is exhausted or collected.",
    ),
    "feature-r-the-own-written-chess-engine-as-the-rust-corpus-target": (
        "the own-written chess engine as the real-world Rust corpus target",
        "The Rust frontend has no real program to compile, only snippets written to "
        "exercise features that were already known to be missing, which means the frontend "
        "is measured against its own author's expectations. A complete chess engine written "
        "in ordinary Rust is a target that nobody tuned to the compiler: it uses traits, "
        "iterators, slices, pattern matching and arithmetic in the proportions a real "
        "program uses them, and every failure it produces names a ticket in the order that "
        "actually matters rather than the order someone guessed.",
        "Grow the umbrella by attempting the target, never by triaging the backlog.",
    ),
    "bug-z-a-zig-comptime-block-is-evaluated-twice": (
        "a zig comptime block is evaluated twice",
        "Comptime evaluation happens once during binding, to learn the type, and again "
        "during lowering, to produce the value. A pure block gives the same answer both "
        "times and nothing is observable; a block that increments a comptime counter or "
        "appends to a comptime list gives a different answer, and the program compiles to "
        "something the source does not describe. The two calls are in different files and "
        "neither knows about the other, so the duplication is invisible from either side.",
        "Cache the evaluation on the node so the second request reads the first result.",
    ),
    "bug-t-the-per-job-scratch-directory-hides-a-binary-name-collision": (
        "the per-job scratch directory hides a binary name collision",
        "Two Makefile rows compile different sources to the same output binary name. Under "
        "the test manager each job runs in its own scratch directory, so the two never meet "
        "and the collision is invisible; under a plain build they share a directory and the "
        "second compile overwrites the first. The harness that runs these rows most often "
        "is therefore the one that structurally cannot see the defect, and the build "
        "everyone actually runs is the one that exposes it.",
        "The hazard is latent under a serial build because each row asserts immediately "
        "after its own compile; it becomes real under parallelism or reordering.",
    ),
    "feature-b-the-read-buffer-becomes-a-pointer-matching-the-reference-layout": (
        "the text file read buffer becomes a pointer, byte-identical to the reference",
        "The read buffer is held inline in the file record, so setting a user buffer copies "
        "through an intermediate and the record's layout diverges from the reference "
        "implementation's. Holding a pointer instead removes the copy and makes the record "
        "byte-identical, which matters because real code casts the record and reads fields "
        "by offset. The change is observable only in the layout and the timing, not in any "
        "value a conforming program can read.",
        "The buffer's lifetime becomes the caller's, which is what the reference "
        "implementation already documents.",
    ),
    "bug-a-wasm32-emits-a-separate-function-per-compile-call": (
        "wasm32 emits a separate function per compile call, so a body is lost",
        "The wasm backend emits a function definition each time it is asked to compile a "
        "subtree, rather than accumulating into the function currently open. A procedure "
        "whose body is built in two calls — which is what happens for anything with a "
        "prologue contributed separately — therefore produces two definitions, and only the "
        "last one survives into the module. The lost half is usually the prologue, so the "
        "symptom is a function that runs with uninitialised locals rather than a link "
        "error.",
        "Other backends accumulate, which is why this is a single-target defect.",
    ),
    "feature-p-a-distinct-type-declaration-must-not-alias-its-base": (
        "a distinct type declaration should not alias its base type",
        "A type declared distinct from an existing one currently shares that type's "
        "identity entirely, so assignment between the two is accepted in both directions "
        "and the declaration has no effect other than introducing a second spelling. The "
        "whole purpose of the construct is to make the two incompatible; a program that "
        "uses it to keep two integer quantities apart gets no diagnostic at all when it "
        "mixes them, which is the exact mistake the declaration was written to catch.",
        "Refuse the assignment in both directions; an explicit cast stays legal.",
    ),
    "bug-c-gnu-inline-assembly-is-not-parsed-by-the-c-frontend": (
        "GNU inline assembly is not parsed by the C frontend",
        "Real C sources reach inline assembly through a compiler-version macro, so the "
        "construct is only compiled when the frontend claims a version recent enough to "
        "support it. Verification under an older pinned compiler takes the portable branch "
        "and never reaches the assembly at all, which produces a green that is correct "
        "about a different compiler. Anything guarded by a version or feature-detection "
        "macro has this shape and must be reproduced at head.",
        "The green under the pin is not evidence about the fix; it is evidence about the "
        "pin's age.",
    ),
    "bug-a-a-method-pointer-record-is-hard-sized-on-32-bit-targets": (
        "a method pointer record is hard-sized and is wrong on 32-bit targets",
        "The record that carries a method pointer is given a constant size that is correct "
        "for a 64-bit pointer and wrong everywhere else, so every 32-bit target lays the "
        "two halves out at the wrong offsets. The dev loop, the quick gate and the pin all "
        "run on the 64-bit host, so the entire class of width-dependent defects is "
        "structurally invisible to the instrument that would normally catch it, and the "
        "control test passes on the host while failing two rows on the cross target.",
        "Assert a relation between sizes rather than a per-target constant, so one "
        "assertion carries no expected width and passes everywhere.",
    ),
    "bug-b-shortstring-truncation-at-an-assignment-is-silent": (
        "shortstring truncation is silent at the assignment",
        "Assigning a longer string into a short one drops the tail with no diagnostic at "
        "compile time and no error at run time, so a program that outgrows a declared "
        "length degrades into producing shorter output rather than failing. The truncation "
        "is the documented behaviour of the type and the silence is the defect: the length "
        "is known at the assignment in every case where both sides are statically typed, "
        "and nothing reports it.",
        "A warning at the statically decidable cases costs nothing at run time.",
    ),
    "feature-s-the-embedded-abstraction-layer-refuses-rather-than-answering-wrong": (
        "many platform abstraction entries refuse deliberately instead of guessing",
        "The embedded target is not a Unix: it has tasks rather than processes, no file "
        "system by default, and no fork. Entries that cannot be implemented honestly return "
        "an unsupported error rather than a plausible wrong answer, so code written against "
        "the POSIX shape fails at the call it cannot support instead of silently doing "
        "something else. The refusal is the feature; a stub that returned success would "
        "move the failure somewhere unrelated.",
        "The primary target is xtensa and the 32-bit riscv target works as well.",
    ),
    "bug-d-a-documentation-snippet-does-not-compile-against-the-pinned-compiler": (
        "a documentation snippet does not compile against the pinned compiler",
        "The published snippet uses a construct that landed after the pin, so a reader "
        "following the documentation against the shipped compiler gets an error that the "
        "documentation does not mention. Snippets are supposed to be verified by compiling "
        "them against the pinned compiler rather than against the tree, precisely because "
        "the reader has the pin and not the tree, and this one was verified against the "
        "wrong one.",
        "Compile every snippet against the pin as part of the docs gate.",
    ),
    "feature-o-loop-unrolling-is-a-named-flag-and-not-an-optimisation-level": (
        "loop unrolling is a named flag rather than a rung on the level ladder",
        "The optimisation levels are a ladder of increasing confidence, each level a "
        "superset of the one below and each required to be correct. A transformation that "
        "trades one resource for another — size for speed, compile time for run time — is "
        "not higher on that ladder, it is sideways, and putting it on the ladder forces "
        "every consumer of the level to accept the trade. Named flags keep the ladder "
        "meaning what it says.",
        "The same argument applies to size-optimising and fast-math style flags.",
    ),
    "bug-a-the-constant-cast-width-table-is-the-third-copy-of-one-fact": (
        "the constant cast width table is the third copy of one fact",
        "Three separate tables record how wide each integer type is, and they disagree on "
        "32-bit targets, so a constant expression folds to one value while the identical "
        "runtime cast in the same program produces another. Filed as a refactor on the "
        "grounds that nothing observably differs, which was true on the host it was "
        "measured on and false on three cross targets: a constant that does not fit its own "
        "type, with no diagnostic.",
        "Counting how many mechanisms serve one concept is the cheap way to find these; "
        "two is a smell and three is a design flaw.",
    ),
    "bug-t-a-glob-across-every-folder-counts-closed-tickets-as-open": (
        "a glob across every ticket folder counts closed tickets as open",
        "Counting tickets with a glob that spans every folder includes the terminal ones, "
        "so a claim about how many are open is inflated by however many were closed. The "
        "instrument does not error; it answers a different question, and the answer looks "
        "exactly like the one that was asked for. In the case that prompted this, seven of "
        "the eight tickets named were already closed and exactly one was open, and the "
        "inference drawn on top of the count was correctly hedged, which made the unhedged "
        "number read as the checked part.",
        "Count open tickets by folder, never by a glob across all of them.",
    ),
    "feature-m-console-handle-inheritance-across-a-spawned-process": (
        "console handle inheritance across a spawned process on Windows",
        "A spawned child inherits standard handles only when the creation call is told to "
        "inherit and the handles themselves are marked inheritable, and the current spawn "
        "path does neither. The child therefore writes to a handle that is not connected to "
        "anything, so its output disappears rather than producing an error, and a parent "
        "that reads the child's output waits for a pipe nobody is writing to.",
        "Both halves are required; setting one without the other changes nothing.",
    ),
    "bug-a-an-exception-handler-binder-is-not-recorded-as-a-scope": (
        "an exception handler binder is not recorded as a scope",
        "The variable bound by an exception handler is declared in a scope of its own, and "
        "nothing in the symbol table records that scope, so anything asking whether two "
        "declarations are in the same scope answers wrongly for a handler binder that "
        "shadows an outer variable of the same name. The construct is legal and common, and "
        "a check written on the unfixed answer would have rejected the very fixture written "
        "to prove it legal.",
        "Record the scope base at the binder and restore it when the handler closes.",
    ),
    "bug-c-sizeof-a-pointer-to-array-answers-the-unknown-default": (
        "sizeof a pointer to array answers the unknown-type default",
        "The size query returns the default for an unrecorded type rather than a computed "
        "one, and for the obvious spelling that default happens to equal the right answer, "
        "so the row passes while nothing at all was computed. Only a spelling whose correct "
        "answer differs from the default separates the two, and the example that had been "
        "asserting this property for a day used the colliding spelling.",
        "Ask whether the row would still pass if the machinery did nothing.",
    ),
    "feature-u-the-proof-grade-gate-is-unsatisfiable-on-the-sweeping-host": (
        "the proof-grade gate cannot be satisfied on the host that does the sweeping",
        "Promotion requires a full run with no skipped holes, and the host that runs the "
        "sweeps lacks a hardware instruction that several rows need, so those rows skip "
        "unconditionally and the count is never zero. The gate is therefore unsatisfiable "
        "in principle on the only machine that runs it, which is a different situation from "
        "a gate that is merely failing, and it needs a decision rather than a fix.",
        "A gate that cannot pass is not a gate, in the same way a guard that cannot fail is "
        "not a guard.",
    ),
    "bug-b-open-array-ownership-leaks-half-the-arrays-it-allocates": (
        "open array ownership leaks about half the arrays it allocates",
        "Ownership of a temporary open array is transferred in one path and duplicated in "
        "the other, so roughly half the allocations are never released. A leak does not "
        "corrupt anything, so every value assertion in every affected test still passes and "
        "the suite is green with thousands of arrays outstanding — including a test named "
        "for the leak, which was green throughout. Only an allocation-counting harness "
        "observes it.",
        "Match the assertion class to the defect class; some defects cannot fail a value "
        "check by construction.",
    ),
    "feature-t-a-fixed-corpus-for-metric-properties-rather-than-the-live-board": (
        "metric properties want a fixed corpus, not the live board",
        "A check that asserts a property of a similarity metric while drawing its "
        "population from the live ticket board cannot separate a metric that changed from a "
        "population that moved, and it fails in the direction that reads as tool breakage. "
        "Its numbers drift while its subject is untouched, and its sample is whatever the "
        "board enumerates first, so it can go green with the identical condition still "
        "present. A written corpus fixes both directions at once.",
        "Properties of the board itself legitimately want the board and stay there.",
    ),
}

# The long document. Deliberately long and deliberately BROAD: containment
# saturates against it because a long enough document contains almost any short
# query's words, which is the failure this corpus exists to keep reproducible.
LONG_SLUG = "feature-a-the-intermediate-representation-is-the-substrate-reference"
LONG_TITLE = "the intermediate representation as the substrate for every frontend"
LONG_SUMMARY = (
    "Push generality down into the intermediate representation and keep the frontends "
    "thin, so a fix reaches every language at once. The substrate is the one gate and the "
    "one multiplier in this tree, and a construct reachable through two shapes is "
    "normalised rather than given a second path, because the second path is the one that "
    "stays broken."
)
LONG_BODY = """
The substrate carries the record layout, the array descriptor, the string representation
and the exception frame, so a frontend that adds a language adds a parser and a lexer and
very little else. Every backend reads the same nodes. The 64-bit host backend is the
default and the 32-bit, aarch64, arm32, xtensa, riscv and wasm32 backends are cross
targets that must agree on the observable value even where they legitimately disagree on
the representation. A shift is lowered as arithmetic where the operand is signed and as
logical where it is unsigned, and the distinction is recorded on the node rather than
inferred at emission; a variant operand goes through a helper instead. A compare is the
same story. Static analysis over the nodes is cheap because the nodes are uniform: the
logical structure of a procedure is a tree of statements, the arithmetic structure of an
expression is a tree of operators, and both are the same node array. Parameters carry
their own kind and their own length, and the recorded length of an open array parameter
is a placeholder stamped at allocation rather than a measurement. Strings are reference
counted and the count is manipulated only through helpers the substrate owns. Calls are
lowered after overload resolution, so no backend ever sees a candidate set. Debug
information is attached to nodes and survives every rewrite the optimiser performs, which
is what makes stepping through optimised code possible at all. Generators, exception
handlers and closures each introduce a frame, and a frame that outlives its statement is
heap allocated and owned by the object that resumes it. Where two implementations make
different but equally valid representational choices, introspection that reports each
choice faithfully is doing its job in both, and neither answer is a defect.
"""


def documents() -> tuple[dict[str, str], dict[str, str]]:
    """Return (head_text, full_text) keyed by slug — text, not tokens, so the
    caller tokenises with the same function the tool uses."""
    heads, fulls = {}, {}
    for slug, (title, summary, body) in DOCS.items():
        head = " ".join((slug.replace("-", " "), title, summary))
        heads[slug] = head
        fulls[slug] = head + " " + body
    head = " ".join((LONG_SLUG.replace("-", " "), LONG_TITLE, LONG_SUMMARY))
    heads[LONG_SLUG] = head
    fulls[LONG_SLUG] = head + " " + LONG_BODY
    return heads, fulls
