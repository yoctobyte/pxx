/* An object must not require an external that only dead code called: a
   header static inline nobody uses keeps no slot relocation, so the link
   does not need never_defined (rump: pmap_pv_remove, vm_map_lock, ...).
   bug-c-objects-require-externals-only-dead-code-called */
int never_defined(int);
static inline int unused_helper(int x) { return never_defined(x) + 1; }
int live_fn(int x) { return x * 3; }
