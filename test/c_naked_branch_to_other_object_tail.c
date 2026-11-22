typedef struct { long rip, rsp; } buf_t;
unsigned int tail_elsewhere(buf_t *b) { return (unsigned)(b->rsp & 15) + 7; }
