const fs = require('fs');
const assert = require('assert');

const classicToc = fs.readFileSync('GearExport-ClassicEra.toc', 'utf8');
const classicAlias = fs.readFileSync('GearExport-Classic.toc', 'utf8');
const tbcToc = fs.readFileSync('GearExport.toc', 'utf8');
assert(/## Interface:\s*11509/.test(classicToc), 'Classic Era TOC must target interface 11509');
assert.strictEqual(classicAlias, classicToc, 'Classic flavor TOC alias must match Classic Era package');
assert(/## Interface:\s*20506/.test(tbcToc), 'TBC TOC interface must remain 20506');
for (const toc of [classicToc, tbcToc]) {
  assert(toc.includes('WoWSyncCompat.lua'), 'Both TOCs must load WoWSyncCompat');
  for (const file of ['WoWSyncCore.lua', 'WoWSyncCollectors.lua', 'WoWSyncRender.lua', 'WoWSyncUI.lua']) {
    assert(toc.includes(file), `${file} missing from TOC`);
  }
}
assert(fs.readFileSync('WoWSyncCompat.lua', 'utf8').includes('ITEM_DATA_LOAD_RESULT'),
  'Compatibility layer must handle delayed item data');
console.log('PASS: Classic Era TOC, shared files, and compatibility hooks');
