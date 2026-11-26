#ifndef _STDALIGN_H
#define _STDALIGN_H
/* C11 <stdalign.h>. pxx reads _Alignas and _Alignof itself; these are the
   lower-case spellings. (C23 makes alignas/alignof keywords; the macros are
   harmless there.) dhcpcd's dhcp.c includes it for an aligned packet buffer. */
#ifndef __cplusplus
#define alignas _Alignas
#define alignof _Alignof
#define __alignas_is_defined 1
#define __alignof_is_defined 1
#endif
#endif
