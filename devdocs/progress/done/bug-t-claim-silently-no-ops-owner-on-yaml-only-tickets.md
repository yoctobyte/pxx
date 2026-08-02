---
track: T
prio: 45
type: bug
owner: claude@xeon
status: done
---

# `progress.sh claim`/`resolve` silently no-op Owner/Status on YAML-only tickets

Found 2026-08-01: `tools/progress.sh check` flagged two tickets I'd claimed
earlier in the session (`feature-a-typeref-migrate-consumers`,
`feature-nilpy-cpyext-c-api-from-source`) as `NO-OWNER`, despite `claim`
having printed `claimed ... -> working/ (owner: claude-A)` for both.

## Cause

`set_field()` (`tools/progress.py`) only replaces an existing markdown bullet
line matching `- **<marker>:** ...`:

```python
def set_field(path, marker, value):
    text = path.read_text(...)
    pat = re.compile(rf"^(\s*-?\s*\*\*{re.escape(marker)}:\*\*\s*).*$", re.I | re.M)
    text = pat.sub(rf"\g<1>{value}", text, count=1)
    path.write_text(text, ...)
```

If the ticket has no such bullet — e.g. a ticket with only plain YAML
frontmatter (`track:`/`prio:`/`type:`, no `- **Owner:**` line) — `pat.sub`
matches nothing and the file is written back unchanged. `cmd_claim` doesn't
check whether the substitution actually did anything, so it prints success
regardless.

`Ticket.owner` (the reader) checks both forms — YAML `owner:` key first, then
falls back to the bullet — so newer YAML-only tickets are a real, silent
write gap on the `claim`/`resolve` write path, not just a display quirk.

## Fix direction

`set_field` should write into YAML frontmatter when no bullet exists to
replace, matching what `set_prio_auto` already does (insert into the
frontmatter block, or create one). Same bug likely affects `cmd_resolve`'s
`Status`/other field writes on YAML-only tickets — check that path too.

## Workaround used

Manually added `owner: <id>` to both affected tickets' frontmatter.

## Log
- 2026-08-02 — resolved, commit 03b90a755.
