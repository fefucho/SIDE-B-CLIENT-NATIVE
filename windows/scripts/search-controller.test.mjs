import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';

const source = await readFile(new URL('../src/lib/search/controller.ts', import.meta.url), 'utf8');
const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { SearchController } = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);
const song = id => ({ videoId: id, title: id, artists: 'Artist', album: null, duration: null, thumbnail: null, isVideo: false, artistId: null, albumId: null });
const album = id => ({ id, title: id, subtitle: null, thumbnail: null });
function deferred() { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; }

test('a different query discards a late rejection', async () => {
  const first = deferred(); const calls = []; let data;
  const search = new SearchController(async (command, args) => { calls.push({ command, args }); return calls.length === 1 ? first.promise : [song('new')]; }, next => data = next);
  search.setQuery('old'); const old = search.execute('old');
  search.setQuery('new'); await search.execute('new');
  first.reject(new Error('old query failed')); await old;
  assert.deepEqual(data.songs.map(item => item.videoId), ['new']);
  assert.equal(data.error, null); assert.equal(data.isLoading, false);
  assert.deepEqual(calls.map(call => call.args.query), ['old', 'new']);
});

test('reset invalidates pending account-context responses and clears cached results', async () => {
  const pending = deferred(); let data; let count = 0;
  const search = new SearchController(async () => { count++; return count === 1 ? pending.promise : [song('fresh')]; }, next => data = next);
  const old = search.execute('private'); search.reset();
  pending.reject(new Error('old account failed')); await old;
  assert.equal(data.error, null); assert.deepEqual(data.songs, []); assert.equal(data.query, '');
  await search.execute('private'); assert.equal(count, 2); assert.deepEqual(data.songs.map(item => item.videoId), ['fresh']);
});

test('failed searches can retry and successful identical searches use the cache', async () => {
  let attempts = 0; let data;
  const search = new SearchController(async () => { attempts++; if (attempts === 1) throw new Error('temporary'); return [song('ok')]; }, next => data = next);
  await search.execute('radiohead'); assert.equal(data.error, 'temporary'); assert.equal(data.isLoading, false);
  await search.execute('radiohead'); assert.equal(data.error, null); assert.deepEqual(data.songs.map(item => item.videoId), ['ok']);
  await search.execute('radiohead'); assert.equal(attempts, 2);
});

test('mode changes supersede stale requests and repeated mode/query lookups are cached', async () => {
  const pending = deferred(); const calls = []; let data;
  const search = new SearchController(async (command, args) => {
    calls.push({ command, args });
    if (command === 'search_songs') return pending.promise;
    return [album('album-1')];
  }, next => data = next);
  search.setQuery('artist'); const songsRequest = search.execute('artist');
  search.setMode('albums');
  await new Promise(resolve => setTimeout(resolve, 0));
  pending.resolve([song('stale')]); await songsRequest;
  assert.deepEqual(data.albums.map(item => item.id), ['album-1']);
  await search.execute('artist', 'albums');
  assert.equal(calls.filter(call => call.command === 'search_albums').length, 1);
  assert.deepEqual(data.songs, []);
});
