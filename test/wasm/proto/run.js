// Run the hand-compiled prototype. Prints the trace one integer per line — the
// same shape writeln() gives, so it diffs directly against the native run.
// Then asserts the two invariants a trace cannot show:
//   * the shadow stack is balanced ($sp back at its initial value) even though
//     two frames exited via the unwind path;
//   * no exception is left armed at the end.
const fs = require('fs');
const buf = fs.readFileSync(process.argv[2]);
const out = [];
const inst = new WebAssembly.Instance(new WebAssembly.Module(buf), {
  env: { print: (n) => out.push(n) },
});
const sp0 = inst.exports.sp.value;
inst.exports.main();
process.stdout.write(out.join('\n') + '\n');
const sp1 = inst.exports.sp.value;
const pend = inst.exports.exc_pending.value;
let bad = 0;
if (sp1 !== sp0) { console.error(`FAIL shadow stack leaked: ${sp0} -> ${sp1}`); bad = 1; }
if (pend !== 0)  { console.error(`FAIL exception left armed: ${pend}`); bad = 1; }
if (!bad) console.error(`ok  $sp balanced at ${sp1}, no exception armed`);
process.exit(bad);
