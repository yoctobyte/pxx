---
title: --rename-globals -- NetBSD's rumpns_ rename done by pxx, so a rump kernel builds without binutils
status: done
owner: claude-dupwt
prio: 60
area: backend/linker
---

# --rename-globals=PREFIX, --rename-globals-keep=a,b,...

NetBSD's rump build renames every global of a rump kernel object, the ones
it defines and the ones it uses, to `rumpns_<name>`. It keeps names starting
`rump`, `RUMP`, `__`, `_GLOBAL_OFFSET_TABLE` and `.TOC.`. The build does this
with `nm -go | awk` and `objcopy --redefine-syms`. Rainyday's all-pxx
rumpnic build (tools/rump-pxx-build.sh) did the same to pxx's objects, so
it still needed binutils. Nodisx builds rumpnic on the target, where there
are no binutils (umbrella-nodisx-compiles-the-whole-system-on-site-with-pxx,
item 3).

pxx now does the rename itself under `--emit-obj`:
`--rename-globals=rumpns_ --rename-globals-keep=rump,RUMP,__,_GLOBAL_OFFSET_TABLE,.TOC.`.
ObjRenameGlobals (elfwriter.inc) runs on the finished file, after the
writer. It works for every object shape (function sections, weak symbols,
common symbols) because it never touches the writers' tables:

- GLOBAL or WEAK symbols that are not SECTION or FILE symbols, are named,
  and match no keep prefix get `prefix+name`;
- the new names go into a copy of .strtab, appended at the end of the file,
  and the strtab section header is repointed to it;
- relocations name symbols by index, so they are unchanged.

ELF64 little-endian only (x86-64 and aarch64 hosted objects). Any other
input stops with an error rather than producing a silently wrong object.

A short write to the object is still reported. OutWriteShort is not reset
here, so a full disk during the writer is not hidden by the rewrite
(a-full-disk-makes-the-compiler-lie-green).

## Proof

- test-core row c_rnglob26 (test/c_rename_globals_{kernel,host}.c) checks
  the nm list: defined, undefined, weak and data symbols are renamed; the
  static local, the kept `__` name and the `rumpuser_` name are not. Then
  it links against an unrenamed object that supplies the `rumpns_` names,
  and the program prints the expected `118 7`.
- On the same C file, the result matches binutils' rule
  (`nm -go | awk` + `objcopy --redefine-syms`) symbol for symbol.
- tools/nodisx/rumpnic: the whole rump kernel (458 renamed units) builds on
  site with it and boots (see feature-nodisx-rumpnic-built-on-site-by-pxx).
