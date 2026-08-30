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

- 2026-08-30 (frankwasm) — `devdocs/dev/debugging-playbook.md`: added the SECOND
  FPC oracle knob for string-width work. The source codepage governs how a
  literal becomes an AnsiString; the **widestring manager** governs how an
  AnsiString converts to a WideString, and stock FPC widens byte-for-byte
  regardless of `{$codepage utf8}` or `-FcUTF8`. `uses cwstring` is the knob.
  Found while answering frankS's question about whether the width conversion was
  reachable at a record-field destination: pxx said 4 units / last=233, FPC said
  5 / 195, and the tempting reading was a divergence. With `cwstring` FPC matches
  pxx on all five positions. The playbook already warned about the first knob,
  which is how the second one got mistaken for it.

2026-08-30 | frank-user | devdocs/progress/working/feature-unicodestring-model.md | Repaired two ghost sha citations: `1557a2d47` -> `d3989b7a3` (6c-params / ProcParamStrElemTk) and `e031655e3` -> `49f1cc801` (7b behind PXX_WIDE_PAYLOAD). Both originals are pre-rebase and on no remote ref; recovered by matching the commit SUBJECT on origin/master, which is why writing a real subject line pays for itself. Confirmed with `git merge-base --is-ancestor`, NOT `git cat-file -e` — the latter answers about the author's own object store, where the pre-rebase object still lives, so it is exactly the check that cannot tell a ghost from a commit. Ticket is live in working/ and untouched apart from the two identifiers; flagged to its owner. `progress.sh check` DANGLING-SHA count 2 -> 0.
2026-08-30 | frankB | devdocs/dev/debugging-playbook.md | added the self-host-catches-a-type-tag row to "the rule this is built on": the causal chain spans a whole compiler generation (tyAnsiString `+` is concat -> round-1 compiler mis-compiles member lookups), which is the clearest case for why make compiler/pascal26 is not skippable. Suggested by frankwasm; incident was mine.
