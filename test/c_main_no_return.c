/* C99 5.1.2.2.3: reaching the closing brace of main is `return 0`.
 *
 * pxx returned whatever the uninitialised result slot held. The output was
 * always right, so the only visible symptom was the EXIT CODE -- and the value
 * differed between compiler builds, which is what stack garbage looks like.
 * c-testsuite 00206 and 00212 both fail this way and nothing else.
 *
 * The three shapes that reach the brace: straight through, out of a nested
 * block, and through a goto to a label at the end. Each must exit 0.
 * bug-c-main-without-return-exits-with-stack-garbage
 */
#include <stdio.h>

static int noise(int n)
{
	/* leave something non-zero in the return register and on the stack just
	   below main's frame, so a slot that is never written keeps it */
	int pad[8];
	int i;
	for (i = 0; i < 8; i++)
		pad[i] = 0x5EED + n + i;
	return pad[n & 7];
}

int main(void)
{
	int k = noise(3);

	printf("%d\n", k != 0);
	if (k) {
		int inner = noise(5);
		printf("%d\n", inner != 0);
		{
			int deeper = noise(1);
			printf("%d\n", deeper != 0);
			goto tail;
		}
	}
	printf("unreachable\n");
tail:
	printf("tail\n");
}
