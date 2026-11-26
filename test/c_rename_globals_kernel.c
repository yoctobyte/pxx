/* --rename-globals=rumpns_ --rename-globals-keep=rump,__ : NetBSD's rump rename.
   Every global this object defines or uses becomes rumpns_<name> except the
   kept prefixes; locals stay. Linked against c_rename_globals_host.c, which
   supplies the renamed names, so a wrong relocation shows as a wrong number. */
extern int memcpy_user(int);
extern int rumpuser_thing(int);
int shared_counter = 3;
static int local_helper(int x) { return x + shared_counter; }
__attribute__((weak)) int weak_hook(int x) { return x * 100; }
int kernel_entry(int x) { return local_helper(memcpy_user(x)) + rumpuser_thing(x) + weak_hook(x); }
int __keep_me(void) { return 7; }
