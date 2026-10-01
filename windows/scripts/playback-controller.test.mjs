import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';

const source = await readFile(new URL('../src/lib/player/controller.ts', import.meta.url), 'utf8');
const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { PlaybackController, emptyPlaybackData } = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);

function deferred() {
  let resolve; let reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
function state(generation, options = {}) {
  return { ...emptyPlaybackData(), generation, ...options,
    queue: { ...emptyPlaybackData().queue, ...(options.queue ?? {}) } };
}
const song = (videoId) => ({ videoId, title: videoId, artists: 'Artist', thumbnail: null, duration: '3:21' });
async function settle() { await new Promise((resolve) => setTimeout(resolve, 0)); }

test('queue metadata survives RPC normalization and queue actions preserve freshest progress', async () => {
  const listeners = new Map(); let published; const enqueued = deferred(); let args;
  const player = new PlaybackController(async (command, input) => {
    if (command === 'get_playback_state') return state(2, { position: 10, isPlaying: true });
    if (command === 'enqueue_tracks') { args = input; return enqueued.promise; }
    throw new Error(command);
  }, async (event, handler) => { listeners.set(event, handler); return () => {}; }, next => published = next);
  await player.connect();
  const artistRuns = [{ text: 'Daft Punk', id: 'UC-daft' }, { text: 'Pharrell Williams', id: 'UC-pharrell' }];
  const pending = player.enqueue([{ ...song('v'), artistId: 'artist', artistRuns, albumId: 'album', album: 'Album' }], 'next');
  assert.equal(args.items[0].artistId, 'artist'); assert.equal(args.items[0].albumId, 'album'); assert.equal(args.items[0].duration, 201);
  assert.deepEqual(args.items[0].artistRuns, artistRuns);
  listeners.get('playback-progress')({ payload: { generation: 2, position: 12, duration: 201 } });
  enqueued.resolve(state(2, { position: 10, queue: { revision: 1, items: args.items } }));
  await pending;
  assert.equal(published.state.position, 12); assert.equal(published.state.queue.items[0].album, 'Album');
  published.state.queue.items[0].artistRuns[1].id = 'changed-by-consumer';
  assert.equal(player.snapshot.state.queue.items[0].artistRuns[1].id, 'UC-pharrell');
});

test('play, radio and retry preserve individual artist links and album metadata', async () => {
  const artistRuns = [{ text: 'Daft Punk', id: 'UC-daft' }, { text: 'Pharrell Williams', id: 'UC-pharrell' }];
  const track = { ...song('dance'), artists: 'Daft Punk & Pharrell Williams', artistRuns,
    album: 'Random Access Memories', albumId: 'MPRE-album', artistId: 'UC-daft' };
  const calls = [];
  const player = new PlaybackController(async (command, args) => {
    calls.push({ command, args });
    return state(2, { currentTrack: { ...track, duration: 201 }, queue: { items: [{ ...track, entryId: 'occurrence', duration: 201 }], currentIndex: 0 } });
  }, async () => () => {}, () => {});
  await player.playSong(track);
  assert.deepEqual(calls[0].args.artistRuns, artistRuns);
  assert.deepEqual(calls[0].args.queueItems[0].artistRuns, artistRuns);
  assert.equal(calls[0].args.album, track.album);
  await player.retry();
  assert.deepEqual(calls[1].args.artistRuns, artistRuns);
  assert.equal(calls[1].args.queueEntryId, 'occurrence');
  await player.startRadio(track);
  assert.deepEqual(calls[2].args.song.artistRuns, artistRuns);
  assert.equal(calls[2].args.song.albumId, track.albumId);
});

test('radio metadata arriving after progress enriches the current track without rewinding it', async () => {
  const listeners = new Map(); const radio = deferred();
  const track = { ...song('dance'), duration: 201 };
  const entry = { ...track, entryId: 'seed' };
  const player = new PlaybackController(async command => {
    if (command === 'get_playback_state') return state(3, { currentTrack: track, position: 20, isPlaying: true,
      queue: { items: [entry], currentIndex: 0 } });
    if (command === 'retry_radio') return radio.promise;
    throw new Error(command);
  }, async (event, handler) => { listeners.set(event, handler); return () => {}; }, () => {});
  await player.connect();
  const pending = player.retryRadio();
  listeners.get('playback-progress')({ payload: { generation: 3, position: 22, duration: 201 } });
  const metadata = { artistRuns: [{ text: 'Daft Punk', id: 'UC-daft' }, { text: 'Pharrell Williams', id: 'UC-pharrell' }],
    album: 'Random Access Memories', albumId: 'MPRE-album' };
  radio.resolve(state(3, { currentTrack: { ...track, ...metadata }, position: 20,
    queue: { items: [{ ...entry, ...metadata }], currentIndex: 0, revision: 1 } }));
  await pending;
  assert.equal(player.snapshot.state.position, 22);
  assert.equal(player.snapshot.state.isPlaying, true);
  assert.equal(player.snapshot.state.currentTrack.album, metadata.album);
  assert.deepEqual(player.snapshot.state.currentTrack.artistRuns, metadata.artistRuns);
  assert.equal(player.snapshot.state.queue.items[0].entryId, 'seed');
});
test('failed queue mutation reports to caller without marking playing audio as failed', async () => {
  let published;
  const player = new PlaybackController(async command => {
    if (command === 'get_playback_state') return state(1, { isPlaying: true });
    throw new Error('cannot remove current');
  }, async () => () => {}, next => published = next);
  await player.connect(); await assert.rejects(player.removeQueueEntry('current'), /cannot remove/);
  assert.equal(published.state.isPlaying, true); assert.equal(published.error, null);
});
test('selecting a duplicate song passes its stable occurrence ID to Rust', async () => {
  let args;
  const items = ['first', 'second'].map(entryId => ({ ...song('same'), entryId, duration: 201 }));
  const player = new PlaybackController(async (command, input) => {
    if (command === 'get_playback_state') return state(1, { queue: { items, currentIndex: 0 } });
    args = input; return state(2, { queue: { items, currentIndex: 1 } });
  }, async () => () => {}, () => {});
  await player.connect(); await player.playQueueIndex(1);
  assert.equal(args.queueEntryId, 'second'); assert.equal(args.preserveQueue, true); assert.equal(args.queueItems, null);
});

test('initial snapshot cannot replace a newer playback state event', async () => {
  const snapshot = deferred(); const listeners = new Map(); let published;
  const player = new PlaybackController(async (command) => {
    assert.equal(command, 'get_playback_state'); return snapshot.promise;
  }, async (name, handler) => {
    listeners.set(name, handler); return () => {};
  }, (next) => { published = next; });

  const connecting = player.connect();
  await settle();
  listeners.get('playback-state-changed')({ payload: state(4, { isPlaying: true, position: 24, currentTrack: { ...song('new'), duration: 201 } }) });
  snapshot.resolve(state(4, { currentTrack: { ...song('old'), duration: 1 } }));
  await connecting;
  assert.equal(published.state.generation, 4);
  assert.equal(published.state.currentTrack.videoId, 'new');
  assert.equal(published.state.isPlaying, true);
  assert.equal(published.state.position, 24);
});

test('newer play request wins when RPC replies arrive out of order', async () => {
  const calls = []; let published;
  const player = new PlaybackController((command, args) => {
    const wait = deferred(); calls.push({ command, args, ...wait }); return wait.promise;
  }, async () => () => {}, (next) => { published = next; });
  const older = player.playSong(song('old'));
  const newer = player.playSong(song('new'));
  assert.equal(calls[0].args.queueItems[0].duration, 201);
  assert.deepEqual(calls[1].args.queueSource, { kind: 'song', id: 'new', title: 'new' });
  calls[1].resolve(state(2, { currentTrack: { ...song('new'), duration: 201 } }));
  await newer;
  calls[0].resolve(state(1, { currentTrack: { ...song('old'), duration: 201 } }));
  await older;
  assert.equal(published.state.currentTrack.videoId, 'new');
  assert.equal(published.error, null);
});

test('stale play failure does not publish or reject after a newer play succeeds', async () => {
  const calls = []; let published;
  const player = new PlaybackController((command) => {
    const wait = deferred(); calls.push(wait); return wait.promise;
  }, async () => () => {}, (next) => { published = next; });
  const old = player.playSong(song('old'));
  const current = player.playSong(song('current'));
  calls[1].resolve(state(7, { currentTrack: { ...song('current'), duration: 10 } }));
  await current;
  calls[0].reject(new Error('old failure'));
  await old;
  assert.equal(published.state.currentTrack.videoId, 'current');
  assert.equal(published.error, null);
});

test('only latest rapid toggle and volume replies can replace state', async () => {
  const calls = []; let published;
  const player = new PlaybackController((command, args) => {
    const wait = deferred(); calls.push({ command, args, ...wait }); return wait.promise;
  }, async () => () => {}, (next) => { published = next; });
  const firstToggle = player.toggle(); const secondToggle = player.toggle();
  assert.deepEqual(calls.slice(0, 2).map((call) => call.command), ['resume_playback', 'resume_playback']);
  calls[1].resolve(state(2, { isPlaying: true })); await secondToggle;
  calls[0].resolve(state(1, { isPlaying: false })); await firstToggle;
  assert.equal(published.state.isPlaying, true);

  const firstVolume = player.setVolume(10); const secondVolume = player.setVolume(35);
  calls[3].resolve(state(2, { volume: 35 })); await secondVolume;
  calls[2].resolve(state(2, { volume: 10 })); await firstVolume;
  assert.equal(published.state.volume, 35);
});

test('stale state events cannot overwrite generation or queue revision', () => {
  let listener; let published;
  const player = new PlaybackController(async () => state(0), async (name, handler) => {
    if (name === 'playback-state-changed') listener = handler;
    return () => {};
  }, (next) => { published = next; });
  const connect = player.connect();
  return settle().then(() => {
    listener({ payload: state(3, { queue: { revision: 8 } }) });
    listener({ payload: state(3, { queue: { revision: 7 }, isPlaying: true }) });
    assert.equal(published.state.queue.revision, 8);
    assert.equal(published.state.isPlaying, false);
    return connect;
  });
});

test('dispose unlistens subscriptions that resolve after teardown', async () => {
  const registrations = [deferred(), deferred()]; let index = 0; let calls = 0;
  const player = new PlaybackController(async () => state(0), async () => registrations[index++].promise, () => {});
  const connecting = player.connect();
  await player.dispose();
  registrations.forEach((registration) => registration.resolve(() => { calls++; }));
  await connecting;
  assert.equal(calls, 2);
});

test('account invalidation drops command callbacks without mutating player snapshot', async () => {
  const response = deferred(); let published;
  const player = new PlaybackController(async (command) => command === 'next_track' ? response.promise : state(0), async () => () => {}, (next) => { published = next; });
  const request = player.next();
  player.invalidatePending();
  response.resolve(state(8, { currentTrack: { ...song('from-old-account'), duration: 201 } }));
  await request;
  assert.equal(published.state.currentTrack, null);
  assert.equal(published.state.generation, 0);
});

test('progress applies only to current generation and skips loading states', () => {
  let progress; let stateChanged; let published;
  const player = new PlaybackController(async () => state(5), async (name, handler) => {
    if (name === 'playback-progress') progress = handler;
    if (name === 'playback-state-changed') stateChanged = handler;
    return () => {};
  }, (next) => { published = next; });
  const connecting = player.connect();
  return settle().then(async () => {
    progress({ payload: { generation: 4, position: 20, duration: 99 } });
    assert.equal(published.state.position, 0);
    progress({ payload: { generation: 5, position: 20, duration: 99 } });
    assert.equal(published.state.position, 20);
    assert.equal(published.state.duration, 99);
    stateChanged({ payload: state(5, { isLoading: true, position: 20, duration: 99 }) });
    progress({ payload: { generation: 5, position: 25, duration: 99 } });
    assert.equal(published.state.position, 20);
    await connecting;
  });
});
