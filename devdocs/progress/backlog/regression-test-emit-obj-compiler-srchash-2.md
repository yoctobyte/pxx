---
prio: 70
track: A
---

> **Track A from the job NAME `test-emit-obj`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`tools/compiler_srchash.sh`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **The SLUG names `compiler_srchash`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `reloc_resolve_check`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-emit-obj#src:tools/compiler_srchash.sh at 387782d9166f in step 106/589, `PXX=./compiler/pascal26 tools/reloc_resolve_check.py arm32 test/reloc_resolve_probe.c` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1f06bcf02d3f`).
  Untriaged.
- **Found:** 2026-09-22T06:00:01Z
- **Test source:** tools/compiler_srchash.sh compiler/.pascal26.fixedpoint +15
- **Failing step:** line 106 of 589 of the job's recipe; it names `tools/reloc_resolve_check.py test/reloc_resolve_probe.c`.
  ```
  PXX=./compiler/pascal26 tools/reloc_resolve_check.py arm32 test/reloc_resolve_probe.c
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-emit-obj#src:tools/compiler_srchash.sh'` at 387782d9166f1ce648c8ab0860b9bf2b976fab05

## Range
> **The named sha `387782d9166f` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `387782d9166f`, last good `8417dc950266`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
 bytes MISS it (as predicted), witness CATCHES it   [.bss +4]
   applied: type 257 x273, type 258 x1077
   movw type table: assembler AGREES -- abs_g0=263, abs_g0_nc=264, abs_g1=265, abs_g1_nc=266, abs_g2=267, abs_g2_nc=268, abs_g3=269
   movw field oracle: clang AGREES -- G0:0xd2824690vs0xd2824690  G1:0xf2aacf10vs0xf2aacf10  [and clang agrees with EmitExternalCallA64's own hand-written movz/movk words]
   the movz/movk arm is unreached by this probe; running test/reloc_movw_probe.c for it
   movw shape oracle: clang group = 4 entries, types [264, 266, 268, 269], 4-byte step True, one addend True
   movw shape: pxx group = 4 entries, MATCHES clang's invariants (pairwise type 264/266, +4 apart, one symbol, equal slot)
   movw coherence: every group names a real GOT slot {'dlopen': 1, 'dlclose': 1} -- each slot an absolute relocation against an UNDEFINED symbol, which is the invariant the two-relocation design rests on
   movw coherence controls: 2 of 2 rejected (slot off by one; every site one slot)
reloc-resolve[aarch64]: AGREE with pxx's own executable on 772256 bytes, 1355 relocations; 4 of 4 controls reddened it, and every section base has an independent runtime witness
   oracle: the executable, which the aarch64 tier runs under qemu. This does NOT establish that a real linker agrees.
   base .data          0x8114fe0  265 votes, runner-up 0x81192a0 x7  [witness agrees]
       .data is loaded in 2 pieces by this executable, each located by CONTENT: [0x0,0x20) -> 0x81192a0, [0x20,0x32b8) -> 0x8114fe0
   base .bss           0x81192d8  1076 votes (unanimous)  [witness agrees]
   CONTROL addend  +4       -> red (good)
   CONTROL offset  +4       -> red (good)
   CONTROL type    swapped  -> red (good)
   CONTROL uniform shift    -> bytes caught it, witness CATCHES it   [.bss +4]
   applied: type 2 x1349
   arm split addend: WRONG -- clang ACCEPTED an addend the 16-bit signed field cannot hold, so the ceiling this writer is designed around is not where it was measured

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Resolution (frankb-8e, 2026-09-22)

**The failing step is mine and the cause is my CONTROL, not the arm32 writer.**
Re-verified at HEAD first, as the ticket's own third caveat instructs: all five
`reloc_resolve_check` targets are green on this box, before and after the fix.
So this is a **host-dependent** red, which is why it fired on borg and never
here.

`clang_arm_split_addend_oracle()`'s CONTROL 2 asserted that **clang REFUSES**
`movw r0, #:lower16:sym+0x8000` and `+0x10000` — the reasoning being that if
the assembler accepted them, the ARM split field would not be 16-bit signed and
`ObjGotStrOff`'s local-symbol-per-GOT-slot design would be answering a question
that does not exist. The reasoning is sound. **The instrument was not.**

The claim is about **what the ARM split field can HOLD** — a property of the
ARM ELF ABI. What I measured is **whether a particular clang chooses to
diagnose an unrepresentable addend**, which is that tool's error-reporting
policy and varies by version and by host. Ubuntu clang 21.1.8 here refuses
both; borg's clang accepted one. Both assemblers are correct; only my control
was wrong about what it was reading. This is CLAUDE.md's "a control from the
wrong population passes and certifies the broken instrument" with the sign
flipped — it did not certify a broken instrument, it **reddened a working
one**, which costs a tier row and an investigation.

**Fixed by measuring the ceiling on the FIELD.** An addend the field cannot
carry must either be refused by the assembler, *or* be encoded lossily — and
lossily is read back through `_inplace_addend`, the same function the applier
uses. Either outcome settles the ceiling. The only outcome that falsifies the
design is an addend that comes back **intact**, and that is now the one case
that returns WRONG.

**And the accept arm is no longer dead code on hosts where clang refuses.**
`.reloc f, R_ARM_MOVW_ABS_NC, sym+65536` hands the assembler the addend
directly and it takes it — measured here, clang 21.1.8 encodes it and the field
reads back **0**. That reproduces borg's condition locally by a different door,
so the arm that only borg could reach now runs on every host, every time. The
verdict line prints all three outcomes:

```
ceiling: +0x8000 refused, +0x10000 refused, .reloc +0x10000 wrapped to 0
(+0x7fff came back intact, so the predicate can say yes)
```

The parenthetical is the positive control for the accept arm's predicate:
`+0x7fff` is in `ARM_SPLIT_ADDENDS` and the main loop returns False if it does
not come back intact, so "the recovered addend equals the one that went in" is
demonstrably reachable and true. The predicate can say yes, so its saying no is
information.

**Scope of the claim:** five targets re-run green at HEAD
(`x86_64`, `i386`, `riscv32`, `aarch64`, `arm32`), `gate.sh quick` green. I
have NOT reproduced on borg — I cannot reach it — so this is a fix derived from
the log tail's exact message plus a local reproduction of the accepting
behaviour by another route, not from a failing run I watched. What would retire
that caveat: the next full tier on borg passing step 106/589.

**Two of the ticket's own three caveats were right and worth recording as
having paid off.** The slug names `compiler_srchash`, which is not what broke.
The named sha `387782d9166f` cannot be the cause. The third — "re-verify at
HEAD" — was the one that did NOT apply: HEAD was green here all along, and
believing that would have closed this as fixed-by-events. **A green re-verify
on the wrong host is not a re-verify**, which is the same class of error as the
bug itself.
