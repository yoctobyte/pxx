---
slug: decide-posix-master-vs-fpc-named-master-for-the-socket-facades
track: U
prio: 25
status: open
---

# `Posix.*` is master, or the FPC-named units are? The tree has already answered, the other way

**The fork blocking [[feature-b-posix-and-fpc-named-socket-facades]].** That
ticket carries a design whose one explicitly-settled question is *"`Posix.*` is
canonical; `BaseUnix`/`Sockets`/`UnixType` are thin wrappers over it, not
siblings"* — decided 2026-06-19, inside `feature-networking`, and never built.
Since then the tree grew the FPC-named units demand-driven and they answered the
question the opposite way by shipping. Nobody has re-argued the design against
that answer, and no agent should pick this up until someone does. Hence a `U`
ticket rather than a implementation task.

## What is actually in tree (re-measured 2026-08-30 by frankB, against `d9b663137`)

| unit the design names | in tree | sits on | consumers |
| --- | --- | --- | --- |
| `sockets` | **633 lines** | `platform` (PAL) directly, 17 PAL call sites | `lib/rtl/netdb.pas`, `test/lib_sockets.pas`, `test/lib_tls.pas`, `test/lib_https_mock.pas` |
| `baseunix` | 149 lines | nothing — no `uses` clause at all | **11 in-tree**: `test/lib_unixshims.pas`, `test/manual/test_pylexer.pas`, nine `examples/**` — plus Synapse |
| `unix` | 46 lines | — | `test/lib_unixshims.pas`, Synapse `synautil` |
| `unixutil` | 16 lines | — | `test/lib_unixshims.pas`, Synapse `synautil` |
| `unixtype` | **absent** | — | — |
| `Posix.*` | **absent** | — | — |

Synapse names these from `external/synapse/`: `synautil.pas:81` pulls
`UnixUtil, Unix, BaseUnix`; `synaser.pas:139` pulls `baseunix, unix`; the three
`ssl_openssl*_lib.pas` pull `BaseUnix` and `Sockets`.

### Two corrections to the numbers in the feature ticket

Both were mine to make and both cut the same way — this is *more* load-bearing
than the earlier note said, not less:

- **`baseunix` has 11 in-tree consumers, not 10.** The earlier note listed
  `test/lib_unixshims.pas` and nine examples; `test/manual/test_pylexer.pas`
  also names it.
- **`compiler/compiler.pas` is a FALSE POSITIVE and must not be counted.** Line
  39 does read `uses SysUtils, Math, BaseUnix, …`, but it sits inside
  `{$ifdef FPC}` — true only under real FPC, never under PXX — so it resolves to
  *FPC's* BaseUnix during the seeded bootstrap and is not taken under self-host.
  A grep for `baseunix` finds it and reads as "the compiler itself depends on
  this", which would wrongly put the self-host gate in the blast radius of any
  inversion. It does not. This is the same shape as the feature ticket's own
  named false positive, `test/dotted/posix.syssocket.pas`.

## The part that is new, and that I think decides it

**All three of the design's selectable backends already exist — one layer down,
at the PAL, under different names.** The design's substantial content was not
the unit names; it was *one interface, several bodies*:

| the design's backend | what is in tree today |
| --- | --- |
| `posix_syscall` — default, libc-free | `lib/rtl/platform/posix/platform_backend.pas`, syscall-based, with `PAL_GENERIC_SYSCALLS` per-CPU selection |
| `posix_libc` — opt-in via `PXX_POSIX_LIBC` | the same file's `-dPXX_DYNLIB_LIBC` path (dlopen/dlsym via libc.so.6) |
| `posix_lwip` — so the surface reaches ESP | `lib/rtl/platform/esp/platform_backend.pas` |

The grep is unambiguous on the other half: `PXX_POSIX_LIBC`, `posix_syscall` and
`posix_lwip` appear **nowhere in the tree** except this feature ticket, the
closed `feature-networking`, and `devdocs/developer/plan-networking.md`. They are
design vocabulary that was never spoken in code — because the capability landed
under PAL's vocabulary instead.

So building `Posix.*` as designed would not be adding the backend mechanism. It
would be adding a *second* backend-selection mechanism, at the facade layer,
over a substrate that already selects backends. That is the "how many mechanisms
serve one concept" smell from `root-cause-over-microfix.md`: two is a smell.

And it would be a **fourth** face over PAL. Three exist: `sockets.pas`
(FPC-named, blocking), `net.pas` (portable `TNetSocket`, 377 lines),
`asyncnet.pas` (coroutine, 201 lines).

## The fork

**A — Build it as designed.** Create `Posix.*` + `unixtype` on PAL, then
re-parent `sockets` and `baseunix` onto it as thin wrappers. Honours the 2026-06
decision. Cost: an inversion of a working layer with 15 in-tree consumers plus
Synapse, to serve zero current consumer, adding a second backend-selection
mechanism.

**B — Invert the design: FPC-named stays master; `Posix.*` becomes the wrapper,
built only when something asks for it.** Matches what shipped. `Posix.SysSocket`
would be a thin spelling over `sockets.pas`, added on demand, with no
re-parenting and no risk to existing consumers. Costs the design's stated
master-decision, which was made before the layer it now contradicts existed.

**C — Close the design as superseded and drop the feature ticket.** Cleanest
board, but discards a genuinely-reasoned design that a future Delphi-source
consumer might want.

## Recommendation: **B**

The 2026-06 decision was sound *for 2026-06*, when neither the FPC-named units
nor the PAL backend split existed and `Posix.*` was the only proposed place to
put backend selection. Both of its premises have since been overtaken by the
tree: the facade layer got built the other way up, and the backend mechanism got
built one layer lower. A decision does not survive the disappearance of both its
premises just because it was explicit.

B keeps the capability reachable (a `Posix.*` spelling can still be added the
day real Delphi-flavoured source needs it), costs nothing today, and does not
put `sockets.pas`'s four consumers or `baseunix`'s eleven at risk for a rename.

I am recommending, not deciding — the design was settled deliberately by the
user's programme and it is not Track B's to overturn. **If B is chosen**, the
feature ticket should be rewritten around it rather than closed, because the
`unixtype` gap and the on-demand `Posix.*` spelling are still real work.

## The recorded rationale — read, and it is overtaken by the same event

I wrote this section as a disclaimer first ("I did not read the plan"). Reading
it was cheap, so here is the rationale instead of a hedge — and it does not
survive, for a reason stronger than the one above.

`plan-networking.md:77-105` records the decision with its *why*: `Posix.*` is
master because **goal 2 of the whole programme was to compile Synapse through
its Delphi-`Posix.*` branch, explicitly not its FPC/`BaseUnix` branch**
(`:16`, `:188-202`). The plan even argues the choice: Synapse's Unix support has
three branches, and the Delphi-POSIX one was picked because its surface is "a
small, well-defined dozen units" rather than the whole FPC compat surface. Given
that goal, Posix-as-master follows necessarily — the consumer would have been
speaking `Posix.*` directly.

**That goal was abandoned in practice, and the gate records it.** Every Synapse
job in `lib-test` compiles the **FPC branch**:

```
Makefile:15755  $(PXX_STABLE) --mimic-fpc -Fuexternal/synapse … test/lib_synapse.pas
Makefile:15757  $(PXX_STABLE) --mimic-fpc … test/lib_synapse_transitive_unit.pas
Makefile:15763  $(PXX_STABLE) --mimic-fpc -dPXX_DYNLIB_LIBC … test/lib_synapse_ssl.pas
Makefile:15784  $(PXX_STABLE) --mimic-fpc -dPXX_DYNLIB_LIBC … test/lib_synapse_tls_loopback.pas
```

`--mimic-fpc` selects the branch the plan said *not* to target, and it is the
route that succeeded — `synautil.pas:81` pulling `UnixUtil, Unix, BaseUnix` is
that branch consuming our FPC-named units. Nothing in tree compiles Synapse's
Delphi-`Posix.*` branch, and no `Posix.*` unit exists to compile it with.

Note the last two lines twice over: `-dPXX_DYNLIB_LIBC` is the design's
`PXX_POSIX_LIBC` switch, at PAL's layer under PAL's name — so the selectable
backend is not merely built elsewhere, it is **exercised in the gate today**.

So the master decision rests on a goal the programme dropped, and its backend
mechanism rests in a layer that already provides one. Both premises are gone by
measurement rather than by argument, which is why I think this is a decision to
re-take rather than a design to implement.

## What would change my recommendation

If the user still wants Synapse's **Delphi-`Posix.*` branch** compiling — as a
capability in its own right, not as a route to Synapse, which the FPC branch
already delivers — then **A is correct and this ticket should say so**, because
that goal is what made Posix master in the first place and it would restore the
premise. That is a product call about which dialects of real-world source PXX
should swallow, and it is exactly the kind of question Track U exists for.
