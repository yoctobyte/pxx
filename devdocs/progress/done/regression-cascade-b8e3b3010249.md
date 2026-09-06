---
prio: 70
---

> **origin/master has advanced 13 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.


# regression CASCADE: 42 jobs newly red in 9d5a4e270..b8e3b3010 (16 commits) — auto-filed by twatch

- **Type:** regression cascade (auto-filed by Track T watcher, host seven).
  Untriaged. 42 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-09-04T18:47:44Z
- **Root-cause suspects in the red set:** none of the known root jobs (`fpc-bootstrap`, `selfhost-fixedpoint`). That is the ONLY heuristic applied here — it does not imply a harness event, and nothing in this filing looked at the build, the box or the range. See the Range section below for commits worth checking.

## Range
> **The named sha `b8e3b3010249` CANNOT be the cause** — it touches no buildable file (docs/tickets/tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range, and the cause is somewhere below it.

bad `b8e3b3010249`, last good `9d5a4e27029e`, **16 commit(s) in range** (16 of them buildable). **No idle bisect will happen** — the watcher skips cascades deliberately (one synthetic key matches no job), so this range is narrowed by hand or not at all.

**Buildable commits in the range, newest first:**
- `6df5ba55877a` feat(C): GNU inline asm with a non-empty template on i386 — the same parser, a text sink
- `c6f1e3f91c2d` fix(C): a GNU inline-asm "m" operand is a frame slot, not a pinned register
- `a07ca8878f18` test(P): wire the four method-pointer / procedural-value tests into the recipe
- `01998adb8998` fix(P): a local generic declaration shadows an imported one — and it was never the lookup
- `eaf3144e593f` feat(T): a copied RTL type alias can no longer drift silently — and the census that would 
- `a623307bddf3` fix(P,B): System.TMethod is declared once — delete the RTL duplicates, and let a UNIT see 
- `d9604ea599a2` fix(P): a default property indexed as an assignment target, and for-in over a pointer dere
- `e4ee8048cbe7` fix(P): {$ASSERTIONS OFF} was accepted and ignored, so the condition still ran
- `02a57e20ec35` fix(P): a different specialization of the same template, inside its own body — one surface
- `f5200b8a492c` tickets(T): the last full-tier red is seven's emulator, not the tree — and the class is wo
- `44c08dc663ec` fix(P): one node-keyed answer to "is this a procedural value", and the parenless call foll
- `92aef7677bed` fix(T): the host-epoch governor check tested itself, not twatch
- ...and 4 earlier commit(s) in the range, not listed

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier full --job '<job>'` at b8e3b301024907a1200d3d149ca427df6eca755e

(The sha above is the right one to REPRODUCE at — the jobs really are red
there — even when the Range section says it cannot be the CAUSE. Reproducing
and blaming are different questions and this line answers the first.)

## Newly red jobs
> Each job's own recorded failure REASON is printed under its name. **When the
> reasons and the Range section disagree, the reasons win.** The range is
> computed from what CHANGED, not from what the job can SEE — a missing guest
> loader, an absent dev package or a job that has never once passed on this box
> all produce a red that no commit in the range caused.

- `demos#00`
  - OK examples/sudoku/sudoku.pas | FAIL examples/tk/uses_tkinter_and_configparser.pas -- near: m : TMethod ; begin m >>> . Code := | OK examples/tui/menudemo.pas | OK examples/vm/vmdemo.pas | === demos:…
- `lib-test#src:examples/json/jsondemo.pas`
  - pascal26:968: error: unknown type: TMethod | in: stable_linux_amd64/default/../../lib/rtl/typinfo.pas | near: addr : Pointer ; m : >>> TMethod ; begin | pascal26:970: error: a value of this type has…
- `lib-test#src:examples/net/httpdemo.pas`
  - pascal26:968: error: unknown type: TMethod | in: stable_linux_amd64/default/../../lib/rtl/typinfo.pas | near: addr : Pointer ; m : >>> TMethod ; begin | pascal26:970: error: a value of this type has…
- `lib-test#src:examples/shell/nilsh.npy`
  - pascal26:992: error: "Code": this value has no members (only records, classes, interfaces and variants do) | in: stable_linux_amd64/default/../../lib/rtl/typinfo.pas | near: PMethod ( addr ) ^ . >>>…
- `lib-test#src:test/lib_base64.pas`
  - pascal26:968: error: unknown type: TMethod | in: lib/rtl/typinfo.pas | near: addr : Pointer ; m : >>> TMethod ; begin | pascal26:970: error: a value of this type has no members (only records, classes…
- `lib-test#src:test/lib_codecs.npy`
  - in: stable_linux_amd64/default/../../lib/rtl/typinfo.pas | near: PMethod ( addr ) ^ . >>> Code := v | pascal26:993: error: "Data": this value has no members (only records, classes, interfaces and var…
- `lib-test#src:test/lib_dns_resolved.pas@2`
  - pascal26:968: error: unknown type: TMethod | in: lib/rtl/typinfo.pas | near: addr : Pointer ; m : >>> TMethod ; begin | pascal26:970: error: a value of this type has no members (only records, classes…
- `lib-test#src:test/lib_http.pas`
  - pascal26:968: error: unknown type: TMethod | in: stable_linux_amd64/default/../../lib/rtl/typinfo.pas | near: addr : Pointer ; m : >>> TMethod ; begin | pascal26:970: error: a value of this type has…
- `lib-test#src:test/lib_http_async.pas`
  - pascal26:968: error: unknown type: TMethod | in: stable_linux_amd64/default/../../lib/rtl/typinfo.pas | near: addr : Pointer ; m : >>> TMethod ; begin | pascal26:970: error: a value of this type has…
- `lib-test#src:test/lib_http_cookie.pas`
  - pascal26:968: error: unknown type: TMethod | in: stable_linux_amd64/default/../../lib/rtl/typinfo.pas | near: addr : Pointer ; m : >>> TMethod ; begin | pascal26:970: error: a value of this type has…
- `lib-test#src:test/lib_http_gzip.pas`
  - pascal26:968: error: unknown type: TMethod | in: stable_linux_amd64/default/../../lib/rtl/typinfo.pas | near: addr : Pointer ; m : >>> TMethod ; begin | pascal26:970: error: a value of this type has…
- `lib-test#src:test/lib_http_keepalive.pas`
  - pascal26:968: error: unknown type: TMethod | in: stable_linux_amd64/default/../../lib/rtl/typinfo.pas | near: addr : Pointer ; m : >>> TMethod ; begin | pascal26:970: error: a value of this type has…
- `lib-test#src:test/lib_http_pool.pas`
  - pascal26:968: error: unknown type: TMethod | in: stable_linux_amd64/default/../../lib/rtl/typinfo.pas | near: addr : Pointer ; m : >>> TMethod ; begin | pascal26:970: error: a value of this type has…
- `lib-test#src:test/lib_http_pool_concurrent.pas`
  - pascal26:968: error: unknown type: TMethod | in: stable_linux_amd64/default/../../lib/rtl/typinfo.pas | near: addr : Pointer ; m : >>> TMethod ; begin | pascal26:970: error: a value of this type has…
- `lib-test#src:test/lib_http_redirect.pas`
  - pascal26:968: error: unknown type: TMethod | in: stable_linux_amd64/default/../../lib/rtl/typinfo.pas | near: addr : Pointer ; m : >>> TMethod ; begin | pascal26:970: error: a value of this type has…
- `lib-test#src:test/lib_http_serve.pas`
  - pascal26:968: error: unknown type: TMethod | in: stable_linux_amd64/default/../../lib/rtl/typinfo.pas | near: addr : Pointer ; m : >>> TMethod ; begin | pascal26:970: error: a value of this type has…
- `lib-test#src:test/lib_httpjson.pas`
  - pascal26:968: error: unknown type: TMethod | in: stable_linux_amd64/default/../../lib/rtl/typinfo.pas | near: addr : Pointer ; m : >>> TMethod ; begin | pascal26:970: error: a value of this type has…
- `lib-test#src:test/lib_https_mock.pas`
  - pascal26:968: error: unknown type: TMethod | in: stable_linux_amd64/default/../../lib/rtl/typinfo.pas | near: addr : Pointer ; m : >>> TMethod ; begin | pascal26:970: error: a value of this type has…
- `lib-test#src:test/lib_markdown.pas`
  - pascal26:968: error: unknown type: TMethod | in: lib/rtl/typinfo.pas | near: addr : Pointer ; m : >>> TMethod ; begin | pascal26:970: error: a value of this type has no members (only records, classes…
- `lib-test#src:test/lib_mimic_bisect.npy`
  - in: lib/rtl/typinfo.pas | near: PMethod ( addr ) ^ . >>> Code := v | pascal26:993: error: "Data": this value has no members (only records, classes, interfaces and variants do) | in: lib/rtl/typinfo.p…
- `lib-test#src:test/lib_mimic_codecs.npy`
  - in: lib/rtl/typinfo.pas | near: PMethod ( addr ) ^ . >>> Code := v | pascal26:993: error: "Data": this value has no members (only records, classes, interfaces and variants do) | in: lib/rtl/typinfo.p…
- `lib-test#src:test/lib_mimic_collections_abc.npy`
  - in: lib/rtl/typinfo.pas | near: PMethod ( addr ) ^ . >>> Code := v | pascal26:993: error: "Data": this value has no members (only records, classes, interfaces and variants do) | in: lib/rtl/typinfo.p…
- `lib-test#src:test/lib_mimic_colorsys.npy`
  - in: lib/rtl/typinfo.pas | near: PMethod ( addr ) ^ . >>> Code := v | pascal26:993: error: "Data": this value has no members (only records, classes, interfaces and variants do) | in: lib/rtl/typinfo.p…
- `lib-test#src:test/lib_mimic_copy.npy`
  - in: lib/rtl/typinfo.pas | near: PMethod ( addr ) ^ . >>> Code := v | pascal26:993: error: "Data": this value has no members (only records, classes, interfaces and variants do) | in: lib/rtl/typinfo.p…
- `lib-test#src:test/lib_mimic_six.npy`
  - in: lib/rtl/typinfo.pas | near: PMethod ( addr ) ^ . >>> Code := v | pascal26:993: error: "Data": this value has no members (only records, classes, interfaces and variants do) | in: lib/rtl/typinfo.p…
- `lib-test#src:test/lib_mimic_six_moves.npy`
  - near: PMethod ( addr ) ^ . >>> Code := v | pascal26:993: error: "Data": this value has no members (only records, classes, interfaces and variants do) | in: lib/rtl/typinfo.pas | near: PMethod ( addr…
- `lib-test#src:test/lib_mimic_string_template.npy`
  - in: lib/rtl/typinfo.pas | near: PMethod ( addr ) ^ . >>> Code := v | pascal26:993: error: "Data": this value has no members (only records, classes, interfaces and variants do) | in: lib/rtl/typinfo.p…
- `lib-test#src:test/lib_mimic_urllib_error.npy`
  - in: lib/rtl/typinfo.pas | near: PMethod ( addr ) ^ . >>> Code := v | pascal26:993: error: "Data": this value has no members (only records, classes, interfaces and variants do) | in: lib/rtl/typinfo.p…
- `lib-test#src:test/lib_mimic_urllib_parse.npy@2`
  - in: lib/rtl/typinfo.pas | near: PMethod ( addr ) ^ . >>> Code := v | pascal26:993: error: "Data": this value has no members (only records, classes, interfaces and variants do) | in: lib/rtl/typinfo.p…
- `lib-test#src:test/lib_mimic_warnings.npy`
  - in: lib/rtl/typinfo.pas | near: PMethod ( addr ) ^ . >>> Code := v | pascal26:993: error: "Data": this value has no members (only records, classes, interfaces and variants do) | in: lib/rtl/typinfo.p…
- `lib-test#src:test/lib_mimic_weakref.npy`
  - in: lib/rtl/typinfo.pas | near: PMethod ( addr ) ^ . >>> Code := v | pascal26:993: error: "Data": this value has no members (only records, classes, interfaces and variants do) | in: lib/rtl/typinfo.p…
- `lib-test#src:test/lib_mimic_xml_dom.npy`
  - in: lib/rtl/typinfo.pas | near: PMethod ( addr ) ^ . >>> Code := v | pascal26:993: error: "Data": this value has no members (only records, classes, interfaces and variants do) | in: lib/rtl/typinfo.p…
- `lib-test#src:test/lib_mimic_xml_dom_minidom.npy@2`
  - in: lib/rtl/typinfo.pas | near: PMethod ( addr ) ^ . >>> Code := v | pascal26:993: error: "Data": this value has no members (only records, classes, interfaces and variants do) | in: lib/rtl/typinfo.p…
- `lib-test#src:test/lib_mimic_xml_etree_elementtree.npy`
  - in: lib/rtl/typinfo.pas | near: PMethod ( addr ) ^ . >>> Code := v | pascal26:993: error: "Data": this value has no members (only records, classes, interfaces and variants do) | in: lib/rtl/typinfo.p…
- `lib-test#src:test/lib_mimic_xml_sax_saxutils.npy`
  - in: lib/rtl/typinfo.pas | near: PMethod ( addr ) ^ . >>> Code := v | pascal26:993: error: "Data": this value has no members (only records, classes, interfaces and variants do) | in: lib/rtl/typinfo.p…
- `lib-test#src:test/lib_mimic_xml_sax_xmlreader.npy`
  - in: lib/rtl/typinfo.pas | near: PMethod ( addr ) ^ . >>> Code := v | pascal26:993: error: "Data": this value has no members (only records, classes, interfaces and variants do) | in: lib/rtl/typinfo.p…
- `lib-test#src:test/lib_pyexec.npy@2`
  - pascal26:992: error: "Code": this value has no members (only records, classes, interfaces and variants do) | in: lib/rtl/typinfo.pas | near: PMethod ( addr ) ^ . >>> Code := v | pascal26:993: error:…
- `lib-test#src:test/lib_typinfo_props.pas`
  - pascal26:968: error: unknown type: TMethod | in: lib/rtl/typinfo.pas | near: addr : Pointer ; m : >>> TMethod ; begin | pascal26:970: error: a value of this type has no members (only records, classes…
- `lib-test#src:tools/crtl_reachability.py`
  - ... 18 more line(s) not shown | lib-units: FAIL uwidgetset | pascal26:413: error: unknown type: TMethod | pascal26:414: error: unknown type: TMethod | pascal26:965: error: unknown type: TMethod | ...…
- `test-fpjson#src:tools/install_lib_candidates.sh`
  - compiling fpjson suite runner ...
- `test-pascal-conformance#shard4/6`
  - SKIP tgeneric7.pp — gap: generics across units + $R range-check state per unit (expects runtime error 201) | SKIP toperator9.pp — gap: operator overload for `in` on a record type not supported by the…
- `test-pascal-conformance#shard5/6`
  - SKIP tprocvar2.pp — gap: typed const procvar initialized with bare proc name (TP mode), procvar via move() | SKIP tsetsize.pp — wontfix: asserts FPC's exact set-size/packing layout (SizeOf(set of sub…

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*

## Log
- 2026-09-06 — auto-closed by the seven watcher: `cascade@b8e3b3010249` passes at c543b335fb2f (tier full); it was red at b8e3b3010249. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
