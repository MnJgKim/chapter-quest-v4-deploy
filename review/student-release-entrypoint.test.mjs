import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const assets = new URL('../app/public/', import.meta.url);
const html = readFileSync(new URL('index.html', assets), 'utf8');
const scripts = [...html.matchAll(/<script\s+src="([^"]+)"/g)].map(match => match[1]);

test('the versioned student entry point waits for automatic release and only renders server-listed chapters', async () => {
  const apiScript = scripts.find(src => src.startsWith('/js/student-api.js?'));
  assert.equal(apiScript, '/js/student-api.js?v=weekday-release-2');
  assert.ok(scripts.indexOf(apiScript) < scripts.indexOf('/js/student-app.js?v=student-display-1'));
  const script = new URL(apiScript.slice(1), assets);
  const browser = vm.createContext({});
  vm.runInContext(readFileSync(script, 'utf8'), browser);

  let finishScheduler;
  const scheduler = new Promise(resolve => {finishScheduler = resolve;});
  const calls = [];
  const lesson = '70000000-0000-4000-8000-000000000077';
  const {createStudentAPI} = browser.CQStudentAPI;
  const api = createStudentAPI({
    url: 'https://isolated.supabase.co',
    anonKey: 'isolated-public-key',
    getAccessToken: async () => 'isolated-student-token',
    fetchImpl: async (url, request) => {
      const rpc = url.split('/').at(-1);
      assert.equal(request.method, 'POST');
      assert.equal(request.headers.Authorization, 'Bearer isolated-student-token');
      calls.push(rpc);
      if (rpc === 'cq_v4_ensure_today_approved_lesson') return scheduler;
      assert.equal(rpc, 'cq_v4_my_released_chapters');
      if (calls.length === 2) return {ok: true, json: async () => []};
      return {ok: true, json: async () => [{
        chapter_uuid: lesson,
        chapter_title: 'Synthetic Chapter 1',
        lesson_date: '2026-11-24',
        questions: [{kind: 'short', text: 'Synthetic question'}],
      }]};
    },
  });

  const firstLoad = api.assignedChapters();
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(calls, ['cq_v4_ensure_today_approved_lesson']);
  // Even when scheduling returns a UUID, the client must use the gated list.
  finishScheduler({ok: true, json: async () => lesson});
  assert.equal((await firstLoad).length, 0);
  const refreshed = await api.assignedChapters();
  assert.equal(refreshed.length, 1);
  assert.equal(refreshed[0].chapter_uuid, lesson);
  assert.equal(refreshed[0].lesson_date, '2026-11-24');
  assert.deepEqual(calls, [
    'cq_v4_ensure_today_approved_lesson', 'cq_v4_my_released_chapters',
    'cq_v4_ensure_today_approved_lesson', 'cq_v4_my_released_chapters',
  ]);
});
