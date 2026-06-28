# Support parsing and enforcing struct alignment and packed attributes in C header import

- **Type:** feature
- **Status:** backlog
- **Track:** C (C frontend)
- **Owner:** —
- **Opened:** 2026-06-28

## Motivation

Currently, the C lexer (`compiler/clexer.inc`) extracts structural layout attribute modifiers such as `__attribute__((packed))` and `__attribute__((aligned))` and sets simple binary flags `CAttrPacked` and `CAttrAligned`. However:
1. The compiler does not parse the exact alignment values (such as `aligned(16)` or `aligned(32)`).
2. It does not apply these modifiers during layout calculations for structures whose fields are read or written directly in Pascal.
3. This creates a risk of structural field drift and memory corruption when interoping with C structures that have custom byte alignments or are packed.

## Scope

1. **Attribute Value Parsing**:
   - Update `compiler/clexer.inc` to extract the alignment byte boundary integer $N$ from `aligned(N)`.
   - Store $N$ in the parsed symbol metadata or structural definition in `compiler/symtab.inc`.
2. **Structure Layout Enforcer**:
   - Update structure layout calculations (`compiler/parser.inc` or related struct offset generators) to respect `packed` (offset alignment = 1) and `aligned(N)` (pad fields or struct size to multiples of $N$).
   - Ensure these alignments match the host platform's C compiler layout conventions.

## Acceptance

- A structure defined with `__attribute__((packed))` or `__attribute__((aligned(16)))` has identical field offsets and total size in Pascal and C.
- Tests (e.g. `test/test_c_packed_aligned.pas`) verify that field offsets and total sizes match the compiled C counterparts.

## Log
- 2026-06-28 — ticket opened.
