/* SPDX-License-Identifier: Zlib */
/* POSIX pthread_*_t types from <sys/types.h> alone, in a struct; sizes against
   gcc + glibc. Row c_ptty26. feature-crtl-pthread-types-in-sys-types-h */
#include <stdio.h>
#include <sys/types.h>
struct w { pthread_mutex_t m; pthread_t t; pthread_once_t o; pthread_key_t k; pthread_cond_t c; pthread_rwlock_t rw; pthread_attr_t a; pthread_spinlock_t s; };
int main(void){ printf("%zu %zu %zu %zu %zu %zu %zu\n", sizeof(struct w), sizeof(pthread_mutex_t), sizeof(pthread_t), sizeof(pthread_cond_t), sizeof(pthread_rwlock_t), sizeof(pthread_attr_t), sizeof(pthread_spinlock_t)); return 0; }
