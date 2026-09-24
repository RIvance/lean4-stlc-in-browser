import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import createModule from '../generated/stlc.mjs';

const executable = fileURLToPath(new URL('../../.lake/build/bin/lambdacalculus', import.meta.url));
const corpusExecutable = fileURLToPath(new URL('../../.lake/build/bin/stlcTests', import.meta.url));
const corpus = spawnSync(corpusExecutable, ['--corpus'], { encoding: 'utf8' });
assert.equal(corpus.status, 0, corpus.stderr);
const cases = JSON.parse(corpus.stdout);
const module = await createModule();
assert.equal(module._stlc_init(), 0);

function evaluate(source, fuel = 100_000, checkOnly = false) {
  const pointer = module.ccall('stlc_request', 'number', ['string', 'number', 'number', 'number'], [
    source, Buffer.byteLength(source), fuel, Number(checkOnly),
  ]);
  assert.notEqual(pointer, 0);
  try { return JSON.parse(module.UTF8ToString(pointer)); }
  finally { module._free(pointer); }
}

for (const item of cases) {
  test(`native/Wasm parity: ${item.name}`, () => {
    const args = ['--json', '--fuel', String(item.fuel), ...(item.checkOnly ? ['--check'] : [])];
    const native = spawnSync(executable, args, { input: item.source, encoding: 'utf8' });
    assert.equal(native.status, item.error ? 1 : 0, native.stderr);
    const result = evaluate(item.source, item.fuel, item.checkOnly);
    assert.deepEqual(result, JSON.parse(native.stdout));
    if (item.error) assert.equal(result.diagnostic.phase, item.error);
    else {
      assert.equal(result.value ?? '', item.value);
      assert.equal(result.type, item.type);
    }
  });
}

test('one module can process repeated requests and recover after errors', () => {
  for (let i = 0; i < 300; i++) {
    assert.equal(evaluate('((x: Nat) ⇒ x + 1)(41)').value, '42');
    assert.equal(evaluate('false(1)').status, 'error');
  }
});
