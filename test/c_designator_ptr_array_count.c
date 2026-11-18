/* `[k] =` in an unsized array of pointers or structs moves the running index,
   so the array is max index + 1 long: st's colorname table
   (`..., [255] = 0, "#cccccc", ...`) was sized by its element count and lost
   its default colours, so st drew no text.
   bug-c-a-designator-in-a-pointer-array-initialiser-is-not-counted */
#include <stdio.h>

static const char *names[] = {
	"black", "red3", "green3",
	[6] = 0,
	"#cccccc", "#555555", "gray90", "black",
};
struct kv { int k; const char *v; };
static const struct kv tab[] = { { 1, "a" }, [4] = { 5, "e" }, { 6, "f" } };
enum { E_A = 2, E_B = 7 };
static const char *byenum[] = { [E_B] = "seven", [E_A] = "two", "three" };

int main(void)
{
	int i, n = sizeof names / sizeof names[0];
	const char *loc[] = { "x", [3] = "w", "v" };
	printf("%d %d %d %d\n", n, (int)(sizeof tab / sizeof tab[0]),
	       (int)(sizeof byenum / sizeof byenum[0]), (int)(sizeof loc / sizeof loc[0]));
	for (i = 0; i < n; i++) printf("%s ", names[i] ? names[i] : "-");
	printf("\n%d %s %d %s %d\n", tab[4].k, tab[5].v, tab[2].k, byenum[3], byenum[0] == 0);
	printf("%s %s %d\n", byenum[7], loc[4], loc[1] == 0);
	return 0;
}
