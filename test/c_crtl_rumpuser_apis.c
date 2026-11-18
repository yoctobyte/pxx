/* The pthread, clock and allocator calls NetBSD's librumpuser makes that crtl
   lacked: thread-specific keys with destructors, pthread_exit, attributes
   (detached), spin locks, pthread_setname_np, clock_nanosleep and clockid_t,
   posix_memalign / aligned_alloc / memalign and their free and realloc.
   Output is compared with gcc + glibc. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <malloc.h>
#include <stdint.h>
#include <time.h>
#include <errno.h>
#include <pthread.h>

static pthread_key_t key;
static int dtor_sum;
static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_spinlock_t spin;
static long spin_count;
static volatile int detached_done;

static void dtor(void *v)
{
	pthread_mutex_lock(&mu);
	dtor_sum += *(int *)v;
	pthread_mutex_unlock(&mu);
	free(v);
}

static void deep(int n)
{
	if (n == 0)
		pthread_exit((void *)(intptr_t)(100 + *(int *)pthread_getspecific(key)));
	deep(n - 1);
}

static void *worker(void *arg)
{
	int id = (int)(intptr_t)arg, i;
	int *mine = malloc(sizeof *mine);
	*mine = id;
	pthread_setspecific(key, mine);
	for (i = 0; i < 20000; i++) {
		pthread_spin_lock(&spin);
		spin_count++;
		pthread_spin_unlock(&spin);
	}
	if (*(int *)pthread_getspecific(key) != id)
		return (void *)-1;
	if (id & 1)
		deep(5);                 /* pthread_exit from a nested frame */
	return (void *)(intptr_t)(200 + id);
}

static void *detached(void *arg)
{
	(void)arg;
	__sync_fetch_and_add(&detached_done, 1);
	return 0;
}

int main(void)
{
	pthread_t t[4], d;
	pthread_attr_t at;
	void *ret;
	int i, st, rc;
	size_t ss;
	void *p;
	char *q;
	struct timespec now, until, rel;
	clockid_t clk = CLOCK_MONOTONIC;

	/* keys, spin, pthread_exit */
	pthread_key_create(&key, dtor);
	pthread_spin_init(&spin, PTHREAD_PROCESS_PRIVATE);
	for (i = 0; i < 4; i++)
		pthread_create(&t[i], 0, worker, (void *)(intptr_t)(i + 1));
	for (i = 0; i < 4; i++) {
		pthread_join(t[i], &ret);
		printf("join %d -> %ld\n", i + 1, (long)(intptr_t)ret);
	}
	printf("spin %ld dtor_sum %d\n", spin_count, dtor_sum);
	printf("main key %p\n", pthread_getspecific(key));
	printf("trylock %d", pthread_spin_trylock(&spin));
	printf(" %d\n", pthread_spin_trylock(&spin));
	pthread_spin_unlock(&spin);
	pthread_spin_destroy(&spin);
	pthread_key_delete(key);
	printf("setspecific deleted %d\n", pthread_setspecific(key, &i) == EINVAL);

	/* attributes */
	pthread_attr_init(&at);
	pthread_attr_getdetachstate(&at, &st);
	printf("default detach %d\n", st);
	printf("set bad %d\n", pthread_attr_setdetachstate(&at, 7));
	pthread_attr_setdetachstate(&at, PTHREAD_CREATE_DETACHED);
	pthread_attr_getdetachstate(&at, &st);
	pthread_attr_setstacksize(&at, 256 * 1024);
	pthread_attr_getstacksize(&at, &ss);
	printf("detach %d stack %lu\n", st, (unsigned long)ss);
	pthread_create(&d, &at, detached, 0);
	pthread_attr_destroy(&at);
	pthread_setname_np(pthread_self(), "rumpuser");
	while (!detached_done) { struct timespec z = { 0, 1000000 }; nanosleep(&z, 0); }
	printf("detached ran %d\n", detached_done);

	/* aligned allocation */
	rc = posix_memalign(&p, 64, 100);
	printf("pm64 %d aligned %d\n", rc, ((uintptr_t)p & 63) == 0);
	memset(p, 0xab, 100);
	printf("usable ok %d\n", malloc_usable_size(p) >= 100);
	q = realloc(p, 300);
	printf("realloc keeps %d %d\n", (unsigned char)q[0], (unsigned char)q[99]);
	free(q);
	rc = posix_memalign(&p, 4096, 10);
	printf("pm4096 %d aligned %d\n", rc, ((uintptr_t)p & 4095) == 0);
	free(p);
	printf("pm bad %d\n", posix_memalign(&p, 24, 10));
	p = aligned_alloc(256, 512);
	printf("aa %d\n", ((uintptr_t)p & 255) == 0);
	free(p);
	p = memalign(32, 33);
	printf("ma %d\n", ((uintptr_t)p & 31) == 0);
	free(p);
	for (i = 0; i < 1000; i++) {             /* the pool survives the churn */
		void *a, *b = malloc(24);
		posix_memalign(&a, 128, (size_t)i + 1);
		((char *)a)[i] = 1;
		free(b);
		free(a);
	}
	printf("churn ok\n");

	/* clock_nanosleep */
	clock_gettime(clk, &now);
	until = now;
	until.tv_nsec += 20000000;
	if (until.tv_nsec >= 1000000000L) { until.tv_nsec -= 1000000000L; until.tv_sec++; }
	rc = clock_nanosleep(clk, TIMER_ABSTIME, &until, 0);
	clock_gettime(clk, &now);
	printf("abs %d reached %d\n", rc,
	       now.tv_sec > until.tv_sec || (now.tv_sec == until.tv_sec && now.tv_nsec >= until.tv_nsec));
	printf("past %d\n", clock_nanosleep(clk, TIMER_ABSTIME, &(struct timespec){ 0, 0 }, 0));
	rel.tv_sec = 0; rel.tv_nsec = 1000000;
	printf("rel %d bad %d\n", clock_nanosleep(CLOCK_REALTIME, 0, &rel, 0),
	       clock_nanosleep(clk, 0, &(struct timespec){ 0, 2000000000L }, 0));
	printf("sizes key %d spin %d attr %d clockid %d\n", (int)sizeof(pthread_key_t),
	       (int)sizeof(pthread_spinlock_t), (int)sizeof(pthread_attr_t), (int)sizeof(clockid_t));

#ifdef RUA_MAIN_RETURNS
	/* --system-libs: glibc's pthread_exit on the main thread needs the
	   unwind buffer __libc_start_main sets up, and pxx's entry is its own.
	   bug-c-system-libs-pthread-exit-on-the-main-thread-crashes */
	return 0;
#else
	pthread_exit(0);                        /* main: the process ends with 0 */
#endif
}
