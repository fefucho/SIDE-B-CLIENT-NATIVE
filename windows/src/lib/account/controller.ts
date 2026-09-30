import type { BrowseCardDto } from '../types';
import type { AccountSongDto as SongDto, AccountPlaylistDto as PlaylistDetailDto } from './types';

export type LibraryTab = 'songs' | 'playlists' | 'albums' | 'artists';
type Channel = LibraryTab | 'history' | 'likes';
type SongPage = { items: SongDto[]; continuation: string | null };
type HistoryGroup = { title: string; items: SongDto[] };
export type AccountRpc = <T>(command: string, args?: Record<string, unknown>) => Promise<T>;
export interface AccountData {
  loggedIn: boolean; tab: LibraryTab;
  songs: SongDto[]; playlists: BrowseCardDto[]; albums: BrowseCardDto[]; artists: BrowseCardDto[];
  history: HistoryGroup[]; songContinuation: string | null;
  playlist: PlaylistDetailDto | null; playlistLoading: boolean; playlistLoadingMore: boolean; playlistError: string | null;
  loadingMore: boolean; loading: Record<Channel, boolean>; errors: Record<Channel, string | null>;
  likedIds: Set<string>; pendingIds: Set<string>; actionError: string | null;
}
export function emptyAccountData(loggedIn = false): AccountData {
  return { loggedIn, tab: 'songs', songs: [], playlists: [], albums: [], artists: [], history: [],
    songContinuation: null, playlist: null, playlistLoading: false, playlistLoadingMore: false,
    playlistError: null, loadingMore: false,
    loading: { songs: false, playlists: false, albums: false, artists: false, history: false, likes: false },
    errors: { songs: null, playlists: null, albums: null, artists: null, history: null, likes: null },
    likedIds: new Set(), pendingIds: new Set(), actionError: null };
}
function message(error: unknown, fallback: string) {
  return error && typeof error === 'object' && 'message' in error && typeof error.message === 'string' ? error.message : fallback;
}
/** Preserve repeat tracks in playlists; only occurrence IDs identify duplicate entries. */
export function appendSongs(existing: SongDto[], incoming: SongDto[]) {
  const seen = new Set(existing.flatMap(song => song.setVideoId ? [song.setVideoId] : []));
  return [...existing, ...incoming.filter(song => {
    if (!song.setVideoId) return true;
    if (seen.has(song.setVideoId)) return false;
    seen.add(song.setVideoId); return true;
  })];
}

/** One account boundary shared by sidebar, collection screens and current-song actions. */
export class AccountController {
  private data = emptyAccountData();
  private generation = 0;
  private requests = new Map<string, number>();
  private usedSongTokens = new Set<string>();
  private usedPlaylistTokens = new Set<string>();
  private likedPlaylist: PlaylistDetailDto | null = null;
  private likesLoaded = false;
  private likeOverrides = new Map<string, boolean>();
  private published: (data: AccountData) => void;
  constructor(private rpc: AccountRpc, publish: (data: AccountData) => void) { this.published = publish; }
  private emit() { this.published({ ...this.data, loading: { ...this.data.loading }, errors: { ...this.data.errors }, likedIds: new Set(this.data.likedIds), pendingIds: new Set(this.data.pendingIds) }); }
  private ticket(key: string) {
    const generation = this.generation;
    const revision = (this.requests.get(key) ?? 0) + 1; this.requests.set(key, revision);
    return () => generation === this.generation && revision === this.requests.get(key) && this.data.loggedIn;
  }
  reset(loggedIn: boolean) {
    ++this.generation; this.requests.clear(); this.usedSongTokens.clear(); this.usedPlaylistTokens.clear();
    this.likeOverrides.clear(); this.likesLoaded = false; this.likedPlaylist = null;
    this.data = emptyAccountData(loggedIn); this.emit();
  }
  setTab(tab: LibraryTab) { this.data.tab = tab; this.emit(); void this.load(tab); }
  async refreshPlaylist(id: string) {
    if (id === 'LM') { this.likedPlaylist = null; this.likesLoaded = false; this.likeOverrides.clear(); }
    await this.openPlaylist(id);
    if (id === 'LM') await this.hydrateLikes();
  }
  async initialize() { if (this.data.loggedIn) await Promise.allSettled([this.load('playlists'), this.load('albums'), this.hydrateLikes()]); }
  async load(channel: LibraryTab | 'history') {
    if (!this.data.loggedIn) return;
    const valid = this.ticket(channel); this.data.loading[channel] = true; this.data.errors[channel] = null;
    if (channel === 'songs') this.data.loadingMore = false;
    this.emit();
    try {
      if (channel === 'songs') {
        const result = await this.rpc<SongPage>('get_library_songs');
        if (valid()) { this.data.songs = result.items; this.data.songContinuation = result.continuation; this.usedSongTokens.clear(); }
      } else if (channel === 'history') {
        const result = await this.rpc<HistoryGroup[]>('get_history'); if (valid()) this.data.history = result;
      } else {
        const result = await this.rpc<BrowseCardDto[]>(`get_library_${channel}`); if (valid()) this.data[channel] = result;
      }
    } catch (error) { if (valid()) this.data.errors[channel] = message(error, 'No se pudo cargar tu colección.'); }
    finally { if (valid()) { this.data.loading[channel] = false; this.emit(); } }
  }
  async loadMoreSongs() {
    const token = this.data.songContinuation;
    if (!this.data.loggedIn || !token || this.data.loadingMore || this.data.loading.songs || this.usedSongTokens.has(token)) return;
    const valid = this.ticket('songs'); this.data.loadingMore = true; this.data.errors.songs = null; this.emit();
    try {
      const page = await this.rpc<SongPage>('get_playlist_continuation', { token });
      if (valid()) {
        this.usedSongTokens.add(token); this.data.songs = appendSongs(this.data.songs, page.items);
        this.data.songContinuation = page.continuation && !this.usedSongTokens.has(page.continuation) ? page.continuation : null;
      }
    } catch (error) { if (valid()) this.data.errors.songs = message(error, 'No se pudieron cargar más canciones.'); }
    finally { if (valid()) { this.data.loadingMore = false; this.emit(); } }
  }
  async hydrateLikes() {
    if (!this.data.loggedIn || this.data.loading.likes || this.likesLoaded) return;
    const valid = this.ticket('likes'); this.data.loading.likes = true; this.data.errors.likes = null; this.emit();
    try {
      const playlist = await this.rpc<PlaylistDetailDto>('get_playlist', { playlistId: 'LM' });
      if (!valid()) return;
      this.likedPlaylist = playlist;
      const ids = new Set(playlist.items.map(song => song.videoId));
      const publishIds = () => {
        const next = new Set(ids);
        for (const [id, liked] of this.likeOverrides) { if (liked) next.add(id); else next.delete(id); }
        this.data.likedIds = next; this.emit();
      };
      publishIds();
      let token = playlist.continuation; const used = new Set<string>();
      // Hydrate all pages: an unloaded older like must not appear unliked in another view.
      while (token && !used.has(token) && valid()) {
        used.add(token);
        const page = await this.rpc<SongPage>('get_playlist_continuation', { token });
        if (!valid()) return;
        for (const song of page.items) ids.add(song.videoId);
        publishIds();
        token = page.continuation;
      }
      if (valid()) {
        for (const [id, liked] of this.likeOverrides) { if (liked) ids.add(id); else ids.delete(id); }
        this.data.likedIds = ids; this.likesLoaded = true;
      }
    } catch (error) { if (valid()) this.data.errors.likes = message(error, 'No se pudieron cargar tus Me Gusta.'); }
    finally { if (valid()) { this.data.loading.likes = false; this.emit(); } }
  }
  async openPlaylist(id: string) {
    this.ticket('playlist');
    this.data.playlist = null; this.data.playlistLoading = true; this.data.playlistError = null;
    this.data.playlistLoadingMore = false; this.usedPlaylistTokens.clear(); this.emit();
    if (!this.data.loggedIn && id === 'LM') { this.data.playlistLoading = false; this.emit(); return; }
    // Public playlists also work as guest; generation and request still guard the result.
    const generation = this.generation; const revision = this.requests.get('playlist');
    const same = () => generation === this.generation && revision === this.requests.get('playlist');
    try {
      const playlist = id === 'LM' && this.likedPlaylist ? this.likedPlaylist : await this.rpc<PlaylistDetailDto>('get_playlist', { playlistId: id });
      if (same()) { this.data.playlist = playlist; if (id === 'LM') { for (const song of playlist.items) this.data.likedIds.add(song.videoId); } }
    } catch (error) { if (same()) this.data.playlistError = message(error, 'No se pudo cargar la playlist.'); }
    finally { if (same()) { this.data.playlistLoading = false; this.emit(); } }
  }
  async loadMorePlaylist() {
    const playlist = this.data.playlist; const token = playlist?.continuation;
    if (!playlist || !token || this.data.playlistLoadingMore || this.usedPlaylistTokens.has(token)) return;
    const generation = this.generation; const revision = this.requests.get('playlist');
    const same = () => generation === this.generation && revision === this.requests.get('playlist') && this.data.playlist?.id === playlist.id;
    this.data.playlistLoadingMore = true; this.data.playlistError = null; this.emit();
    try {
      const page = await this.rpc<SongPage>('get_playlist_continuation', { token });
      if (same()) {
        this.usedPlaylistTokens.add(token);
        this.data.playlist = { ...this.data.playlist!, items: appendSongs(this.data.playlist!.items, page.items), continuation: page.continuation && !this.usedPlaylistTokens.has(page.continuation) ? page.continuation : null };
        if (playlist.id === 'LM') for (const song of page.items) this.data.likedIds.add(song.videoId);
      }
    } catch (error) { if (same()) this.data.playlistError = message(error, 'No se pudieron cargar más canciones.'); }
    finally { if (same()) { this.data.playlistLoadingMore = false; this.emit(); } }
  }
  private async mutate(key: string, action: () => Promise<unknown>, commit: () => void) {
    if (!this.data.loggedIn || this.data.pendingIds.has(key)) return false;
    const generation = this.generation; this.data.pendingIds.add(key); this.data.actionError = null; this.emit();
    try { await action(); if (generation !== this.generation) return false; commit(); return true; }
    catch (error) { if (generation === this.generation) this.data.actionError = message(error, 'No se pudo guardar el cambio.'); return false; }
    finally { if (generation === this.generation) { this.data.pendingIds.delete(key); this.emit(); } }
  }
  async toggleLike(song: Pick<SongDto, 'videoId'>) {
    const generation = this.generation;
    // Wait for complete hydration before deciding LIKE vs INDIFFERENT.
    if (!this.likesLoaded && !this.data.likedIds.has(song.videoId)) { await this.hydrateLikes(); if (!this.likesLoaded) { this.data.actionError = this.data.errors.likes; this.emit(); return; } }
    if (generation !== this.generation || !this.data.loggedIn) return;
    const liked = !this.data.likedIds.has(song.videoId);
    const changed = await this.mutate(song.videoId, () => this.rpc('rate_song', { videoId: song.videoId, rating: liked ? 'LIKE' : 'INDIFFERENT' }), () => {
      this.likeOverrides.set(song.videoId, liked); if (liked) this.data.likedIds.add(song.videoId); else this.data.likedIds.delete(song.videoId);
      this.likedPlaylist = null;
      if (!liked && this.data.playlist?.id === 'LM') this.data.playlist = { ...this.data.playlist, items: this.data.playlist.items.filter(item => item.videoId !== song.videoId) };
    });
    if (changed && generation === this.generation && this.data.playlist?.id === 'LM' && liked) await this.openPlaylist('LM');
  }
  async toggleSaved(song: SongDto) {
    const library = song.library; const token = library?.inLibrary ? library.removeToken : library?.addToken;
    if (!token) return;
    const saved = !library!.inLibrary;
    const changed = await this.mutate(song.videoId, () => this.rpc('apply_song_library_action', { token }), () => {
      const update = (item: SongDto) => item.videoId === song.videoId ? { ...item, library: { ...(item.library ?? library!), inLibrary: saved } } : item;
      this.data.songs = this.data.songs.map(update);
      if (this.data.playlist) this.data.playlist = { ...this.data.playlist, items: this.data.playlist.items.map(update) };
    });
    if (changed) await this.load('songs');
  }
  async togglePlaylistLibrary() {
    const playlist = this.data.playlist; if (!playlist || playlist.id === 'LM' || playlist.owned) return;
    const changed = await this.mutate(`playlist:${playlist.id}`, () => this.rpc('toggle_album_library', { playlistId: playlist.id, save: !playlist.inLibrary }), () => {
      if (this.data.playlist?.id === playlist.id) this.data.playlist = { ...this.data.playlist, inLibrary: !playlist.inLibrary };
    });
    if (changed) await this.load('playlists');
  }
  async createPlaylist(title: string, description: string) {
    if (!this.data.loggedIn) throw new Error('Iniciá sesión para crear una playlist.');
    const generation = this.generation;
    await this.rpc<string>('create_playlist', { title, description });
    if (generation === this.generation) await this.load('playlists');
  }
}
