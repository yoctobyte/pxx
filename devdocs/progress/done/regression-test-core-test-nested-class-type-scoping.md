---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_nested_class_type_scoping.pas /tmp/test_nested_cls_type26`, which names `test/test_nested_class_type_scoping.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nested_class_type_scoping.pas at d81b90a991e9 in step 1/2, `./compiler/pascal26 test/test_nested_class_type_scoping.pas /tmp/test_nested_cls_type26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5666dc9dba23`).
  Untriaged.
- **Found:** 2026-09-08T07:02:22Z
- **Test source:** test/test_nested_class_type_scoping.pas tools/expect_same.sh
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_nested_class_type_scoping.pas`.
  ```
  ./compiler/pascal26 test/test_nested_class_type_scoping.pas /tmp/test_nested_cls_type26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nested_class_type_scoping.pas'` at d81b90a991e9eb2266c31c9d2f3889173c7ab8df

## Range
bad `d81b90a991e9`, last good `baad7e842cd8`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:104: error: "w": no such member on this record/class
pascal26:104: error: "v": no such member on this record/class
pascal26:105: error: "w": no such member on this record/class
pascal26:106: error: "v": no such member on this record/class
(tail)
pascal26:104: error: "w": no such member on this record/class
  near: tinner . Create ; b . >>> w := 22 
pascal26:104: error: "v": no such member on this record/class
  near: w := 22 ; b . >>> v := 33 
pascal26:105: error: "w": no such member on this record/class
  near: Chk ( 'other-field-w' , b . >>> w , 22 
pascal26:106: error: "v": no such member on this record/class
  near: Chk ( 'other-field-v' , b . >>> v , 33 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*


## Verified dead at HEAD (2026-09-08, frankS)

Cause and fix, so the range does not have to be re-derived: `d81b90a99` put an
`EatQualifiedTypePrefix` ahead of five `FindArrayType(CurTok.SVal)` probes, which
for a qualified spelling read the OWNER token. **`ParseTypeKindInner` carries its
own copy of that strip, and that copy does one thing the shared helper does not:
when the member is a nested CLASS or RECORD it REWRITES the name to the
registered row.** Stripping ahead of it consumed the qualifier that arm reads,
the arm never fired, and the bare name bound to whichever class registered
first -- which is exactly the defect this test was written for, reintroduced
through a different door.

`5ea212e36` adds `EatQualifiedArrayTypePrefix`: it decides from the token stream
WITHOUT consuming and delegates only when the member names a row in `ArrType*`.
Not a narrowing for safety -- `FindNestedType` answers -1 for an array member, so
`ParseTypeKindInner` would strip and rewrite nothing there. Same
`QualTypeOwnerCi`, same final token. The guard is "strip exactly where the two
copies agree".

**Before and after both measured in this checkout.** At `d81b90a99` my own full
tier died on this source with four rows -- `"w": no such member on this
record/class` and the same for `"v"`, at lines 104-106. At `5ea212e36`,
compiler `29e343715a4a`: `total ok 9 / 9`, zero FAIL rows.

`test/test_a_qualified_nested_array_type_in_a_declaration.pas` now carries the
guard's own positive control -- two owner classes each declaring a nested class
named `TIn`, with the fields proving which row was picked -- so the next person
to widen the strip fails on the row that names the reason rather than here.

## Log
- 2026-09-08 — auto-closed by the seven watcher: `test-core#src:test/test_nested_class_type_scoping.pas` passes at 76b75db6a7b7 (tier native); it was red at d81b90a991e9. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
- 2026-09-08 — frankS: the analysis above was appended here and the duplicate stub in `backlog/` (left behind when the watcher filed its close into `done/` without removing it) was deleted, so one slug names one file.
