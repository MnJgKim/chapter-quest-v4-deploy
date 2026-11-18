import { readFileSync, readdirSync } from 'node:fs';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const files = readdirSync('app/tests')
  .filter(name => name.startsWith('isolated-') && name.endsWith('.sql'))
  .map(name => `app/tests/${name}`);
test('isolated SQL files have no malformed DO $ anonymous blocks', () => {
  for (const file of files) {
    const sql = readFileSync(file, 'utf8');
    assert.doesNotMatch(sql, /\bDO \$(?=\s*\n)/, file);
    assert.doesNotMatch(sql, /\bEND \$;/, file);
    const openings = [...sql.matchAll(/\bDO (\$[A-Za-z_]*\$)/g)].map(m => m[1]);
    for (const tag of new Set(openings)) {
      const count = sql.split(tag).length - 1;
      assert.equal(count % 2, 0, `${file}: unmatched ${tag}`);
    }
  }
});
