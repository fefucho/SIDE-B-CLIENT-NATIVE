<script lang="ts">
  import type { AlbumCardDto, BrowseCardDto, SongDto } from "$lib/types";
  import ArtistCredits from "$lib/components/ArtistCredits.svelte";
  import type { SearchData, SearchMode } from "$lib/search/controller";
  import { createMenuHandlers } from "$lib/menu/hooks";

  interface Props {
    data: SearchData;
    backendReady: boolean;
    currentTrackId: string | null;
    isPlaying: boolean;
    onSubmit: (query: string, mode: SearchMode) => void;
    onQueryChange: (query: string) => void;
    onModeChange: (mode: SearchMode) => void;
    onQuickSearch: (query: string) => void;
    onPlaySong: (song: SongDto) => void;
    onOpenAlbum: (album: AlbumCardDto) => void;
    onOpenArtist?: (id: string) => void;
  }

  let { data, backendReady, currentTrackId, isPlaying, onSubmit, onQueryChange, onModeChange, onQuickSearch, onPlaySong, onOpenAlbum, onOpenArtist }: Props = $props();
  const createMenu = createMenuHandlers();
  function submit(event: SubmitEvent) { event.preventDefault(); onSubmit(data.query, data.mode); }
  function play(song: SongDto) { onPlaySong(song); }
  function openSongAlbum(song: SongDto, id: string) {
    onOpenAlbum({ id, title: song.album ?? '', subtitle: song.artists, thumbnail: song.thumbnail });
  }
</script>

<div class="search-view-container" data-primary-search>
  <nav class="mode-tabs" aria-label="Modo de búsqueda">
    <button type="button" class="tab-btn" class:active={data.mode === "songs"} disabled={!backendReady || data.isLoading} onclick={() => onModeChange("songs")}>
      <svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor"><path d="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z" /></svg>
      Canciones
    </button>
    <button type="button" class="tab-btn" class:active={data.mode === "albums"} disabled={!backendReady || data.isLoading} onclick={() => onModeChange("albums")}>
      <svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 14.5c-2.49 0-4.5-2.01-4.5-4.5S9.51 7.5 12 7.5s4.5 2.01 4.5 4.5-2.01 4.5-4.5 4.5zm0-5.5c-.55 0-1 .45-1 1s.45 1 1 1 1-.45 1-1-.45-1-1-1z" /></svg>
      Álbumes
    </button>
  </nav>

  <section class="search-section">
    <form class="search-form" onsubmit={submit}>
      <div class="input-wrapper">
        <svg class="search-icon" viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <circle cx="11" cy="11" r="8"></circle><line x1="21" y1="21" x2="16.65" y2="16.65"></line>
        </svg>
        <input id="search-input" type="text" data-primary-search aria-label="Buscar en el catálogo" placeholder={data.mode === "songs" ? "Buscar canciones o artistas..." : "Buscar álbumes o discografías..."} value={data.query} oninput={(event) => onQueryChange(event.currentTarget.value)} disabled={!backendReady || data.isLoading} />
        {#if data.query && !data.isLoading}
          <button type="button" class="clear-btn" onclick={() => onQueryChange("")} aria-label="Limpiar búsqueda">&times;</button>
        {/if}
      </div>
      <button type="submit" class="submit-btn" disabled={!backendReady || data.isLoading || !data.query.trim()}>{data.isLoading ? "Buscando..." : "Buscar"}</button>
    </form>
    <div class="quick-chips">
      <span class="chip-label">Sugerencias:</span>
      <button type="button" class="chip" disabled={!backendReady || data.isLoading} onclick={() => onQuickSearch("Daft Punk")}>Daft Punk</button>
      <button type="button" class="chip" disabled={!backendReady || data.isLoading} onclick={() => onQuickSearch("Radiohead")}>Radiohead</button>
      <button type="button" class="chip" disabled={!backendReady || data.isLoading} onclick={() => onQuickSearch("Gustavo Cerati")}>Gustavo Cerati</button>
    </div>
  </section>

  <section class="content-section">
    {#if data.isLoading}
      <div class="state-container loading-state"><div class="spinner"></div><p>{data.mode === "songs" ? "Buscando canciones en YouTube Music..." : "Buscando álbumes en YouTube Music..."}</p></div>
    {:else if data.error}
      <div class="state-container error-state"><div class="error-icon">!</div><h3>Error al consultar el catálogo</h3><p class="error-msg">{data.error}</p><button type="button" class="retry-btn" onclick={() => onSubmit(data.lastSearchedQuery || data.query, data.mode)}>Reintentar búsqueda</button></div>
    {:else if data.mode === "songs"}
      {#if data.hasSearchedSongs && data.songs.length === 0}
        <div class="state-container empty-state"><div class="empty-icon">&#128269;</div><h3>Sin resultados</h3><p>No se encontraron canciones para «<strong>{data.lastSearchedQuery}</strong>».</p></div>
      {:else if !data.hasSearchedSongs}
        <div class="state-container prompt-state"><div class="prompt-icon">&#9835;</div><h3>Búsqueda de canciones</h3><p>Ingresá una búsqueda arriba para probar la resolución de canciones de <code>sideb-core</code>.</p></div>
      {:else}
        <div class="results-header"><h2>Resultados para «{data.lastSearchedQuery}»</h2><span class="count-badge">{data.songs.length} canciones</span></div>
        <div class="song-list">
          {#each data.songs as song (song.videoId)}
            {@const menu = createMenu(() => ({ kind: 'song', song }), { view: 'search_results' })}
            <div class="song-row" class:is-active-track={currentTrackId === song.videoId} role="group" aria-label={`Canción: ${song.title}`} oncontextmenu={menu.onContextMenu}>
              <button type="button" class="thumb-container song-play" onclick={() => play(song)} onkeydown={menu.onKeyDown} aria-label={`Reproducir ${song.title}`} title="Reproducir canción">{#if song.thumbnail}<img src={song.thumbnail} alt="" class="thumb-img" loading="lazy" />{:else}<span class="thumb-fallback">&#9835;</span>{/if}</button>
              <div class="meta-col"><button type="button" class="song-title song-play" title={song.title} onclick={() => play(song)} onkeydown={menu.onKeyDown}>{song.title}</button><div class="song-credits"><ArtistCredits artistRuns={song.artistRuns} artists={song.artists} artistId={song.artistId} onOpenArtist={onOpenArtist} album={song.album} albumId={song.albumId} onOpenAlbum={(id) => openSongAlbum(song, id)} /></div></div>
              <div class="extra-col">{#if currentTrackId === song.videoId && isPlaying}<span class="tag-playing">&#9658; SONANDO</span>{/if}{#if song.isVideo}<span class="tag-video">VIDEO</span>{/if}{#if song.duration}<span class="song-duration">{song.duration}</span>{/if}</div>
            </div>
          {/each}
        </div>
      {/if}
    {:else}
      {#if data.hasSearchedAlbums && data.albums.length === 0}
        <div class="state-container empty-state"><div class="empty-icon">&#128269;</div><h3>Sin resultados</h3><p>No se encontraron álbumes para «<strong>{data.lastSearchedQuery}</strong>».</p></div>
      {:else if !data.hasSearchedAlbums}
        <div class="state-container prompt-state"><div class="prompt-icon">&#128191;</div><h3>Búsqueda de álbumes</h3><p>Ingresá una búsqueda arriba para explorar discografías y abrir su detalle con pistas reales.</p></div>
      {:else}
        <div class="results-header"><h2>Álbumes para «{data.lastSearchedQuery}»</h2><span class="count-badge">{data.albums.length} álbumes</span></div>
        <div class="album-grid">
          {#each data.albums as album (album.id)}
            {@const card: BrowseCardDto = { kind: 'album', id: album.id, title: album.title, subtitle: album.subtitle, thumbnail: album.thumbnail, duration: null }}
            {@const menu = createMenu(() => ({ kind: 'album', card }), { view: 'search_results' })}
            <button type="button" class="album-card" onclick={() => onOpenAlbum(album)} oncontextmenu={menu.onContextMenu} onkeydown={menu.onKeyDown} title={`Ver detalle de ${album.title}`}>
              <div class="album-card-cover">{#if album.thumbnail}<img src={album.thumbnail} alt={album.title} class="album-card-img" loading="lazy" />{:else}<div class="album-card-fallback">&#128191;</div>{/if}</div>
              <div class="album-card-info"><span class="album-card-title">{album.title}</span>{#if album.subtitle}<span class="album-card-sub">{album.subtitle}</span>{/if}</div>
            </button>
          {/each}
        </div>
      {/if}
    {/if}
  </section>
</div>

<style>
  .search-view-container {
    display: flex;
    flex-direction: column;
    gap: 1.4rem;
  }

  .mode-tabs {
    display: flex;
    justify-content: center;
    gap: 0.5rem;
    background: #1e1e24;
    padding: 0.3rem;
    border-radius: 12px;
    border: 1px solid #2e2e38;
    max-width: 300px;
    margin: 0 auto;
  }

  .tab-btn {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 0.4rem;
    background: transparent;
    border: none;
    color: #9ca3af;
    font-size: 0.9rem;
    font-weight: 600;
    padding: 0.45rem 1rem;
    border-radius: 8px;
    cursor: pointer;
    transition: all 0.15s;
  }

  .tab-btn:hover:not(:disabled) {
    color: #ffffff;
    background: rgba(255, 255, 255, 0.05);
  }

  .tab-btn.active {
    background: #a33d45;
    color: #ffffff;
    box-shadow: 0 2px 8px rgba(163, 61, 69, 0.35);
  }

  .tab-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .search-section {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  .search-form {
    display: flex;
    gap: 0.75rem;
  }

  .input-wrapper {
    flex: 1;
    position: relative;
    display: flex;
    align-items: center;
  }

  .search-icon {
    position: absolute;
    left: 1rem;
    color: #9ca3af;
    pointer-events: none;
  }

  input[type="text"] {
    width: 100%;
    background: #24242a;
    border: 1px solid #3a3a44;
    border-radius: 10px;
    padding: 0.75rem 2.5rem 0.75rem 2.85rem;
    font-size: 1rem;
    color: #ffffff;
    outline: none;
    transition: border-color 0.2s, box-shadow 0.2s;
  }

  input[type="text"]:focus {
    border-color: #a33d45;
    box-shadow: 0 0 0 2px rgba(163, 61, 69, 0.25);
  }

  input[type="text"]:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .clear-btn {
    position: absolute;
    right: 0.75rem;
    background: transparent;
    border: none;
    color: #9ca3af;
    font-size: 1.4rem;
    cursor: pointer;
    line-height: 1;
    padding: 0.2rem 0.4rem;
  }

  .clear-btn:hover {
    color: #ffffff;
  }

  .submit-btn {
    background: #a33d45;
    color: #ffffff;
    border: none;
    border-radius: 10px;
    padding: 0 1.5rem;
    font-size: 0.95rem;
    font-weight: 600;
    cursor: pointer;
    transition: background-color 0.2s;
  }

  .submit-btn:hover:not(:disabled) {
    background: #b74750;
  }

  .submit-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .quick-chips {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    flex-wrap: wrap;
    font-size: 0.85rem;
  }

  .chip-label {
    color: #9ca3af;
  }

  .chip {
    background: #24242a;
    border: 1px solid #3a3a44;
    color: #d1d5db;
    border-radius: 9999px;
    padding: 0.25rem 0.75rem;
    font-size: 0.8rem;
    cursor: pointer;
    transition: all 0.2s;
  }

  .chip:hover:not(:disabled) {
    background: #2f2f38;
    border-color: #a33d45;
    color: #ffffff;
  }

  .chip:disabled {
    opacity: 0.45;
    cursor: not-allowed;
  }

  .content-section {
    min-height: 320px;
  }

  .state-container {
    background: #24242a;
    border: 1px solid #32323a;
    border-radius: 12px;
    padding: 3rem 1.5rem;
    text-align: center;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.75rem;
  }

  .spinner {
    width: 36px;
    height: 36px;
    border: 3px solid rgba(255, 255, 255, 0.1);
    border-top-color: #a33d45;
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }

  .error-icon {
    width: 42px;
    height: 42px;
    border-radius: 50%;
    background: rgba(239, 68, 68, 0.15);
    color: #ef4444;
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: 700;
    font-size: 1.4rem;
  }

  .error-msg {
    color: #fca5a5;
    max-width: 500px;
    font-size: 0.9rem;
    margin: 0;
  }


  .retry-btn {
    background: #a33d45;
    color: #ffffff;
    border: none;
    border-radius: 8px;
    padding: 0.5rem 1.25rem;
    font-size: 0.9rem;
    cursor: pointer;
  }

  .retry-btn:hover {
    background: #b74750;
  }



  .empty-icon, .prompt-icon {
    font-size: 2.5rem;
    opacity: 0.6;
  }

  .results-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 1rem;
    padding: 0 0.25rem;
  }

  .results-header h2 {
    font-size: 1.25rem;
    font-weight: 600;
    margin: 0;
    color: #ffffff;
  }

  .count-badge {
    background: #24242a;
    border: 1px solid #32323a;
    padding: 0.2rem 0.65rem;
    border-radius: 9999px;
    font-size: 0.8rem;
    color: #9ca3af;
  }

  /* Lista de canciones */
  .song-list {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .song-row {
    background: #24242a;
    border: 1px solid #32323a;
    border-radius: 10px;
    padding: 0.65rem 0.9rem;
    display: flex;
    align-items: center;
    gap: 1rem;
    transition: background-color 0.15s, border-color 0.15s;
  }

  .song-row:hover {
    background: #2b2b32;
    border-color: #42424c;
  }

  .thumb-container {
    width: 48px;
    height: 48px;
    border-radius: 6px;
    overflow: hidden;
    flex-shrink: 0;
    background: #1b1b1e;
  }

  .song-play { padding: 0; border: 0; color: inherit; font: inherit; text-align: left; cursor: pointer; }
  .song-play:focus-visible { outline: 2px solid var(--sideb-highlight, #d06c70); outline-offset: 2px; border-radius: 6px; }
  button.thumb-container { display: block; }

  .thumb-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }

  .thumb-fallback {
    width: 100%;
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    color: #6b7280;
    font-size: 1.2rem;
  }

  .meta-col {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 0.15rem;
  }

  .song-title {
    display: block;
    width: 100%;
    padding: 0;
    border: 0;
    background: transparent;
    font-weight: 600;
    color: #ffffff;
    font-size: 0.95rem;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .song-credits { min-width: 0; overflow: hidden; color: #9ca3af; font-size: 0.85rem; line-height: 1.2; white-space: nowrap; }
  .song-credits :global(.artist-credits) { display: flex; }
  .song-credits :global(.credit-link:hover) { color: #fff; }

  .extra-col {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    flex-shrink: 0;
  }

  .tag-video {
    background: #3f3f46;
    color: #e4e4e7;
    font-size: 0.65rem;
    font-weight: 700;
    padding: 0.15rem 0.4rem;
    border-radius: 4px;
    letter-spacing: 0.05em;
  }

  .song-duration {
    font-family: "Cascadia Code", Consolas, monospace;
    font-size: 0.85rem;
    color: #9ca3af;
  }

  /* Grid de Álbumes */
  .album-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(170px, 1fr));
    gap: 1rem;
  }

  .album-card {
    background: #24242a;
    border: 1px solid #32323a;
    border-radius: 12px;
    padding: 0.85rem;
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
    text-align: left;
    cursor: pointer;
    transition: transform 0.15s, background-color 0.15s, border-color 0.15s, box-shadow 0.15s;
    color: inherit;
  }

  .album-card:hover {
    background: #2b2b33;
    border-color: #a33d45;
    transform: translateY(-2px);
    box-shadow: 0 6px 18px rgba(0, 0, 0, 0.4);
  }

  .album-card-cover {
    width: 100%;
    aspect-ratio: 1 / 1;
    border-radius: 8px;
    overflow: hidden;
    background: #1b1b1e;
  }

  .album-card-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }

  .album-card-fallback {
    width: 100%;
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    color: #6b7280;
    font-size: 2.5rem;
  }

  .album-card-info {
    display: flex;
    flex-direction: column;
    gap: 0.2rem;
  }

  .album-card-title {
    font-weight: 600;
    color: #ffffff;
    font-size: 0.95rem;
    line-height: 1.3;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }

  .album-card-sub {
    font-size: 0.8rem;
    color: #9ca3af;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .retry-btn { font-size: 0.7rem; font-weight: 500; color: #ffffff; background: rgba(239, 68, 68, 0.4); border: 1px solid rgba(239, 68, 68, 0.6); padding: 0.1rem 0.45rem; border-radius: 4px; cursor: pointer; }
  .retry-btn:hover { background: rgba(239, 68, 68, 0.65); }
  .is-active-track { background: #252538 !important; border-color: #6366f1 !important; }
  .tag-playing { font-size: 0.65rem; font-weight: 700; color: #818cf8; background: rgba(99, 102, 241, 0.18); padding: 0.15rem 0.4rem; border-radius: 4px; letter-spacing: 0.04em; flex-shrink: 0; }
  .song-row { cursor: pointer; }
  @media (max-width: 640px) {
    .album-grid { grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); }
  }

</style>
