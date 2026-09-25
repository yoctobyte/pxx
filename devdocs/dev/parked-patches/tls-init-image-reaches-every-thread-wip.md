# tls-init-image-reaches-every-thread-wip.patch

Parked 2026-09-25 at the wrap-up, from frankS's stash "tls init image WIP"
(2026-09-24, base 0fa4b9cfbc; still applies cleanly at the tree it was parked
on). The bug: a C `__thread int x = 5;` is initialised by a store in main's
prologue, so every thread except main reads 0. The patch writes a thread-local
INIT IMAGE in BSS (defs.inc BSS_TLS_IMAGE, TLS_SLOT_INIT_IMAGE = 13), makes
CompilePendingGlobalInits copy each initialised thread-local into it, and
makes every new block copy the image: the clone legs in thread_emit.inc and
PxxPthreadStart in palthread.pas. It adds a gcc-oracle test,
test/c_thread_local_initialiser_reaches_every_thread.c (main writes 6 first,
so the rows tell an image copy from a copy of main's block, and a grandchild
is checked), with x86-64/aarch64/arm32 rows.

HOW FAR IT GOT: work in progress. The stash was never run to a green
fixedpoint that I can find recorded, and no ticket named
bug-c-an-initialised-thread-local-reads-zero-in-every-thread-but-main exists
in the tree. Rebuild, run the new rows and `make compiler/pascal26` before
trusting any of it.
