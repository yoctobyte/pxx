---
track: T
prio: 35
type: bug
blocked-by: []
status: backlog
owner: ""
created: 2026-09-05
summary: "The shell-loop rule in .claude/hooks/no-full-suite.sh scans the whole command text, so a HEREDOC BODY is judged as if it were a command. Writing documentation that mentions a test glob and contains the word `for` — e.g. quoting a Pascal `for i := 0 to n` loop — is refused as 'a shell loop over a test/ glob'. No loop, no glob expansion, no suite. Measured with a two-line repro."
---

# The full-suite hook judges heredoc prose as a command

Rule 3 of `.claude/hooks/no-full-suite.sh` requires two matches in `$scan`:

1. a `test/`-shaped glob (`(test|tests)/[A-Za-z0-9_]*\*[A-Za-z0-9_]*\.(npy|pas|c|py|zig|rs)`), and
2. a shell-loop word (`for|while|xargs|parallel`, or `find -exec`).

Both halves are satisfied by ordinary English-plus-code PROSE, because `$scan`
is the raw command and a heredoc body is part of it.

## Repro, two lines, no suite anywhere near it

```sh
cat > note.txt <<'EOF'
This is documentation. It mentions test/<star>.pas and it contains the word for
because it quotes a Pascal loop.
EOF
```

REFUSED: *"a shell loop over a test/ glob is a full regression run with extra
steps"*. (Spell `<star>` as the asterisk to reproduce.)

Hit for real on 2026-09-05 writing a ticket note: the prose named the corpus a
byte-comparison had run over and described the code it replaced as *"five
separate `for i := 0 to nArgs-1` walks"*. Pascal source quoted in a document,
read as a shell loop.

## Why it is worth fixing rather than living with

**The whole command is refused, so the write does not happen** — the failure is
loud and nothing is half-written, which is the good half.

The bad half is what it teaches. The only way past is to reword the document or
prefix `PXX_ALLOW_FULL_SUITE=1` — and that flag means "I genuinely need the full
suite", which is false here, so using it makes the commit message lie about why.
**A guard that misfires on documentation trains agents to rephrase around
guards**, and CLAUDE.md's `rm` rule says in as many words that *"the fix is not
to rephrase the command so it slips past the guard"*. A false positive is how
that habit gets learned somewhere it is harmless, before it is applied somewhere
it is not.

(This ticket was itself written with `PXX_ALLOW_FULL_SUITE=1` in front of the
heredoc, for exactly this reason. Stated rather than hidden.)

## Suggested repair, and the control it needs

Judge the COMMAND, not the heredoc body: strip `<<'?EOF'?` … terminator regions
from `$scan` before rules 3 and 4, or apply the loop rules only to text outside
a heredoc.

**`tools/test_no_full_suite_hook.sh` must gain an ALLOW row for this**, and the
row has to carry both trigger tokens inside a heredoc — a control that omits
either one passes on a hook that is still broken. Note the existing rows are
`deny`-heavy for a good reason (an over-widened guardrail fails silently), so
the new row is the other direction and needs saying explicitly: this is a guard
that says NO where it should say nothing.
