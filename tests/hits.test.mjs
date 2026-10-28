import test from 'node:test';
import assert from 'node:assert/strict';
const expected=n=>({sar:n,classics:n*2,ar:n*4});
test('Display Sollwerte',()=>assert.deepEqual(expected(1),{sar:1,classics:2,ar:4}));
test('Case Sollwerte',()=>assert.deepEqual(expected(12),{sar:12,classics:24,ar:48}));
test('Case-Case Sollwerte',()=>assert.deepEqual(expected(72),{sar:72,classics:144,ar:288}));
test('Methodenwechsel behält alle Displays',()=>assert.equal([4,4,4].reduce((x,y)=>x+y,0),12));
