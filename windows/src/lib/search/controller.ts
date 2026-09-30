import type { AlbumCardDto, SongDto } from '../types';

export type SearchMode = 'songs' | 'albums';
export type SearchRpc = <T>(command: string, args?: Record<string, unknown>) => Promise<T>;

export interface SearchData {
  query: string;
  mode: SearchMode;
  lastSearchedQuery: string;
  songs: SongDto[];
  albums: AlbumCardDto[];
  isLoading: boolean;
  error: string | null;
  hasSearchedSongs: boolean;
  hasSearchedAlbums: boolean;
}

export function emptySearchData(): SearchData {
  return { query: '', mode: 'songs', lastSearchedQuery: '', songs: [], albums: [], isLoading: false, error: null,
    hasSearchedSongs: false, hasSearchedAlbums: false };
}

function errorMessage(error: unknown) {
  if (error && typeof error === 'object' && 'message' in error && typeof error.message === 'string') return error.message;
  if (typeof error === 'string') return error;
  return 'Error al consultar el catálogo.';
}

/** Search state boundary: requests are guarded by generation and revision, so reset or query/mode changes discard late replies. */
export class SearchController {
  private data = emptySearchData();
  private publish: (data: SearchData) => void;
  private generation = 0;
  private revision = 0;
  private caches: { songs: Map<string, SongDto[]>; albums: Map<string, AlbumCardDto[]> } = { songs: new Map(), albums: new Map() };

  constructor(private rpc: SearchRpc, publish: (data: SearchData) => void) { this.publish = publish; }

  private emit() {
    this.publish({ ...this.data, songs: [...this.data.songs], albums: [...this.data.albums] });
  }

  setQuery(query: string) {
    if (query !== this.data.query) {
      ++this.revision;
      this.data = { ...this.data, query, isLoading: false, error: null };
      this.emit();
    }
  }

  setMode(mode: SearchMode) {
    if (mode === this.data.mode) return;
    ++this.revision;
    this.data = { ...this.data, mode, isLoading: false, error: null };
    this.emit();
    if (this.data.query.trim()) void this.execute(this.data.query, mode);
  }

  /** Invalidate pending work while preserving visible results; useful when leaving search or changing account context. */
  invalidate() {
    ++this.revision;
    this.data = { ...this.data, isLoading: false };
    this.emit();
  }

  reset() {
    ++this.generation;
    ++this.revision;
    this.caches = { songs: new Map(), albums: new Map() };
    this.data = emptySearchData();
    this.emit();
  }

  restore(snapshot: SearchData) {
    ++this.revision;
    this.data = { ...snapshot, songs: [...snapshot.songs], albums: [...snapshot.albums], isLoading: false };
    this.emit();
    if (snapshot.isLoading && snapshot.lastSearchedQuery) void this.execute(snapshot.lastSearchedQuery, snapshot.mode);
  }

  async execute(targetQuery: string, mode: SearchMode = this.data.mode) {
    const query = targetQuery.trim();
    if (!query) return;
    // Exact in-flight repeats are a no-op; a different query/mode always supersedes old work.
    if (this.data.isLoading && this.data.lastSearchedQuery === query && this.data.mode === mode) return;
    const generation = this.generation;
    const revision = ++this.revision;
    const current = () => generation === this.generation && revision === this.revision;
    this.data = { ...this.data, query, mode, lastSearchedQuery: query, isLoading: false, error: null };
    const cached = this.caches[mode].get(query);
    if (cached) {
      this.data = mode === 'songs'
        ? { ...this.data, songs: [...cached as SongDto[]], hasSearchedSongs: true }
        : { ...this.data, albums: [...cached as AlbumCardDto[]], hasSearchedAlbums: true };
      this.emit();
      return;
    }
    this.data.isLoading = true;
    if (mode === 'songs') this.data.hasSearchedSongs = true;
    else this.data.hasSearchedAlbums = true;
    this.emit();
    try {
      if (mode === 'songs') {
        const results = await this.rpc<SongDto[]>('search_songs', { query });
        if (current()) { this.caches.songs.set(query, results); this.data.songs = [...results]; }
      } else {
        const results = await this.rpc<AlbumCardDto[]>('search_albums', { query });
        if (current()) { this.caches.albums.set(query, results); this.data.albums = [...results]; }
      }
    } catch (error) {
      if (current()) {
        this.data.error = errorMessage(error);
        if (mode === 'songs') this.data.songs = [];
        else this.data.albums = [];
      }
    } finally {
      if (current()) { this.data.isLoading = false; this.emit(); }
    }
  }
}
