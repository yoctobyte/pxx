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
