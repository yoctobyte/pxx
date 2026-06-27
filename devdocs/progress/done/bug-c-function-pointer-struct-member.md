# C: function-pointer struct member is silently dropped (layout + call + parse)

- **Type:** bug (C frontend → struct layout) — Track C
- **Status:** working
- **Owner:** (in progress)
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]). The next real wall after the
  default-crtl-include fix.

## Symptom (one root, three faces)

An inline function-pointer struct member — `RET (*name)(params);` — is **dropped**
during struct layout. `ParseCDeclType` fully consumes `(*name)(params)` and
captures the name (`CTypeFnPtrName`) + a call signature (`CTypeProcSig`), but
`ParseCStructInto` then expects to read the member name itself (`if CurTok.Kind
<> tkIdent then Break`), finds none, and `Break`s — so the field is never
registered. Consequences:

1. **Layout corruption.** The field is missing, so every following field's
   offset is wrong and an initializer mis-aligns.
   ```c
   struct cfg { int n; int (*fp)(); int m; };
   static struct cfg g = { 1, 0, 2 };
   int main(void){ return g.n + g.m; }   /* want 3, got 1 */
   ```
2. **Call mis-computes / fails.** `s.fp(args)` can't resolve a field that isn't
   there.
   ```c
   struct cfg { int (*fp)(int); };
   static int add1(int x){ return x+1; }
   int main(void){ struct cfg c; c.fp = add1; return c.fp(41); }  /* want 42, got 36 */
   ```
3. **Parse desync in context.** sqlite3.c:19490
   `0==sqlite3Config.xAltLocaltime((const void*)t,(void*)pTm)` → `unexpected token`.

## Fix (registration — the single root)

In `ParseCStructInto`, after `ParseCDeclType`, when `CTypeFnPtrName <> ''`
register the member directly: name = `CTypeFnPtrName` (token off/len), type =
`tyPointer` (8 bytes / 8-align), proc sig = `CTypeProcSig`; advance `curOff`,
`Eat(tkSemicolon)`, and skip the normal name-reading declarator loop. Mirrors the
existing fn-ptr *typedef* path (cparser.inc:4334) and the buffered-field block.

Needs the name token's offset/len exposed from `ParseCDeclType` (new
`CTypeFnPtrNameOff/Len`, captured where `fpName` is captured, reset at the top).

## Acceptance

- The three repros above return 3 / 42 / compile.
- sqlite advances past line 19490.
- C tests green + self-host byte-identical.
- If `s.fp(args)` still mis-lowers after registration (a separate call-lowering
  gap), file that as a follow-up.

## Log

- 2026-06-27 - Root-caused to the dropped member in ParseCStructInto. Taking it.

## DONE (layout/registration) 2026-06-27

Fixed in commit (fix(cfront): register inline function-pointer struct members):
ParseCStructInto now registers `RET (*name)(params);` members as 8-byte pointer
fields with the captured sig. Layout repro reads 3 (was 1). Typedef'd fn-ptr
fields unaffected. Full gate green, self-host byte-identical.

**Split out:** the *call* of an inline fn-ptr member is a SEPARATE lowering gap →
[[bug-c-call-inline-function-pointer-struct-member]]. Layout part of this ticket
is complete; closing it.
