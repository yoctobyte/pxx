/* A function-pointer global initialised with a CAST function name binds the
   address (rump: `rump_proc_vfs_init = (void *)nullop`, nil at boot).
   bug-c-a-cast-function-name-initialiser-of-a-function-pointer-global-is-dropped */
struct proc;
typedef void (*rump_proc_vfs_init_fn)(struct proc *);
int nullop(void *);
rump_proc_vfs_init_fn pv = (void *)nullop;
void (*pf)(void) = (void *)nullop;
int (*pd)(void *) = nullop;
void *pc = (void *)nullop;
