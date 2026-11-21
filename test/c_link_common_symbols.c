/* -fcommon tentative definitions linked by pxx --link: one name in two
   objects is ONE variable (the larger size and alignment win), a real
   definition in a third object displaces the commons, and an unshared
   common is zero. ld's rule; NetBSD's rump kernel relies on it. Built three
   times: -DCM_A, -DCM_B, and plain (the main). */
#ifdef CM_A
int cm_shared;
long cm_wide[2];
int cm_defined;
void cm_a_set(void) { cm_shared = 7; cm_wide[1] = 5; cm_defined += 1; }
#elif defined(CM_B)
int cm_shared;
long cm_wide[4];
int cm_defined = 40;
int cm_only_b;
void cm_b_set(void) { cm_shared += 10; cm_wide[3] = 9; cm_defined += 1; }
int cm_b_only(void) { return cm_only_b; }
#else
#include <stdio.h>
extern int cm_shared;
extern long cm_wide[4];
extern int cm_defined;
void cm_a_set(void);
void cm_b_set(void);
int cm_b_only(void);
int main(void)
{
    cm_a_set();
    cm_b_set();
    printf("%d %ld %ld %d %d\n", cm_shared, cm_wide[1], cm_wide[3], cm_defined, cm_b_only());
    return 0;
}
#endif
