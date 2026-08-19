---
track: A
prio: 30
type: refactor
blocked-by: []
summary: "Omitting rparser.inc breaks zparser.inc in 123 places, plus gparser/eparser/fparser — the greenfield frontends call each other's support functions, which is exactly what the-substrate-is-ast-and-ir-not-the-parser.md says not to do. Costs nothing today; makes R and Z individually unomittable and couples two language specs."
---

# The greenfield frontends share each other's parser helpers

Found 2026-08-19 while measuring
[[feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets]] by omission —
comment out a component's `{$include}` lines, compile, count what breaks.

**Omitting `rlexer.inc` + `rparser.inc` produces 200 errors, and only 7 of them are in shared
files:**

    zparser.inc:123   gparser.inc:23   eparser.inc:23   fparser.inc:19

So this is not Rust coupling to the core — it is **four other frontends calling Rust's
parser support functions**. Every other frontend measured is nearly free to omit (zig 3,
nilpy 7, cfront 11).

## Why it matters beyond the build feature

`devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md` is explicit: share the AST and the
IR, **duplicate the parser, the lexer and their support functions per language** — because a
shared parser helper couples two specs and is wrong in both. That is precisely what this is,
and it grew in the newest, greenfield code rather than in the Pascal-seeded files the document
was written about.

Concretely it means R and Z cannot be omitted independently, and a change to a Rust parsing
helper silently changes Zig's parse.

## Shape of the fix

Duplicate the shared helpers into each frontend that uses them, per the rule — or, where a
helper is genuinely language-neutral (token plumbing rather than grammar), move it to a shared
file so the dependency is on the core rather than on Rust. Classify each of the ~40 distinct
names before moving any: which of them is Rust's grammar and which is plumbing is the actual
question, and the answer is per name.

Track X applies (R and Z are experimental), so this is not urgent — but it is cheap now and
gets more expensive per frontend added.

## Gate

Track A's: `make compiler/pascal26` + `tools/gate.sh quick`; R and Z tests where touched.
