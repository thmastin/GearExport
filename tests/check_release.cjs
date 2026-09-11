// Final release invariants; used by run.cjs in addition to runtime regression tests.
const fs = require('fs');
const crypto = require('crypto');
const assert = require('assert');
const bankHash = crypto.createHash('sha256').update(fs.readFileSync('BankCleanup.lua')).digest('hex');
assert.strictEqual(bankHash, '54cbbd5ea9f8ac6b0307a475b270220bd7ea190e2ec6755950df34f50b67a6ba', 'BankCleanup must remain byte-for-byte unchanged');
const readme = fs.readFileSync('README.md', 'utf8');
const marker = '# Using WoWSync with an LLM';
assert(readme.includes(marker), 'Missing README LLM section');
const prompts = readme.slice(readme.indexOf(marker));
for (const heading of ['General prompt', 'Gear analysis', 'Inventory/bank cleanup',
  'Trainer/ability planning', 'Profession planning', 'Economy/gold planning',
  'Leveling/next-step planning', 'Custom prompt template']) {
  const start = prompts.indexOf('### ' + heading + '\n');
  assert(start >= 0, 'Missing prompt: ' + heading);
  const end = prompts.indexOf('\n### ', start + 1);
  const section = prompts.slice(start, end < 0 ? undefined : end);
  assert(section.includes('```text\n') && section.includes('[PASTE THE COMPLETE WOWSYNC v1 BLOCK HERE]'), 'Prompt must be ready to copy: ' + heading);
}
assert(!/Torahn|Voodan|Tenivard/i.test(prompts), 'Public prompts must remain generic');
console.log('PASS: BankCleanup baseline hash; general, six focused, and custom README prompts');
