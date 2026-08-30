# LOGBOOK — trivial fixes made without a ticket

One line per fix that was small enough to just do. **This is not a ticket file**:
no frontmatter, no slugs, no `board-md`, nothing to resolve, nothing to link.

The rule that authorises these, including the boundary and the comment-vs-code
trap that makes it dangerous, is **"Just fix it — the trivial-fix rule" in
`CLAUDE.md`**. Read it before adding your first line. Short version: if it cannot
change behaviour and you can verify it by reading, fix it and log it here instead
of filing.

**Format** — `date | agent | file | what and WHY`:

```
- 2026-08-30 | frankA | compiler/foo.inc | dropped the NOTE about bar; the sibling it cites was corrected on 08-29, so the clause was false
```

The **why** is the part worth writing. "fixed comment" tells the next reader
nothing and defeats the point of keeping this file.

**Conventions**

- Append at the **end**. On a rebase conflict keep both lines — never drop one.
- Batch freely: ten comment fixes in a sweep is one commit and ten lines here.
- This file's job is the one thing `git log` cannot give you cheaply — the
  isolated record of **what bypassed the ticket system**, so the practice stays
  auditable. If it ever fills with entries that plainly needed tickets, the rule
  is being over-read and should be tightened.

---

- 2026-08-30 | claude-A | compiler/builtin/builtinheap.pas | dropped the trailing NOTE in `PXXSysLseek`'s rv32 comment — it claimed the sibling comment in `lib/rtl/platform/posix/platform_backend.pas` "still says the plain form is tolerated by qemu-user", but that sibling was corrected on 2026-08-30 (it now carries the falsifying strace itself) and the ticket it cited is closed. Checked the code first, per the comment-vs-code rule: the code is right, only the prose was stale. Retires `chore-a-trim-the-stale-cross-reference-in-pxxsyslseek-s-rv32-comment` — 56 lines of ticket for a 5-line deletion, and the first entry here is the one that motivated the rule.
