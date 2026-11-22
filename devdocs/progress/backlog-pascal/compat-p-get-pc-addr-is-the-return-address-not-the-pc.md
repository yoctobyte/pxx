---
slug: compat-p-get-pc-addr-is-the-return-address-not-the-pc
track: P
prio: 20
type: compat
status: backlog
created: 2026-11-22
found-by: claude-pxx (writing test_get_pc_addr_xtensa_windowed against FPC)
summary: "pxx's get_pc_addr returns the CURRENT FUNCTION'S return address (the same node as C's __builtin_return_address(0); feature-system-stack-frame-intrinsics). FPC 3.2.2 returns the PC at the call to get_pc_addr, a point inside the current function. In `function Where: Pointer; begin Where := get_pc_addr end;` called twice, FPC gives the same value both times and pxx two different ones."
---

# get_pc_addr: the return address in pxx, the PC in FPC

Measured 2026-11-22 with test/test_get_pc_addr_xtensa_windowed.pas built by
fpc 3.2.2 (without `noinline`, which FPC does not parse):

    fpc:  distinct FALSE increasing FALSE / stable FALSE near TRUE
    pxx:  distinct TRUE increasing TRUE   / stable TRUE near TRUE

FPC's `get_pc_addr` is "the current program counter". The value a frame
walk uses is `get_caller_addr(get_frame)`. pxx folded both meanings into
`get_pc_addr` when it lowered it as AN_PCADDR, the node C's
`__builtin_return_address(0)` also uses.

The fix would split the two: get_pc_addr becomes the current PC, and
AN_PCADDR stays as C's return address. test_stack_frame_intrinsics_b270
relies on today's meaning ("return address into Inner's caller") and would
change with it. Not done, because nothing known depends on either meaning.
