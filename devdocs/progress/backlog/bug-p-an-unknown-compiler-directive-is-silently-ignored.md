---
slug: bug-p-an-unknown-compiler-directive-is-silently-ignored
title: "The directive dispatch has 34 arms and no unknown-directive diagnostic"
track: P
prio: 35
type: bug
blocked-by: []
status: backlog
owner: unassigned
created: 2026-08-28
summary: "compiler/lexer.inc's {$...} handler is an if/else chain of 34 CaseEqual(command, ...) arms with no terminal else, so ANY directive outside those 34 is silently ignored — no warning, no note, exit 0. {$FATAL} is one confirmed instance (bug-p-fatal-directive-is-silently-ignored) and the mechanism guarantees there are others. Filed separately from the {$FATAL} ticket on purpose: fixing {$FATAL} closes that ticket and leaves this generator intact."
---

# The mechanism, not the instance

Filed by frank-coordinator from a follow-up frankB flagged while filing
`bug-p-fatal-directive-is-silently-ignored`. **Separated deliberately** — CLAUDE.md's
`normalise-dont-special-case` rule says to grep for the sibling before closing a
double case, and here the sibling is *unbounded*: fixing `{$FATAL}` closes that
ticket and leaves the mechanism that produced it untouched.

**Measured, 2026-08-28:**

```
grep -c "else if CaseEqual(command" compiler/lexer.inc   ->  34
```

Thirty-four arms (`warning`, `message`, `error`, `mode`, …) and **no terminal
`else` that diagnoses an unrecognised directive.** A directive outside the set is
consumed and discarded: no warning, no note, exit 0.

## Why this is a bug and not a diagnostic-parity nit

Same reasoning frankB used for `{$FATAL}`, and it generalises: **a directive's
purpose is to change what the compiler DOES.** Ignoring one does not change a
message — it changes the artifact, or whether an artifact exists at all. A source
that says *"this configuration is unsupported, do not build"*, or that sets a range
check, an alignment, a calling convention, gets silently built the other way.

That is the silent-wrong-behaviour escape in CLAUDE.md's compat table, not the
deferrable "our diagnostic differs" row.

## What the sweep is

1. Enumerate the directives FPC/Delphi accept that real Pascal in our corpora
   actually uses, and diff against the 34.
2. **Do not trust a single extraction of either side** — the census that found this
   class in `lib/crtl` was written twice and each implementation silently dropped a
   different name (`atexit` to a `(*` filter; `longjmp` to `sort -u` under a UTF-8
   locale). Manufacture a disagreement.
3. Add the terminal `else`. **Its shape is the real decision:** a hard error breaks
   every source using a directive we do not implement but could safely ignore
   (`{$IFOPT}`, vendor-specific pragmas); silence is the current bug. A warning that
   names the directive is the likely answer, with a small allow-list of
   known-inert ones so the warning stays meaningful.

## Related

- `bug-p-fatal-directive-is-silently-ignored` [P, p35] — the confirmed instance.
  Note its own trap: `fatal` must join the `messageText` capture at
  `lexer.inc:1697` or the diagnostic comes out empty.
- Do not close this when that one closes. **This ticket is the generator; that one
  is one of its outputs.**
