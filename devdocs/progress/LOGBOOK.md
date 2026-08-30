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
- 2026-08-30 | frankC | devdocs/dev/differential-probes.md | added the BEFORE/AFTER probe class (two commits, one tree): build both arms from source or the finding has no sign, and a subject list is a table with cells you have not filled. Both measured verifying the C calling convention; the empty cell was a real regression two independent verifications missed.
- 2026-08-30 | frankS | compiler/defs.inc | AN_INDEX/AN_FIELD said "Left = base sym idx"; it is a NODE. Swept all 196 builders of AN_INDEX (52) / AN_FIELD (88) / AN_DEREF (56) in compiler/*.inc: every one assigns a node (node, idn, tmpN, CloneAST(...), *MakeIdent(sym) -- the MakeIdent helpers exist precisely to wrap a symbol in a node). ir.inc:1544 and ResolveNodeRec read it as a node and are right. Corroborated independently by frankwasm from its wide-char arms. The comment nearly bought a symbol-walk fix that would have mis-typed destinations and rejected working code.
- 2026-08-30 | frank-optimize | compiler/builtin/promocore.pas | retired the "keep every hot routine free of TBig" rule at :796 -- it was a workaround for a codegen defect fixed in d27b4a28a. Re-measured by un-splitting PXXPromoCmp: the unsplit form costs 2 rep-stosb and 282 instructions binary-wide (was: 21 managed temps zeroed + 30 finalize calls per prologue). Comment only; splits kept as harmless, and the "do not hand-split new routines" guidance is now explicit so the retired rule stops shaping new code.
