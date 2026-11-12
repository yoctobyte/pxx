---
track: A
tags: [C]
prio: 40
type: bug
blocked-by: []
summary: "`extern uint64_t boot_epoch;` inside a function, with no file-scope declaration anywhere in the translation unit, was \"undeclared identifier\" at its first use (Gibux fs/ext2.c). Pass 1 skipped function bodies wholesale, so the name was only ever known if a later file-scope definition registered it. CHoistBlockScopeExterns now registers such object declarations in pass 1, before SkipBraceBlock; an object file then imports the name (UND)."
status: done
owner: unassigned
---

# A block-scope extern with no file-scope declaration is undeclared

C lets a function declare an object with external linkage locally:

    static uint64_t now(void) { extern uint64_t boot_epoch; return boot_epoch; }

pxx's pass 1 collects file-scope declarations and skips function bodies. If
the definition sat later in the same file, pass 1 found it there, so a
single-file program worked. In a kernel the definition is in another file, so
nothing registered the name.

## Fix

CHoistBlockScopeExterns (cparser.inc) runs in pass 1, in CHeaderMode and
CProgramMode, before SkipBraceBlock. It scans the body for `extern T name;`
object declarations whose name has no global yet, and registers each through
ParseCGlobalVarDecl as an extern.

## Test

test/c_block_scope_extern_with_no_file_scope_declaration.c:

- run, it prints gcc's `1700000008`;
- with `-dNO_DEFINITIONS --emit-obj`, the Makefile row checks that
  boot_epoch is UND in the object.

The d9a0d9a599 compiler refuses the second form: "undeclared identifier
'counts' used as value".
