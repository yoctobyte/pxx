# Archived stable compiler binaries (`stable_linux_amd64/default`)

Mid-dev we keep only the **latest** stable in the working tree (`stable_latest`/`stable_pinned`, fixed-name overwrite). The historical per-version binaries `v1…v36` were removed from the tree but are **not lost** — every blob stays in git history. This manifest makes each one findable + extractable in one line.

## Extract a historical stable

```sh
# by git blob id (fastest; from the table below):
git cat-file blob <blob-id> > /tmp/pxx-vN && chmod +x /tmp/pxx-vN
# or by the commit it lived in:
git show <source-commit>:stable_linux_amd64/default/vN > /tmp/pxx-vN && chmod +x /tmp/pxx-vN
```

Verify with the recorded sha256 (full value is in `history.log`).

| version | date (UTC) | sha256 (12) | source commit (12) | git blob id | subject |
|---------|------------|-------------|--------------------|-------------|---------|
| v1 | 2026-05-25T00:00:00Z | `09a67b12adda` | `113f50df2e23` | `53970e8ebee1a786d8fead2d3f75fcc0ab2d1f27` | initial stabilize baseline |
| v2 | 2026-05-25T18:21:12Z | `09a67b12adda` | `6f82fd2e2e35` | `53970e8ebee1a786d8fead2d3f75fcc0ab2d1f27` | Add stabilize target and stable binary registry |
| v3 | 2026-05-25T18:25:57Z | `09a67b12adda` | `2bca4e82cdb5` | `53970e8ebee1a786d8fead2d3f75fcc0ab2d1f27` | Track versioned stable binaries in git |
| v4 | 2026-05-25T19:23:07Z | `bbe5785af8cf` | `d75a6a423f55` | `0a643e1697636101fd4d2b58a522f7fed227e825` | Stage 2b: wire expression AST building (parallel with direct emit) |
| v5 | 2026-05-28T14:55:07Z | `4ad3a9d46b6e` | `de1bc00ef3c2` | `141db92a8e53187e43bcebe0cca9e358eace7a05` | feat(ir): lower repeat to label jumps |
| v6 | 2026-05-28T15:06:19Z | `c2e1475ddd07` | `de1bc00ef3c2` | `0760f0d3f2663034db7494db18eede1f1e9d85d5` | feat(ir): lower repeat to label jumps |
| v7 | 2026-05-28T18:51:15Z | `cf9f86fffa08` | `479b7e2e443b` | `c5acce67b39e0fbbb1ade42158227e282e04f4f1` | docs: add ordered implementation plan for missing Pascal features |
| v8 | 2026-05-29T05:13:09Z | `8607861ee377` | `0aecd6b5bf46` | `62d7057b18610fb8f1364f122b23e82e5dde1871` | fix(ir): implement IR_VIRTUAL_CALL to fix AN_VIRTUAL_CALL gap in IR backend |
| v9 | 2026-06-19T13:26:16Z | `4e72841a6001` | `d78d198ec886` | `765167b1d2580b6eee2666b774ae612ba8b5139f` | feat(workflow): pinned stable-compiler track for parallel lib/demo work |
| v10 | 2026-06-19T15:50:43Z | `a734a25df5f0` | `8b5364cc1bf7` | `13e15dc267475a539c3dcb6381e17e5215a59fe6` | docs(naming): combined maintainer ranking + Other/write-in path |
| v11 | 2026-06-19T17:27:33Z | `73600eef4ae7` | `a214f60b4ec8` | `ae6eb175a1818cfe913aaad7009dea153f53f5ce` | feat(copy): generic dynamic-array Copy(arr, index[, count]) intrinsic |
| v12 | 2026-06-19T19:25:29Z | `f0b479a7bebe` | `361163ceafb6` | `4e51dd02c37931cb0c0c83f78a002cc3190f1500` | feat(generator): yield a record element from a generator |
| v13 | 2026-06-19T20:19:56Z | `ee8cb8abf6b4` | `6f0865c33af5` | `990a958e2c57f2a2520fec0ddeb735f96adc56a9` | fix(codegen): nil-init hidden aggregate-result record temps (full extent) |
| v14 | 2026-06-20T02:02:32Z | `28453d6ebd82` | `1df5c762957f` | `fcc1fcd1df1e54a6a6afcce0556fb9ca64b6f927` | fix(parser): preserve proc index during managed zeroing |
| v15 | 2026-06-20T06:49:21Z | `4bac688c87a1` | `bb94412fc905` | `02c9e85765ab4c41cfc2ffe25634db24688a4a56` | feat(parser,ir): member access on a function/method call result |
| v16 | 2026-06-20T07:45:26Z | `edb3e3e0baf9` | `517c456e348c` | `40a59399865f4b19f7304ca2385723a78b72ba8a` | docs(ticket): pin a5afebb as the bug-c-quoted-include commit ref |
| v17 | 2026-06-20T08:13:58Z | `7d09790ec6b6` | `6da40d6b5f0b` | `981aece36c42def846302c8facfae79448f2acf2` | feat(compiler): platform + capability define axis (PAL step 1) |
| v18 | 2026-06-20T08:38:52Z | `7d09790ec6b6` | `24c696927afd` | `981aece36c42def846302c8facfae79448f2acf2` | feat(crtl): cover POSIX regex headers |
| v19 | 2026-06-20T09:10:04Z | `1ab241223bfa` | `84a4e6f46a7c` | `2b584531c2aa153569622f98ca3c81d584dd492c` | docs(progress): log library suite ticket |
| v20 | 2026-06-20T09:23:17Z | `cdb2b2c0c1f0` | `f9bdeb88ba0b` | `42914d23f586f7e6c126b814d9b5232c73aacc3c` | feat(rtl): add PAL-backed text files |
| v21 | 2026-06-20T12:57:37Z | `6e575713da48` | `54170d2c2633` | `cbc2a169396a2862bd5d58b4f0a881ef4fc09b00` | docs(ticket): close subclass-field-offset + pcl-search-path (DONE) |
| v22 | 2026-06-20T13:36:47Z | `37e152ead9b0` | `355192a49fe7` | `9a8d2c6e15f3cd434bceeb6d47478bde9b7f52a9` | feat(compiler): method calls on a hard class typecast TClass(x).M(args) |
| v23 | 2026-06-20T16:05:51Z | `bb8e65776ea3` | `f7c9dc5fe089` | `fe9637d18df9983223ff9d7d21614e3ab040cb3f` | fix(parser): array-of-string element -> managed AnsiString (per-use) |
| v24 | 2026-06-20T17:03:42Z | `66d0163736d0` | `cc6717845ef5` | `41423a454466818a608b6c52b3fda8ec181fefed` | docs(ticket): record string-model slices 1-4p1 done; flip held |
| v25 | 2026-06-20T17:35:13Z | `fad360a78c62` | `0b28bfedc0ed` | `0d6c61f5d655e6890c5a6676e81c879333187097` | Implement PCL graphics, drawing, canvas, PaintBox, and GTK Cairo backend |
| v26 | 2026-06-20T20:07:04Z | `227a58eb627e` | `1786e3620b33` | `b9e8979bd0860e1821b5bd72949e5a375a4377fa` | test(string-model): RTTI typinfo frozen-name read + managed-flip regression |
| v27 | 2026-06-21T11:00:00Z | `2ca8787544fa` | `e8a69822bef8` | `e7dbc0b06dd2a7c0b570875a50964a9e84db387b` | docs(tickets): movslq pointer-truncation DONE; lexer suffix-keyword REJECTED |
| v28 | 2026-06-21T11:14:42Z | `1b0f9c0791b1` | `3bd22eb31770` | `6054e977dfba329eca876ea85993bc41b61bd64a` | fix(parser): search .h/.c for units in the lib/pcl widgetset dir |
| v29 | 2026-06-21T11:20:39Z | `5f5293f81bbd` | `d4dca78d33e3` | `3bb65f3ab03d57464c6cadb540db990354f77c7c` | feat(tools): install.sh — `pxx` wrapper on PATH for the pinned compiler |
| v30 | 2026-06-21T12:01:13Z | `9bb56f44863a` | `90090acfb0a5` | `ca52cf6195fcddef9f68dd2b68671287240ec787` | docs(tickets): Inc/Dec lvalue bug DONE (reframed from feature); file local-typed-const |
| v31 | 2026-06-21T12:49:38Z | `65b6177e660e` | `a56f77300fec` | `e44583fba6f427ea46d6a2f2687941982e26e2e0` | feat(esp-float): Trunc + float unary minus on riscv32/xtensa |
| v32 | 2026-06-21T13:31:06Z | `c01e163bedc6` | `4c88d9236680` | `48cbe358b53129e307d2f30c075c283621bed65a` | docs(ticket): esp-float Round/Frac/Int done; core functionally complete |
| v33 | 2026-06-22T08:54:51Z | `489d7da76554` | `c87785dc8782` | `4af4085fb5581a1f2fcd19844bf62cd03ecd5aea` | refactor(parser): harden all 9 paramless self-recursion sites to F() |
| v34 | 2026-06-22T10:44:32Z | `73edfe40be62` | `5153dd771c3f` | `618cec65edeb0d63e885affa6c2e9030f0ea99ef` | fix(parser): local variable shadows same-named paramless function |
| v35 | 2026-06-22T11:45:31Z | `7d30d1e8d659` | `4a37b0060c16` | `8c85e8a797ac36820c699ca0df771b65fdc36a2a` | fix(parser): named dyn-array alias as a class/record field is a real dyn array |
| v36 | 2026-06-22T12:07:45Z | `180adf3a5108` | `39d851a848aa` | `22dc70fa376666295b776c844b27b12806287ffb` | fix(codegen): whole dyn-array assignment into a record/object field |

> Generated from `history.log` + `git rev-parse HEAD:…/vN` at the removal commit. `pin.log`/`history.log` retain the full sha256 and audit trail. New stables overwrite `stable_latest`/`stable_pinned` in place, so this list does not grow per-pin — only releases keep permanent binaries (rebuilt fresh, not from here).
