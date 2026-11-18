/* -fcommon: tentative definitions are COMMON in an x86-64 object, so the main
   may define them too (NetBSD net_stub.c); initialised and static ones stay put.
   feature-c-fcommon-tentative-definitions-are-common-symbols */
struct pl { void *a, *b; };
struct pl ifnet_pslist;
int ipsec_debug;
int ipsec_used = 1;
static int priv;
void (*altq_input)(int);
int stub_get(void) { return ipsec_debug + priv + (ifnet_pslist.a != 0) + (altq_input != 0); }
