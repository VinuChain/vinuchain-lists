/**
 * Corrected prototype pollution test
 */

const { safeParse } = require('../../scripts/utils/safe-json');

console.log('CORRECTED Prototype Pollution Test\n');
console.log('='.repeat(60));

// Clean check - create new object to test pollution
function testPollution(jsonString, testKey) {
  console.log(`\nTest: ${jsonString.substring(0, 60)}...`);

  // Parse the malicious JSON
  const parsed = safeParse(jsonString);

  // Create a NEW empty object to check if prototype was polluted
  const testObj = {};

  console.log(`  Parsed object:`, parsed);
  console.log(`  Has dangerous key as own property:`, parsed.hasOwnProperty('__proto__') || parsed.hasOwnProperty('constructor'));
  console.log(`  New object has pollution:`, testKey in testObj);
  console.log(`  New object[${testKey}]:`, testObj[testKey]);

  if (testObj[testKey] !== undefined) {
    console.log(`  ❌ CRITICAL: Prototype pollution successful!`);
    return false;
  } else if (parsed.__proto__ && typeof parsed.__proto__ === 'object' && Object.keys(parsed.__proto__).length > 0) {
    console.log(`  ❌ WARNING: Object has __proto__ property (but no pollution)`);
    return false;
  } else {
    console.log(`  ✅ SAFE: No prototype pollution`);
    return true;
  }
}

// Test cases
const tests = [
  { json: '{"__proto__": {"polluted": true}}', key: 'polluted' },
  { json: '{"constructor": {"prototype": {"polluted2": true}}}', key: 'polluted2' },
  { json: '{"a": {"__proto__": {"polluted3": true}}}', key: 'polluted3' },
  { json: '{"__proto__": {"isAdmin": true}}', key: 'isAdmin' },
  { json: '{"normal": "value"}', key: 'normal' },
];

let allSafe = true;
for (const test of tests) {
  const safe = testPollution(test.json, test.key);
  allSafe = allSafe && safe;
}

console.log('\n' + '='.repeat(60));
if (allSafe) {
  console.log('✅ ALL TESTS PASSED - Prototype pollution protection working');
} else {
  console.log('❌ TESTS FAILED - Prototype pollution protection broken');
}
console.log('='.repeat(60));
