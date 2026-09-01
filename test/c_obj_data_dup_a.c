/* POSITIVE CONTROL, half one. Two TUs each with a bare `int x;` are a genuine
   duplicate definition under -fno-common, which gcc has defaulted to since
   GCC 10 -- so the link MUST fail. Producing that failure is conformance, not
   collateral damage: the link succeeding is the defect, because two objects
   silently get private slots for what the source says is one object.
   This is the counterpart of the `file_local` row: that one guards against
   exporting too MUCH, this one against exporting too little or reviving
   -fcommon by emitting SHN_COMMON. */
int x;
int dup_a(void) { return x; }
