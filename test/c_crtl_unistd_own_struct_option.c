/* A program's own `struct option` beside <unistd.h>, as git's
   parse-options.h has one: glibc declares getopt's `struct option` and
   getopt_long in <getopt.h> only, so this is valid C there. pxx's <unistd.h>
   declared them too, and git's apply.c read `opt->value` from getopt's
   struct ("no member named 'value"). getopt itself stays in <unistd.h>.
   bug-crtl-unistd-h-declares-getopts-struct-option */
#include <unistd.h>
#include <stdio.h>
#include <stddef.h>

struct option {
	int type;
	const char *long_name;
	void *value;
	size_t precision;
};

static int parse(const struct option *opt, const char *arg)
{
	int *v = opt->value;
	*v = arg[0] - '0';
	return 0;
}

int main(int argc, char **argv)
{
	int n = 0, c, seen = 0;
	struct option o = { 1, "count", &n, sizeof(int) };
	char *av[] = { "prog", "-x", "-y", "7", NULL };

	parse(&o, "4");
	printf("own struct option: %s %d %zu %zu\n", o.long_name, n, o.precision,
	       sizeof(struct option));
	(void)argc; (void)argv;
	while ((c = getopt(4, av, "xy:")) != -1)
		seen = seen * 10 + (c == 'x' ? 1 : (optarg[0] - '0'));
	printf("getopt from <unistd.h>: %d optind=%d\n", seen, optind);
	return 0;
}
