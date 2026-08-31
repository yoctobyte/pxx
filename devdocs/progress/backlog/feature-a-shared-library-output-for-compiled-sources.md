---
track: A
prio: 50
type: feature
status: backlog
found: 2026-08-31
found-by: frankC
owner: ""
blocked-by: []
summary: "--shared writes an x86-64 ET_DYN for .asm sources only (compiler.pas says so in the option handler). A .so is harder than the .o that landed at 41045d7b4 and for one reason: writeELFSharedX64 needs ZERO R_X86_64_RELATIVE relocations because the .asm frontend has no absolute-address operand form AT ALL, while the general backend's EmitDataRef/EmitGlobRef are exactly that. So a compiled-source .so is blocked on the same backend work as feature-a-x86-64-object-output-is-position-dependent, not on writer work -- and unlike the .o, -no-pie cannot rescue it: a shared library IS relocated at load. Do that ticket first; this one is small afterwards."
---

# `--shared` for compiled sources, not just `.asm`

Deferred by [[meta-a-pxx-produces-linkable-code]] until the object writer's
shape was known.

## Why this is not the same job as the `.o`

The general x86-64 **object** writer landed with an absolute relocation model
and a documented `-no-pie` requirement. That trade is available because a
non-PIE executable chooses its own load address.

**A shared library does not.** It is relocated at load time by definition, so
the same absolute operands that a `-no-pie` link resolves cannot work here at
all. `writeELFSharedX64`'s own comment states the property it depends on: the
`.asm` frontend's addressing *"is already position-independent by
construction — there is no absolute-address operand form in this frontend at
all"*, so it emits zero `R_X86_64_RELATIVE` relocations. `EmitDataRef` and
`EmitGlobRef` are precisely that missing form.

So the blocker is backend work — [[feature-a-x86-64-object-output-is-position-dependent]] —
and not writer work. Either the backend grows a rip-relative global-reference
form, or the `.so` writer grows `R_X86_64_RELATIVE` emission for every
`Fixups`/`GlobFix`/`DataPtrFix`/`MethodFix` site plus a `DT_RELA`/`DT_RELACOUNT`
pair. **The second is the cheaper of the two and should be priced first** — it
is writer-local, it reuses the relocation inventory `writeELFRelX64General`
already walks, and it does not move a single instruction.

Do not start here expecting the `.o` work to carry over; the export surface and
symbol partition do, the relocation model does not.

## Umbrella

[[meta-a-pxx-produces-linkable-code]]
