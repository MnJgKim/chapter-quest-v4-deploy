import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const files = [
  'app/tests/isolated-postgres-makeup-audit.sql',
  'app/tests/isolated-approved-weekday-release-gate.sql',
  'app/tests/isolated-atomic-weekday-scheduler.sql',
  'app/tests/isolated-approved-chapter-queue.sql',
];
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
