/* Definitions for c_incomplete_extern_distinct_a.c (see there). */
struct cipher { const char *name; int keylen; };
struct mode { const char *name; };
struct hash { const char *name; int len; };

const struct cipher nocipher = { "none-cipher", 0 };
const struct mode mode_none = { "none-mode" };
const struct hash nohash = { "none-hash", 20 };
