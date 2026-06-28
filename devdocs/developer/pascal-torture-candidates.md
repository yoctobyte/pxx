# Pascal Torture-Corpus Candidates

**Snapshot:** 2026-06-28

This note collects Pascal/Object Pascal libraries that are useful as compiler
torture workloads. They are not automatic dependencies and not promises of
compatibility. The pattern is the same as the library-suite discovery lane:
stage candidate source outside `lib/`, compile the smallest meaningful slice,
and turn failures into focused Track A/B tickets.

## Already Tracked Or Partly Covered

| Candidate | Current project hook | Why it matters |
| --- | --- | --- |
| Synapse | [[feature-synapse-compile-check]] | Networking library in Object Pascal. Smaller and cleaner than Indy. Good sockets, streams, protocol, conditional-compilation, and RTL-breadth test. |
| RemObjects Pascal Script | [[feature-embed-pascal-script]] | Pascal interpreter/compiler written in Pascal. Good parser-ish code, variants, RTTI/class registration, and meta-circular stress. |
| Lazarus/LCL shape | GUI/LFM/PCL docs and tickets | Big GUI framework shape: inheritance, properties, events, component streaming, resources, and platform conditionals. A stock Lazarus-style hello world has already been used; full LCL remains much heavier. |
| FPC compiler source | [[goal-compile-fpc-compiler]] | The long-term summit for conservative Object Pascal source compatibility. Keep separate from importing the FPC RTL/FCL as libraries. |

## Strong Next Candidates

| Candidate | Why it is interesting | First useful probe |
| --- | --- | --- |
| TRegExpr | Compact but nontrivial regular-expression parser/state-machine code. Good strings, sets/ranges, backtracking/state, and parser control-flow test. | Compile the core regex unit and run a tiny match suite. |
| DCPcrypt | Pure Pascal crypto library. Strong for bit operations, overflow semantics, endian handling, packed records, and byte arrays. | Compile one hash and one block cipher, compare known vectors. |
| BGRABitmap | Image/graphics library. Stresses records, overloaded routines, pixel-level loops, arrays, class helpers, and math-heavy code. | Compile color/pixel primitives before image IO and GUI integration. |
| AggPas | Anti-Grain Geometry port to Pascal. Math-heavy, record-heavy, procedural/object hybrid style. Good numeric-correctness and geometry test. | Compile fixed-point/path/raster core units with a deterministic geometry smoke. |
| PasMP | Parallel-processing library. Good for threading, atomics, generics, callbacks, and scheduler structures. | Compile non-thread-spawning core/generic structures first; run real threading only after the heap/thread contracts are ready. |
| fpGUI | GUI toolkit written in Pascal, lighter than Lazarus LCL. Useful intermediate GUI/component target if full LCL is too much. | Compile base classes and non-window widget definitions before real backend/window code. |

## Heavy Or Later Candidates

| Candidate | Why it is useful | Why later |
| --- | --- | --- |
| Free Pascal RTL | Obvious baseline for core language, system unit, memory, strings, arrays, files, and platform conditionals. | PXX has an own-RTL policy; use as a compatibility oracle/source-shape test, not as code to vendor into `lib/rtl`. |
| FPC FCL packages | Medium-weight ecosystem test: `fcl-base`, `fcl-json`, `fcl-xml`, `fcl-db`, `fcl-image`, streams, RTTI, variants, resources, and generics. | Depends on much more FPC RTL/package surface. Better after smaller library candidates expose the first gaps. |
| Full Lazarus LCL | Maximum GUI/component stress: inheritance, properties, events, component streaming, resources, widgetsets, conditionals. | Very large and platform-heavy. Use fpGUI or targeted Lazarus-generated examples before full LCL. |
| Indy | Huge networking stack and strong Delphi-compatibility torture test: interfaces, class hierarchies, protocols, conditional compilation. | Much larger and messier than Synapse. Let Synapse establish the network/RTL ground first. |
| mORMot 2 | Serious modern Object Pascal codebase. Excellent stress for generics, RTTI, JSON, serialization, interfaces, records, and low-level assumptions. | Deep modern-language and RTL surface. High value, but not an early probe. |
| ZeosLib / ZeosDBO | Database access layer with interfaces, variants, conditional compilation, external bindings, and broad API surface. | Needs database client bindings and a lot of compatibility surface. Use after simpler external-binding libraries. |
| FastMM / memory managers | Low-level, platform-sensitive, pointer-heavy, and allocator-hostile code. Excellent dangerous-corner test. | Only useful once allocator, pointer, thread, and platform contracts are stable enough to diagnose failures. |
| SynEdit | Text editor component/library. Good classes, events, Unicode/string handling, lexers, and UI-adjacent code. | Depends on component/GUI assumptions. Better after fpGUI/LCL-adjacent work progresses. |

## Prioritization

Suggested ladder:

1. **Compact pure-Pascal algorithmic tests:** TRegExpr, DCPcrypt.
2. **Graphics/math without full GUI:** AggPas, BGRABitmap core.
3. **Compatibility/library breadth:** fpGUI, PasMP.
4. **Ecosystem-scale libraries:** FPC FCL slices, Indy, ZeosLib, mORMot 2.
5. **Summit targets:** FPC RTL/FCL breadth, full LCL, memory managers.

Keep Synapse and Pascal Script on their existing tickets. Do not create new
umbrella tickets for them from this list; append discoveries to their current
logs.

## Import Discipline

- Check license and upstream status at import time. Do not infer vendoring
  suitability from this catalog.
- Pin an upstream revision and record it in the candidate manifest.
- Prefer tests with deterministic oracles: known crypto vectors, regex cases,
  JSON/XML round-trips, fixed image checksums, or stdout equality.
- Split actual compiler defects out as Track A tickets; keep missing units,
  shims, PAL surfaces, and owned-library work on Track B.
