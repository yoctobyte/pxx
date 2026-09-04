---
track: T
prio: 50
type: bug
status: backlog
found: 2026-09-04
found-by: frankA (hit it); shape identified by frankuser
owner: ""
blocked-by: []
summary: "MEASURED 2026-09-04. `.claude/hooks/no-full-suite.sh` deliberately exempts a commit message that QUOTES a forbidden command -- its own comment says an un-exempted one was `silently deleting the message span` -- but the exemption is keyed on the command's FIRST WORD being `git`, and `git` is the only first word that survives a chain. Nobody writes a multi-paragraph commit message as `git commit -m`: the repo's own practice is to write it to a file with a quoted heredoc (CLAUDE.md requires the quoting) and then `git commit -F`. That command's first word is `cat`, or `cd`, and the heredoc BODY is what the hook scans. So the exempted shape is the one nobody uses and the used shape is unexempted. Cost here: a commit refused because its message explained that a census `used to run only in the test-core target`. The refusal is visible and reword-able; the failure mode the hook's own comment names -- a silently truncated message -- is not."
---

# The exemption covers `git commit -m`, and nobody writes a message that way

## Measured, not inferred

The refused command was, in one Bash call:

```
cd <repo>; ... ; cat > $S/msg.txt <<'EOF' ... EOF ; git commit -F $S/msg.txt && tools/sync.sh
```

`first` resolves to `cd`. The chain rule (`case "$cmd" in *"&&"*|*"||"*|*";"*)
[ "$first" = git ] || first='' ;;`) then blanks it, and the scan matches the
forbidden phrase inside the HEREDOC BODY. `git commit -F <file>` on its own
contains no forbidden text at all -- the string is in the file, and the hook
never reads the file. **It is the `cat` that gets refused, not the commit.**

## Why the existing exemption does not reach it

Lines 31-37 already know about this class:

> a commit message that quotes a forbidden command all tripped the refusal --
> the last one **silently deleting the message span**

and the `git` first-word exemption is kept alive through a chain on purpose,
with the reason given: *"a commit MESSAGE routinely contains both a semicolon
and a quoted command"*. That is exactly right and it stops one step short: the
message is not usually IN the git command. CLAUDE.md tells everyone to put it in
a file with a **quoted** heredoc, because an unquoted one substitutes backticks
and `$(...)`. So the documented, required practice produces the unexempted shape.

## Severity is about the OTHER failure mode

A visible refusal is cheap -- reword and move on, which is what happened here.
The hook's own comment names the expensive one: **silently deleting the message
span**. If any path still truncates rather than refuses, a commit lands with a
hole in its message and nothing says so, and this repo's commit messages are
where the reasoning lives.

**Not established:** whether the truncating path is still reachable, or whether
it was fully replaced by the refusal. Whoever takes this should find out first;
it decides whether this is a papercut or a data-loss bug.

## Candidate fixes, none chosen

1. **Do not scan heredoc bodies.** A `<<'DELIM' ... DELIM` body is data being
   written to a file, not a command. This is the narrowest change and it matches
   the hook's own principle that reading about a rule is not running it.
2. **Exempt a redirect-to-file whose target is not executable**, i.e. treat
   `cat > f` like the read-only tools it already exempts.
3. **Keep the first-word exemption alive through a chain for the read-only
   list**, not only for `git`. Weakest option: it re-opens the
   `echo 'make -n' && <suite>` hole the chain rule was added to close, which is
   documented directly above it.

Whichever is taken needs the positive control the hook already has a harness for
(`tools/test_no_full_suite_hook.sh`): a case that must still be REFUSED --
`echo hi && <a real suite invocation>` -- asserted in the same commit as the new
exemption. A widened exemption without that is how the hole comes back.

## Borders Track U

If the answer is "the hook should not inspect message text at all", that is a
design call rather than a fix, and it belongs in `backlog-decide`.

## Two probes, one axis, measured 2026-09-04

Not read off the comments. Identical heredoc content containing the forbidden
literal, written to a scratch path, differing ONLY in whether the Bash call is a
chain:

```
# ALLOWED
cat > /tmp/.../hooktest_a.txt <<'EOF'
This file quotes a forbidden phrase: <the literal>
EOF

# REFUSED
cd <repo>; cat > /tmp/.../hooktest_b.txt <<'EOF'
Same content, but this Bash call is a chain: <the literal>
EOF
```

The first passes because `first` is `cat`, which is on the read-only list. The
second is refused because the leading `cd <repo>;` makes it a chain, and the
chain rule blanks `first` for every word except `git`.

**That is the whole bug in two lines.** Nothing about the content changed. And a
leading `cd` into the repo is how essentially every Bash call in this fleet
starts, so in practice the read-only exemption is unreachable and only `git`'s
survives — while the message text lives in the `cat`, not in the `git`.

The first probe is also the positive control for the second: without it,
"refused" would not have been attributable to the chain at all, since a probe
that never contained the literal would pass for a reason that has nothing to do
with the rule.
