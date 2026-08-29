# Rust frontend: where the frontend deliberately differs from rustc

Divergences that are **chosen**, not bugs. Each one here has been considered
and left as it is on purpose. Anything not in this file that differs from
rustc is a bug — file it.

The rule this list is written against, borrowed from
`nilpy-semantics-divergences.md` because it is the same rule with a different
reference implementation: **a program rustc accepts and runs must behave the
same under pxx.** An entry belongs here only when it differs for programs
rustc itself rejects, or in a way no accepting program can observe.

CLAUDE.md's compat table is what routes an item here rather than into the
backlog:

> **an observable that no compiling program can reach → never** — close it
> `rejected/`, cite this row.

This file is where those get written down instead of vanishing. Note the
inverse is NOT here: *"real Rust source compiles wrong, or not at all"* is a
**bug** in Track R's lane, and *"rustc accepts a form we reject"* is ordinary
unimplemented work — the ladder in `feature-rust-corpus-chess` is full of it.

Track R is X-tagged (experimental, unranked), so this file is short by
construction: most of what differs today is simply **not implemented yet**,
which is a gap and not a divergence. Only deliberate, permanent-until-revisited
choices go here.

---

## A top-level `const NAME: [T; N] = [...]` is a global filled at startup

*Decided 2026-08-29, rung 10. Routed here rather than to a `decide-*` by
CLAUDE.md's "an observable that no compiling program can reach" row, since the
written rule already answers it.*

Rust's `const` is a compile-time value; rustc materialises it wherever it is
used, and an array const would live in read-only data. The Rust frontend
instead allocates a **BSS global** and emits the element stores at the top of
`main`, before any user statement runs (`RRegisterTopConsts` / `RConstInitSeq`
in `compiler/rparser.inc`).

Every observable an accepting program has is the same: the values are the
values, the address is stable across reads, and any function can read it —
including a function textually *above* the const, which is why registration is
a prescan rather than part of the top-level walk.

What differs is a write that no accepting program performs. `DELTAS[0] = 9;`
is rejected by rustc (`cannot assign to this expression`), so no program that
compiles under rustc can reach the difference. This frontend does not reject
it, and today such a write would stick.

**The line where this flips into a bug:** if a program could write through such
a name *and rustc would have accepted the program*, that is a different defect
in a different direction and belongs in the backlog, not here. It is also the
reason this entry is worth writing down rather than assuming: the deviation is
safe because of what rustc **refuses**, not because of what we do.

Building real `.rodata` initializers is shared-codegen work (Track A) and would
buy the corpus engine nothing observable, which is the whole argument for not
doing it.

## `println!` evaluates its arguments interleaved with the format text

*Noticed 2026-08-29, rung 6. Re-checked rung 13, when `println!` was next
touched — still true, and now true for a second reason.*

Rust evaluates all of a `println!`'s arguments, in order, before any output is
produced. This frontend lowers the macro to a sequence of writes, so a
side-effecting argument runs at the point its placeholder is reached rather
than before the first literal segment.

Rung 13 made the sequence *longer* — a bool argument now splits the write in
two so it can be spelled `true`/`false` — which widens the window without
changing the order. The fix is the same one it always was and is still not
done: evaluate every argument into a temp first, then write. That costs a temp
per argument for a case no test in the corpus reaches, which is the whole
argument for leaving it.

Only reachable with a side-effecting argument. Every Rust test in this repo
that would have tripped over it hoists the call into a `let` instead.

## A type alias with a multi-token target is dropped, not aliased

*Rung 10.*

`pub type Bitboard = u64;` aliases. `type Row = [u8; 8];` and
`type Maybe = Option<Square>;` are still dropped whole, so a use of the alias
errors with `unknown type`.

This is a **gap, not a divergence** — it is listed here only so the narrowing
is written down somewhere a reader will find it, since the single-token
restriction is invisible from the outside until a program hits it. Widening it
is ordinary Track R work; nothing about it is a decision.

## `String` and `&str` are one type: the managed AnsiString

*Decided 2026-08-29, rung 14.*

Rust has two string types and the difference between them is ownership:
`String` owns a heap buffer, `&str` borrows a view of one. This frontend maps
both to pxx's managed, refcounted AnsiString, and every operation -- `+`,
`==`, `len()`, assignment, passing, returning -- is the shared lowering's
already-gated ARC path.

**Why no accepting program can observe it.** The two types differ in exactly
one place: what happens when a buffer is mutated while another name refers to
it. Rust's borrow checker exists to make that unrepresentable -- you cannot
hold a `&str` into a `String` and push to the `String`. So a program rustc
accepts never performs the observation, and one that attempts it does not
compile there in the first place.

That is a stronger argument than the const-array entry's and worth stating
plainly: this is not "unlikely to matter", it is "the reference implementation
statically forbids the only experiment that could tell". Carrying a second
representation would cost the whole borrow-tracking machinery this frontend
does not have and answer no question any compiling program can ask.

**What follows from it, and is therefore also deliberate:** `s.as_str()`,
`.to_owned()`, `.clone()` and `.into()` on a string are all identity. They
exist in Rust to move between representations and there is only one. They are
accepted rather than rejected because real source is full of them.

**What we accept that rustc rejects** (the "not a defect" row of CLAUDE.md's
compat table): `a + b` where rustc demands `a + &b`, and comparing a `String`
to a `&str` without a borrow. Same call NilPy makes for CPython.

**The line where this flips into a bug:** if a program could observe a *value*
difference -- a mutation visible through a name Rust would have kept
independent, or the reverse -- that is an ordinary Track R bug in the
backlog, not this entry. The divergence is safe because of what rustc
**refuses**, not because of what we do.

## `format!` and `println!` do not share a lowering

*Rung 14. Noted because the duplication is deliberate and looks like an
oversight.*

Both scan `{}` placeholders out of a format literal. `println!` lowers to a
SEQUENCE OF WRITES (and splits again at a bool, so it can spell `true` rather
than Pascal's `TRUE`); `format!` builds a concatenated VALUE. Sharing the scan
would mean handing back an ordered item list that neither caller wants in that
form, to couple an output path to an expression path. Twenty lines of brace
scanning is the cheaper half.

One consequence is visible: `println!` renders a float and `format!` refuses
one, because the write path has a float renderer and the value path would need
StrFloat and a decision about digits -- which is Track F's question, and low
prio by that letter's charter.
