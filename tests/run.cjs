// Usage from GearExport: node tests/run.cjs TEMP_NODE_MODULES [V2_1_GearExport.lua]
const path = require('path');
const { spawnSync } = require('child_process');
require('./check_lua.cjs');
require('./check_release.cjs');
require('./check_classic.cjs');
require('./check_retail.cjs');
require('./check_forever.cjs');
require('./check_icon.cjs');
const cli = path.join(process.argv[2], 'fengari-node-cli', 'src', 'lua-cli.js');
const args = [cli, 'tests/wowsync_test.lua'];
if (process.argv[3]) args.push(process.argv[3]);
const result = spawnSync(process.execPath, args, { encoding: 'utf8' });
if (result.error) process.stderr.write(result.error.message + '\n');
process.stdout.write(result.stdout || '');
process.stderr.write(result.stderr || '');
// Fengari can return exit code 0 for a Lua assertion failure; require the final marker.
if (result.error || result.status !== 0 || result.stderr || !/^PASS: \d+ assertions; 0 gameplay actions\s*$/m.test(result.stdout || '')) {
  process.exitCode = 1;
}
const retail = spawnSync(process.execPath, [cli, 'tests/retail_test.lua'], { encoding: 'utf8' });
if (retail.error) process.stderr.write(retail.error.message + '\n');
process.stdout.write(retail.stdout || '');
process.stderr.write(retail.stderr || '');
if (retail.error || retail.status !== 0 || retail.stderr || !/^PASS: \d+ Retail assertions; 0 gameplay actions\s*$/m.test(retail.stdout || '')) {
  process.exitCode = 1;
}
const forever = spawnSync(process.execPath, [cli, 'tests/forever_test.lua'], { encoding: 'utf8' });
if (forever.error) process.stderr.write(forever.error.message + '\n');
process.stdout.write(forever.stdout || '');
process.stderr.write(forever.stderr || '');
if (forever.error || forever.status !== 0 || forever.stderr || !/^PASS: \d+ Forever assertions; 0 gameplay actions\s*$/m.test(forever.stdout || '')) {
  process.exitCode = 1;
}
