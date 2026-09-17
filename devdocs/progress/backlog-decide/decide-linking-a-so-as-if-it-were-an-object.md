---
slug: decide-linking-a-so-as-if-it-were-an-object
title: "Should pxx be able to consume a .so as if it were a .o?"
track: U
prio: 20
type: decide
blocked-by: []
status: decided
created: 2026-09-17
found: 2026-09-17
found-by: frank-user, scoping pxx --link with the owner
owner: ""
summary: "DECIDED NO, 2026-09-17, and filed so nobody rediscovers it. Raised by the owner while scoping `pxx --link`. A .so has ALREADY BEEN LINKED and the information a static link needs was consumed and discarded on the way: its relocations are DYNAMIC (.rela.dyn/.rela.plt — instructions for ld.so at load time, not for a linker at build time), its symbols are in .dynsym while the .symtab and .rela.text a static link needs are usually stripped, it is position-independent and already laid out so there is no per-function granularity to select from, and copy relocations, symbol interposition, version records and init order across the DT_NEEDED chain are loader semantics with no static equivalent. Tools claiming to do this are approximating and break on the general case. THE REAL QUESTION UNDERNEATH IS DIFFERENT AND ALREADY ANSWERED: 'I have a .so, no source and no .a, and I want to use it' is served by staying DYNAMIC, which pxx already supports on the producer side — elfwriter.inc emits DT_NEEDED (line 236) and a dynsym (314), and the weakexternal path (157-167) lets a library reached only by weak imports contribute NO DT_NEEDED at all, so a weak-only program collapses back to a static link. So: no, and the alternative is not a compromise."
---

# Should pxx consume a `.so` as if it were a `.o`?

## The fork, in one sentence

Do we want pxx to be able to statically absorb a shared library it was not given
the source or the `.a` for — or is "use a shared library" served by linking
against it dynamically, the way everyone else does?

## Decided: NO, and the reason is not cost

This is not a hard feature we are declining on budget. **It is not a coherent
operation in the general case**, and that distinction matters because a cost
decision gets relitigated when someone finds a cheaper route and this one should
not be.

A `.so` is the OUTPUT of a link. The four things a static link would need have
all been consumed or discarded by the time the file exists:

1. **Relocations.** What remains are DYNAMIC relocations — `.rela.dyn` and
   `.rela.plt` — which are instructions for `ld.so` at load time. The link-time
   relocations (`.rela.text` and friends) that say how to patch code into a new
   layout are gone.
2. **Symbols.** `.dynsym` is an EXPORT list. The `.symtab` a static link needs is
   usually stripped, and even when present it does not carry section-relative
   information for code that has already been laid out.
3. **Granularity.** The image is position-independent and already arranged.
   There is nothing to select: you take the whole `.so` or none of it, which
   defeats the usual reason for wanting a static link.
4. **Semantics with no static equivalent.** Copy relocations, symbol
   interposition, `.gnu.version_r` version records, and initialisation order
   across the `DT_NEEDED` chain are properties of the dynamic loader. A static
   link has no place to put them.

## What to do instead, and it is not a workaround

**Link against it dynamically.** pxx already implements the producer side:
`DT_NEEDED` emission (`compiler/elfwriter.inc:236`), `.dynsym`
(`elfwriter.inc:314`), and the `weakexternal` optional-import path
(`elfwriter.inc:157-167`), where a library reached ONLY by weak imports
contributes no `DT_NEEDED` and the program collapses back to a static link.

If a genuinely static result is required, the answer is to obtain the `.a` or the
source. That is the same answer every other toolchain gives.

## What would reopen this

A concrete program we want to build, named, that we cannot build any other way —
not a general wish for the capability. If that program appears, the scope is
*that* library and not the general case.

## See also

- `feature-a-pxx-cannot-link-its-own-objects-so-a-freestanding-multi-object-program-needs-gcc` — rung 1, the live ticket, and rung 2 (third-party objects) scoped there.
- `devdocs/dev/linking-in-this-tree.md` — the concepts, mapped onto our own source.
