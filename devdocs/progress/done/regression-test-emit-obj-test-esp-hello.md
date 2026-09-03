---
prio: 70
track: A
status: done
---

> **Track A from the job NAME `test-emit-obj`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`test/test_esp_hello.pas`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 13 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-emit-obj#src:test/test_esp_hello.pas@1 at 7fff15ddc1eb in step 27/8, `for t in "--target=riscv32 --platform=esp" "--target=xtensa --platform=esp"; do \ ./compiler/pascal26 --emit-obj $t tes…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-02T18:29:30Z
- **Test source:** test/test_esp_hello.pas test/c_obj_extern_addr.c
- **Failing step:** line 27 of 8 of the job's recipe; it names `test/c_obj_extern_addr.c`.
  ```
  for t in "--target=riscv32 --platform=esp" "--target=xtensa --platform=esp"; do \ ./compiler/pascal26 --emit-obj $t test/c_obj_extern_addr.c /tmp/exa_both.o >/dev/null || { echo "test-emit-obj: [$t] REFUSES the address of an external routine"; exit 1; }; \ ./compiler/pascal26 --emit-obj $t /tmp/exa_
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-emit-obj#src:test/test_esp_hello.pas@1'` at 7fff15ddc1eb1ed9d4247a4aa0a8afa9f12a0203

## Range
> **The named sha `7fff15ddc1eb` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `7fff15ddc1eb`, last good `afbc83e5a976`, 6 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
test-emit-obj: an unmarked ESP program still exports app_main and nothing else
test-emit-obj: [--target=riscv32 --platform=esp] taking an external's address adds 1 relocations, not 2 (call-only 1, both 2)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## RESOLVED (frankB, 2026-09-03) — the EXPECTED count was the defect, not the actual

The row asserted that taking an external routine's address costs **two** more
relocations than calling it. It costs **one**, and one is correct.

`adbe33db8` ("one `IRKindIsStatement` replaces five drifted per-backend
denylists") stopped emitting the address-materialisation node twice. Before it,
riscv32 emitted

```
  b4: auipc a0,0 / j +8 / <literal> / lw a0,8(a0)
  c4: auipc a0,0 / j +8 / <literal> / lw a0,8(a0)     <-- same value, same register
```

back to back, and xtensa carried the same duplicate literal. The expected `+2`
was measured with that duplicate in place, so the row encoded the bug as the
specification and went RED for the improvement that removed it.

**Verified byte for byte, not inferred:** disassembled the object built by the
pinned compiler and by HEAD — HEAD's `.text` is the pin's with exactly that
16-byte sequence deleted and everything after it shifted down by 16. The
external is still named, still relocated, still loaded.

**Comment vs code, decided before touching either:** the FIXTURE's own comment
(`test/c_obj_extern_addr.c`) has said **one** since it was written — *"Every
target must emit one more relocation naming the external for the first than for
the second"*. The Makefile said two. The comment was right and the code had
encoded what the defect produced.

Row corrected to `+1`, with the duplicate-emission history written above it so
nobody re-derives `+2` from an old object. Both targets green; the call-only
positive control (`c >= 1`) is untouched and still fires.
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit e69e71ed2.
