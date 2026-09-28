{ `parallel for` sizes its pool from sched_getaffinity. aarch64 and arm32 used
  sched_SETaffinity's number (122 / 241), the call failed with EINVAL, and the
  pool fell back to 4 workers on every such machine. Under qemu-user the
  affinity mask is the host's, so every target must print what x86-64 prints.
  bug-a-parallel-for-uses-4-workers-on-aarch64-and-arm32-because-it-asks-setaffinity }
program test_parallel_for_worker_count_follows_the_cpu_affinity;
uses palparallel;
begin
  WriteLn(PXXParForWorkers);
end.
