<script lang="ts">
  import { onMount, tick } from "svelte";
  import Sidebar from "$lib/components/sidebar/Sidebar.svelte";
  import PlayerBar from "$lib/components/player/PlayerBar.svelte";
  import HomeView from "$lib/components/home/HomeView.svelte";
  import AlbumDetailView from "$lib/components/detail/AlbumDetailView.svelte";
  import ArtistDetailView from "$lib/components/detail/ArtistDetailView.svelte";
  import CatalogView from "$lib/components/detail/CatalogView.svelte";
  import LibraryView from "$lib/components/library/LibraryView.svelte";
  import PlaylistDetailView from "$lib/components/detail/PlaylistDetailView.svelte";
  import HistoryView from "$lib/components/library/HistoryView.svelte";
  import { AccountController, emptyAccountData } from "$lib/account/controller";
  import { sectionIdentity } from "$lib/home/presentation";
  import FullscreenNowPlaying from "$lib/components/fullscreen/FullscreenNowPlaying.svelte";
  import { invoke } from "@tauri-apps/api/core";
  import { listen, type UnlistenFn } from "@tauri-apps/api/event";
  import type {
    SongDto,
    AlbumCardDto,
    AlbumDetailDto,
    ArtistDetailDto,
    BrowseCardDto,
    HomeSectionDto,
    HomePageDto,
    BackendStatusDto,
    AuthStatusDto,
    CommandError,
    PlaybackStateDto,
    PlaybackProgressDto,
  } from "$lib/types";

  type PrimaryNav = "home" | "search" | "library" | "likes" | "history";
  type SearchMode = "songs" | "albums";
  type ActiveView = "feed" | "search_results" | "album_detail" | "artist_detail" | "catalog" | "library" | "playlist_detail" | "history";

  let primaryNav = $state<PrimaryNav>("home");
  let searchMode = $state<SearchMode>("songs");
  let activeView = $state<ActiveView>("feed");
  let sidebarCollapsed = $state(false);
  let isFullscreenOpen = $state(false);
  let accountData = $state(emptyAccountData());
  const account = new AccountController((command, args) => invoke(command, args), data => { accountData = data; });
  let lastPlaylistId = $state<string | null>(null);

  // Estado Home
  let homePage = $state<HomePageDto | null>(null);
  let activeChipParams = $state<string | null>(null);
  let isHomeLoading = $state(false);
  let homeError = $state<string | null>(null);
  let isHomeLoadingMore = $state(false);
  let homeMoreError = $state<string | null>(null);
  let usedHomeTokens = new Set<string>();

  // Estado Búsqueda
  let query = $state("");
  let lastSearchedQuery = $state("");
  let songs = $state<SongDto[]>([]);
  let albums = $state<AlbumCardDto[]>([]);
  let isSearchLoading = $state(false);
  let searchError = $state<string | null>(null);
  let hasSearchedSongs = $state(false);
  let hasSearchedAlbums = $state(false);

  // Estado Detalle de Álbum
  let selectedAlbum = $state<AlbumDetailDto | null>(null);
  let lastAlbumBrowseId = $state<string | null>(null);
  let isAlbumLoading = $state(false);
  let albumError = $state<string | null>(null);
  let selectedArtist = $state<ArtistDetailDto | null>(null);
  let lastArtistBrowseId = $state<string | null>(null);
  let isArtistLoading = $state(false);
  let artistError = $state<string | null>(null);
  let catalogItems = $state<BrowseCardDto[]>([]);
  let catalogTarget = $state<{id: string; params: string | null; title: string} | null>(null);
  let isCatalogLoading = $state(false);
  let catalogError = $state<string | null>(null);
  type NavigationSnapshot = {
    view: ActiveView; primary: PrimaryNav; scroll: number;
    album: AlbumDetailDto | null; albumId: string | null; albumError: string | null;
    artist: ArtistDetailDto | null; artistId: string | null; artistError: string | null;
    catalog: BrowseCardDto[]; target: typeof catalogTarget; catalogError: string | null;
    playlistId: string | null;
  };
  let navigationHistory: NavigationSnapshot[] = [];

  // Estado Backend
  let backendStatus = $state<BackendStatusDto | null>(null);
  let statusError = $state<string | null>(null);
  let isRetryingInit = $state(false);
  let authStatus = $state<AuthStatusDto>({ state: "guest", name: null, email: null, thumbnail: null, message: null });

  // Estado Reproductor (W06/W07)
  let playbackState = $state<PlaybackStateDto>({
    isPlaying: false,
    isLoading: false,
    isEnded: false,
    position: 0,
    duration: 0,
    volume: 100,
    currentTrack: null,
    error: null,
    generation: 0,
    queue: { items: [], currentIndex: null, source: null, revision: 0 },
  });
  let playbackError = $state<string | null>(null);
  const playerBarState = $derived({ ...playbackState, error: playbackError || playbackState.error });

  let homeRequestId = 0;
  let searchRequestId = 0;
  let albumRequestId = 0;
  let artistRequestId = 0;
  let catalogRequestId = 0;
  let sessionRevision = 0;
  let playSongRequestId = 0;

  function applyAuthStatus(next: AuthStatusDto) {
    const changedAccount = (next.state === "guest" || next.state === "ready")
      && (authStatus.state !== next.state || authStatus.email !== next.email);
    authStatus = next;
    if (changedAccount) {
      ++homeRequestId;
      ++searchRequestId;
      ++albumRequestId;
      ++artistRequestId;
      ++catalogRequestId;
      ++sessionRevision;
      ++playSongRequestId;
      account.reset(next.state === "ready");
      lastPlaylistId = null;
      homePage = null;
      songs = [];
      albums = [];
      selectedAlbum = null;
      selectedArtist = null;
      catalogItems = [];
      catalogTarget = null;
      navigationHistory = [];
      activeView = primaryNav === "home" ? "feed" : primaryNav === "search" ? "search_results" : primaryNav === "history" ? "history" : primaryNav === "likes" ? "playlist_detail" : "library";
      isAlbumLoading = isArtistLoading = isCatalogLoading = false;
      isHomeLoadingMore = false;
      if (backendStatus?.ready) { loadHomePage(); void account.initialize(); }
      if (next.state === "ready") {
        if (primaryNav === "library") void account.load(accountData.tab);
        if (primaryNav === "history") void account.load('history');
        if (primaryNav === "likes") { lastPlaylistId = 'LM'; void account.openPlaylist('LM'); }
      }
    }
  }

  async function handleLogin() {
    try {
      await invoke("login_webview");
    } catch (error) {
      authStatus = { ...authStatus, state: "error", message: extractErrorMessage(error, "No se pudo abrir el acceso.") };
    }
  }

  async function handleCancelLogin() {
    try {
      applyAuthStatus(await invoke<AuthStatusDto>("cancel_login"));
    } catch (error) {
      authStatus = { ...authStatus, message: extractErrorMessage(error, "No se pudo cancelar el acceso.") };
    }
  }

  async function handleLogout() {
    try {
      applyAuthStatus(await invoke<AuthStatusDto>("sign_out"));
    } catch (error) {
      authStatus = { ...authStatus, message: extractErrorMessage(error, "No se pudo limpiar la sesión.") };
    }
  }

  function extractErrorMessage(err: unknown, fallback: string): string {
    if (err && typeof err === "object" && "message" in err) {
      return (err as CommandError).message;
    }
    if (typeof err === "string") {
      return err;
    }
    return fallback;
  }

  async function checkBackendStatus() {
    try {
      statusError = null;
      backendStatus = await invoke<BackendStatusDto>("get_backend_status");
      if (backendStatus?.ready && !homePage) {
        loadHomePage();
        if (authStatus.state === "ready") void account.initialize();
      }
    } catch (e: unknown) {
      statusError = extractErrorMessage(e, "Error al comprobar el estado del backend.");
    }
  }

  async function handleRetryInit() {
    isRetryingInit = true;
    statusError = null;
    try {
      backendStatus = await invoke<BackendStatusDto>("retry_init_core");
      if (backendStatus?.ready) {
        loadHomePage();
      }
    } catch (e: unknown) {
      statusError = extractErrorMessage(e, "No se pudo reconectar con el motor.");
    } finally {
      isRetryingInit = false;
    }
  }

  async function loadHomePage(chipParams?: string | null) {
    const requestId = ++homeRequestId;
    isHomeLoading = true;
    homeError = null;
    homeMoreError = null;
    isHomeLoadingMore = false;
    usedHomeTokens = new Set();
    activeChipParams = chipParams ?? null;

    try {
      const page = await invoke<HomePageDto>("get_home_page", {
        chipParams: chipParams ?? null,
      });
      if (requestId === homeRequestId) {
        homePage = page;
      }
    } catch (err: unknown) {
      if (requestId === homeRequestId) {
        homeError = extractErrorMessage(err, "No se pudo cargar la página de inicio.");
      }
    } finally {
      if (requestId === homeRequestId) {
        isHomeLoading = false;
      }
    }
    if (requestId === homeRequestId && !homeError && homePage?.continuation && activeChipParams === null) {
      const started = Date.now();
      for (let page = 0; page < 3 && Date.now() - started < 12000; page++) {
        if (requestId !== homeRequestId || !await loadMoreHome(requestId)) break;
      }
    }
  }

  async function loadMoreHome(expectedRequestId = homeRequestId): Promise<boolean> {
    const token = homePage?.continuation;
    if (!token || isHomeLoading || isHomeLoadingMore || expectedRequestId !== homeRequestId || usedHomeTokens.has(token)) return false;
    isHomeLoadingMore = true;
    homeMoreError = null;
    try {
      const page = await invoke<HomePageDto>("get_home_continuation", { token });
      if (expectedRequestId !== homeRequestId || homePage?.continuation !== token) return false;
      usedHomeTokens.add(token);
      const existing = new Set(homePage.sections.map(sectionIdentity));
      const fresh = page.sections.filter((section: HomeSectionDto) => {
        const key = sectionIdentity(section);
        if (existing.has(key)) return false;
        existing.add(key);
        return true;
      });
      const next = page.continuation && !usedHomeTokens.has(page.continuation) ? page.continuation : null;
      homePage = { ...homePage, sections: [...homePage.sections, ...fresh], continuation: next };
      return Boolean(next);
    } catch (error) {
      if (expectedRequestId === homeRequestId) homeMoreError = extractErrorMessage(error, "No se pudieron cargar más recomendaciones.");
      return false;
    } finally {
      if (expectedRequestId === homeRequestId) isHomeLoadingMore = false;
    }
  }

  async function executeSearch(targetQuery: string, mode: SearchMode = searchMode) {
    const q = targetQuery.trim();
    if (!q || isSearchLoading) return;
    invalidateDetails(); navigationHistory = [];

    primaryNav = "search";
    activeView = "search_results";
    scrollContentToTop();
    searchMode = mode;
    query = q;
    const requestId = ++searchRequestId;
    isSearchLoading = true;
    searchError = null;
    lastSearchedQuery = q;

    try {
      if (mode === "songs") {
        hasSearchedSongs = true;
        const results = await invoke<SongDto[]>("search_songs", { query: q });
        if (requestId === searchRequestId) {
          songs = results;
        }
      } else {
        hasSearchedAlbums = true;
        const results = await invoke<AlbumCardDto[]>("search_albums", { query: q });
        if (requestId === searchRequestId) {
          albums = results;
        }
      }
    } catch (err: unknown) {
      if (requestId === searchRequestId) {
        searchError = extractErrorMessage(err, "Error al consultar el catálogo.");
        if (mode === "songs") songs = [];
        else albums = [];
      }
    } finally {
      if (requestId === searchRequestId) {
        isSearchLoading = false;
      }
    }
  }

  function handleSwitchNav(nav: PrimaryNav) {
    if (nav === 'library' || nav === 'likes' || nav === 'history') { openAccountNav(nav); return; }
    navigationHistory = [];
    invalidateDetails();
    primaryNav = nav;
    if (nav === "home") {
      activeView = "feed";
      if (!homePage && !isHomeLoading) {
        loadHomePage();
      }
    } else {
      activeView = "search_results";
    }
    scrollContentToTop();
  }

  function scrollContentToTop() {
    document.querySelector<HTMLElement>(".content-column")?.scrollTo({ top: 0 });
  }

  async function handleWindowKeydown(event: KeyboardEvent) {
    if (event.key === "Escape" && isFullscreenOpen) {
      isFullscreenOpen = false;
      return;
    }
    if (event.ctrlKey && !event.altKey && !event.metaKey && event.key.toLowerCase() === "k") {
      event.preventDefault();
      handleSwitchNav("search");
      await tick();
      document.getElementById("search-input")?.focus();
    }
  }

  function handleSwitchSearchMode(mode: SearchMode) {
    if (searchMode === mode && activeView === "search_results") return;
    searchMode = mode;
    activeView = "search_results";
    if (query.trim()) {
      executeSearch(query, mode);
    }
  }

  function handleSearchFormSubmit(e: Event) {
    e.preventDefault();
    executeSearch(query, searchMode);
  }

  function handleQuickSearch(sample: string) {
    if (isSearchLoading) return;
    query = sample;
    executeSearch(sample, searchMode);
  }

  function invalidateDetails() {
    ++albumRequestId; ++artistRequestId; ++catalogRequestId;
    isAlbumLoading = isArtistLoading = isCatalogLoading = false;
  }

  function pushNavigation() {
    navigationHistory.push({ view: activeView, primary: primaryNav,
      scroll: document.querySelector<HTMLElement>(".content-column")?.scrollTop ?? 0,
      album: selectedAlbum, albumId: lastAlbumBrowseId, albumError,
      artist: selectedArtist, artistId: lastArtistBrowseId, artistError,
      catalog: catalogItems, target: catalogTarget, catalogError, playlistId: lastPlaylistId });
    if (navigationHistory.length > 40) navigationHistory.shift();
    invalidateDetails();
  }

  async function openAlbumDetail(browseId: string, _origin?: "home" | "search", remember = true) {
    if (!browseId.trim()) return;
    if (remember) pushNavigation();
    const requestId = ++albumRequestId;
    isAlbumLoading = true;
    albumError = null;
    activeView = "album_detail";
    scrollContentToTop();
    selectedAlbum = null;
    lastAlbumBrowseId = browseId;

    try {
      const detail = await invoke<AlbumDetailDto>("get_album", { browseId });
      if (requestId === albumRequestId) {
        selectedAlbum = detail;
      }
    } catch (err: unknown) {
      if (requestId === albumRequestId) {
        albumError = extractErrorMessage(err, "Error al cargar el detalle del álbum.");
      }
    } finally {
      if (requestId === albumRequestId) {
        isAlbumLoading = false;
      }
    }
  }

  async function openArtistDetail(browseId: string, remember = true) {
    if (!browseId.trim()) return;
    if (remember) pushNavigation();
    const requestId = ++artistRequestId;
    activeView = "artist_detail";
    selectedArtist = null; lastArtistBrowseId = browseId;
    isArtistLoading = true; artistError = null;
    scrollContentToTop();
    try {
      const detail = await invoke<ArtistDetailDto>("get_artist", { browseId });
      if (requestId === artistRequestId) selectedArtist = detail;
    } catch (error) {
      if (requestId === artistRequestId) artistError = extractErrorMessage(error, "No se pudo cargar el artista.");
    } finally { if (requestId === artistRequestId) isArtistLoading = false; }
  }

  async function openCatalog(id: string, params: string | null, title: string, remember = true) {
    if (!id.trim()) return;
    if (remember) pushNavigation();
    const requestId = ++catalogRequestId;
    activeView = "catalog"; catalogTarget = { id, params, title }; catalogItems = [];
    isCatalogLoading = true; catalogError = null;
    scrollContentToTop();
    try {
      const items = await invoke<BrowseCardDto[]>("get_browse_grid", { browseId: id, params });
      if (requestId === catalogRequestId) catalogItems = items;
    } catch (error) {
      if (requestId === catalogRequestId) catalogError = extractErrorMessage(error, "No se pudo cargar la sección.");
    } finally { if (requestId === catalogRequestId) isCatalogLoading = false; }
  }

  async function goBackFromDetail() {
    invalidateDetails();
    const previous = navigationHistory.pop();
    if (!previous) { handleSwitchNav(primaryNav === 'likes' ? 'home' : primaryNav); return; }
    activeView = previous.view; primaryNav = previous.primary;
    selectedAlbum = previous.album; lastAlbumBrowseId = previous.albumId; albumError = previous.albumError;
    selectedArtist = previous.artist; lastArtistBrowseId = previous.artistId; artistError = previous.artistError;
    catalogItems = previous.catalog; catalogTarget = previous.target; catalogError = previous.catalogError;
    lastPlaylistId = previous.playlistId;
    if (activeView === 'playlist_detail' && lastPlaylistId) void account.openPlaylist(lastPlaylistId);
    if (activeView === "album_detail" && !selectedAlbum && lastAlbumBrowseId && !albumError) void openAlbumDetail(lastAlbumBrowseId, undefined, false);
    if (activeView === "artist_detail" && !selectedArtist && lastArtistBrowseId && !artistError) void openArtistDetail(lastArtistBrowseId, false);
    if (activeView === "catalog" && !catalogItems.length && catalogTarget && !catalogError) void openCatalog(catalogTarget.id, catalogTarget.params, catalogTarget.title, false);
    await tick();
    document.querySelector<HTMLElement>(".content-column")?.scrollTo({ top: previous.scroll });
  }

  async function toggleAlbumLibrary() {
    const album = selectedAlbum;
    if (!album?.playlistId || authStatus.state !== "ready") throw new Error("Inicia sesión para guardar el álbum.");
    const revision = sessionRevision;
    const save = !album.inLibrary;
    try { await invoke("toggle_album_library", { playlistId: album.playlistId, save }); }
    catch (error) { throw new Error(extractErrorMessage(error, "No se pudo actualizar la biblioteca.")); }
    if (revision !== sessionRevision) return;
    if (selectedAlbum?.browseId === album.browseId) selectedAlbum = { ...selectedAlbum, inLibrary: save };
    for (const snapshot of navigationHistory) if (snapshot.album?.browseId === album.browseId) snapshot.album = { ...snapshot.album, inLibrary: save };
    void account.load('albums');
  }

  async function toggleArtistSubscription() {
    const artist = selectedArtist;
    if (!artist || authStatus.state !== "ready") throw new Error("Inicia sesión para suscribirte.");
    const revision = sessionRevision;
    const subscribe = !artist.subscribed;
    try { await invoke("set_artist_subscription", { channelId: artist.channelId, subscribe }); }
    catch (error) { throw new Error(extractErrorMessage(error, "No se pudo actualizar la suscripción.")); }
    if (revision !== sessionRevision) return;
    if (selectedArtist?.channelId === artist.channelId) selectedArtist = { ...selectedArtist, subscribed: subscribe };
    for (const snapshot of navigationHistory) if (snapshot.artist?.channelId === artist.channelId) snapshot.artist = { ...snapshot.artist, subscribed: subscribe };
    void account.load('artists');
  }

  async function playCollection(items: SongDto[], index: number, source: {kind:string;id:string;title:string}, shuffle = false, fallbackThumbnail: string | null = null) {
    const indexed = items.map((song, originalIndex) => ({ song, originalIndex })).filter(({ song }) => song.videoId.trim());
    const entries = indexed.map(({ song }) => ({
      entryId: crypto.randomUUID(), videoId: song.videoId, title: song.title,
      artists: song.artists, thumbnail: song.thumbnail || fallbackThumbnail,
      duration: song.duration ? parseDuration(song.duration) : null,
    }));
    if (!entries.length) throw new Error("No hay canciones disponibles para reproducir.");
    let startIndex = indexed.findIndex((entry) => entry.originalIndex === index);
    if (shuffle) {
      for (let position = entries.length - 1; position > 0; position--) {
        const other = Math.floor(Math.random() * (position + 1));
        [entries[position], entries[other]] = [entries[other], entries[position]];
      }
      startIndex = 0;
    }
    startIndex = Math.max(0, startIndex);
    const track = entries[startIndex];
    const requestId = ++playSongRequestId;
    playbackError = null;
    try {
      const result = await invoke<PlaybackStateDto>("play_song", { videoId: track.videoId,
        title: track.title, artists: track.artists, thumbnail: track.thumbnail,
        queueItems: entries, queueCurrentIndex: startIndex, queueSource: source, preserveQueue: false });
      if (requestId === playSongRequestId && result.generation >= playbackState.generation) {
        playbackState = result; playbackError = result.error;
      }
    } catch (error) {
      const message = extractErrorMessage(error, "No se pudo iniciar la reproducción.");
      if (requestId === playSongRequestId) playbackError = message;
      throw new Error(message);
    }
  }

  function playAlbum(index: number, shuffle = false) {
    if (selectedAlbum) void playCollection(selectedAlbum.items, index,
      {kind: "album", id: selectedAlbum.browseId, title: selectedAlbum.title}, shuffle, selectedAlbum.thumbnail).catch(() => {});
  }

  function playArtist(index: number, shuffle = false) {
    if (selectedArtist) void playCollection(selectedArtist.topSongs, index,
      {kind: "artist", id: selectedArtist.channelId, title: selectedArtist.name}, shuffle, selectedArtist.thumbnail).catch(() => {});
  }

  function openAccountNav(destination: 'library' | 'likes' | 'history') {
    navigationHistory = []; invalidateDetails(); primaryNav = destination;
    if (destination === 'likes') { activeView = 'playlist_detail'; lastPlaylistId = 'LM'; void account.openPlaylist('LM'); }
    else if (destination === 'library') { activeView = 'library'; void account.load(accountData.tab); }
    else { activeView = 'history'; void account.load('history'); }
    scrollContentToTop();
  }
  function openPlaylist(id: string, remember = true) {
    if (!id.trim()) return;
    if (remember) pushNavigation();
    activeView = 'playlist_detail'; lastPlaylistId = id; scrollContentToTop(); void account.openPlaylist(id);
  }
  function openLibraryCard(card: BrowseCardDto) {
    if (card.kind === 'artist' || accountData.tab === 'artists') void openArtistDetail(card.id);
    else if (card.kind === 'album' || accountData.tab === 'albums') void openAlbumDetail(card.id);
    else openPlaylist(card.id);
  }
  function playLibrarySong(index: number) {
    void playCollection(accountData.songs, index, { kind: 'library', id: 'FEmusic_liked_videos', title: 'Biblioteca' }).catch(() => {});
  }
  function playPlaylistSong(index: number) {
    const playlist = accountData.playlist;
    if (playlist) void playCollection(playlist.items, index, { kind: 'playlist', id: playlist.id, title: playlist.title }, false, playlist.thumbnail).catch(() => {});
  }

  async function startArtistRadio() {
    const artist = selectedArtist;
    if (!artist?.radioPlaylistId) return;
    const revision = sessionRevision;
    const requestId = artistRequestId;
    try {
      const items = await invoke<SongDto[]>("get_artist_radio", { playlistId: artist.radioPlaylistId });
      if (revision !== sessionRevision || requestId !== artistRequestId) return;
      await playCollection(items, 0, {kind: "radio", id: artist.radioPlaylistId, title: `Mix de ${artist.name}`});
    } catch (error) { throw new Error(extractErrorMessage(error, "No se pudo iniciar el mix.")); }
  }

  async function handlePlaySong(
    videoId: string,
    meta?: { title?: string; artists?: string; thumbnail?: string | null; duration?: string | null },
    albumContext?: AlbumDetailDto | null,
    preserveQueue = false,
    albumIndex?: number,
    queueIndex?: number,
  ) {
    if (!videoId.trim()) return;
    const reqId = ++playSongRequestId;
    playbackError = null;
    playbackState.error = null;
    try {
      const entries = !preserveQueue ? albumContext?.items.map((song) => ({
          entryId: crypto.randomUUID(), videoId: song.videoId, title: song.title,
          artists: song.artists || albumContext.artist || "", thumbnail: song.thumbnail || albumContext.thumbnail,
          duration: song.duration ? parseDuration(song.duration) : null,
        })) ?? [{ entryId: crypto.randomUUID(), videoId: videoId.trim(), title: meta?.title ?? "Canción",
          artists: meta?.artists ?? "", thumbnail: meta?.thumbnail ?? null,
          duration: meta?.duration ? parseDuration(meta.duration) : null }] : null;
      const currentIndex = albumContext ? (albumIndex ?? albumContext.items.findIndex((song) => song.videoId === videoId)) : (queueIndex ?? (preserveQueue ? null : 0));
      const res = await invoke<PlaybackStateDto>("play_song", {
        videoId: videoId.trim(),
        title: meta?.title ?? null,
        artists: meta?.artists ?? null,
        thumbnail: meta?.thumbnail ?? null,
        queueItems: entries,
        queueCurrentIndex: currentIndex !== null && currentIndex < 0 ? 0 : currentIndex,
        queueSource: entries ? albumContext
          ? { kind: "album", id: albumContext.browseId, title: albumContext.title }
          : { kind: "song", id: videoId.trim(), title: meta?.title ?? null }
          : null,
        preserveQueue,
      });
      if (reqId === playSongRequestId) {
        if (res.generation >= playbackState.generation) {
          playbackState = res;
          if (res.error) {
            playbackError = res.error;
          }
        }
      }
    } catch (err: unknown) {
      if (reqId === playSongRequestId) {
        playbackError = extractErrorMessage(err, "No se pudo iniciar la reproducción de la canción.");
      }
    }
  }

  function parseDuration(value: string): number | null {
    const parts = value.split(":").map(Number);
    if (parts.some((part) => !Number.isFinite(part))) return null;
    return parts.reduce((total, part) => total * 60 + part, 0);
  }

  async function playQueueIndex(index: number) {
    const entry = playbackState.queue.items[index];
    if (!entry) return;
    await handlePlaySong(entry.videoId, { title: entry.title, artists: entry.artists, thumbnail: entry.thumbnail }, null, true, undefined, index);
  }

  async function handleNext() {
    try {
      const next = await invoke<PlaybackStateDto>("next_track");
      if (next.generation >= playbackState.generation) playbackState = next;
    } catch (err) { playbackError = extractErrorMessage(err, "No se pudo avanzar la cola."); }
  }

  async function handlePrevious() {
    try {
      const previous = await invoke<PlaybackStateDto>("previous_track");
      if (previous.generation >= playbackState.generation) playbackState = previous;
    } catch (err) { playbackError = extractErrorMessage(err, "No se pudo retroceder en la cola."); }
  }

  async function handleTogglePlay() {
    try {
      if ((playbackState.isEnded || playbackState.error || playbackError) && playbackState.currentTrack) {
        await handleRetryPlayback();
        return;
      } else if (playbackState.isPlaying) {
        playbackState = await invoke<PlaybackStateDto>("pause_playback");
      } else {
        playbackState = await invoke<PlaybackStateDto>("resume_playback");
      }
      playbackError = null;
    } catch (err: unknown) {
      playbackError = extractErrorMessage(err, "Error al cambiar el estado de reproducción.");
    }
  }

  async function handleRetryPlayback() {
    const track = playbackState.currentTrack;
    if (!track) return;
    await handlePlaySong(track.videoId, {
      title: track.title ?? undefined,
      artists: track.artists ?? undefined,
      thumbnail: track.thumbnail,
    }, null, true);
  }

  async function handleSeek(seconds: number) {
    try {
      playbackState = await invoke<PlaybackStateDto>("seek_playback", { seconds });
    } catch (err: unknown) {
      playbackError = extractErrorMessage(err, "Error al cambiar la posición de reproducción.");
    }
  }

  async function handleVolumeChange(volume: number) {
    playbackState.volume = volume;
    try {
      await invoke<PlaybackStateDto>("set_playback_volume", { volume });
    } catch (err: unknown) {
      playbackError = extractErrorMessage(err, "Error al cambiar el volumen.");
    }
  }

  let unlistenState: UnlistenFn | null = null;
  let unlistenProgress: UnlistenFn | null = null;
  let unlistenAuth: UnlistenFn | null = null;

  onMount(() => {
    checkBackendStatus();
    invoke<AuthStatusDto>("get_auth_status").then(applyAuthStatus).catch(() => {});
    window.addEventListener("keydown", handleWindowKeydown);

    listen<PlaybackStateDto>("playback-state-changed", (event) => {
      if (event.payload.generation >= playbackState.generation) {
        playbackState = event.payload;
        if (event.payload.error) {
          playbackError = event.payload.error;
        } else {
          playbackError = null;
        }
      }
    }).then((unlisten) => {
      unlistenState = unlisten;
    });

    listen<PlaybackProgressDto>("playback-progress", (event) => {
      if (event.payload.generation === playbackState.generation && !playbackState.isLoading) {
        playbackState.position = event.payload.position;
        if (event.payload.duration > 0) {
          playbackState.duration = event.payload.duration;
        }
      }
    }).then((unlisten) => {
      unlistenProgress = unlisten;
    });

    listen<AuthStatusDto>("auth-status-changed", (event) => applyAuthStatus(event.payload))
      .then((unlisten) => { unlistenAuth = unlisten; });

    invoke<PlaybackStateDto>("get_playback_state")
      .then((state) => {
        playbackState = state;
      })
      .catch(() => {});

    return () => {
      account.reset(false);
      window.removeEventListener("keydown", handleWindowKeydown);
      unlistenState?.();
      unlistenProgress?.();
      unlistenAuth?.();
    };
  });
</script>

<div class="app-frame" class:sidebar-collapsed={sidebarCollapsed} class:fullscreen-open={isFullscreenOpen}>
  <Sidebar
    activeDestination={activeView === 'playlist_detail' ? lastPlaylistId === 'LM' ? 'likes' : 'playlist' : activeView === 'library' ? 'library' : activeView === 'history' ? 'history' : activeView === 'artist_detail' ? 'artist' : activeView === 'album_detail' || activeView === 'catalog' ? 'album' : primaryNav}
    onHome={() => handleSwitchNav("home")}
    onSearch={() => handleSwitchNav("search")}
    collapsed={sidebarCollapsed}
    auth={authStatus}
    onLogin={handleLogin}
    onCancelLogin={handleCancelLogin}
    onLogout={handleLogout}
    onLikes={() => openAccountNav('likes')} onLibrary={() => openAccountNav('library')} onHistory={() => openAccountNav('history')}
    playlists={accountData.playlists} albums={accountData.albums}
    libraryLoading={accountData.loading.playlists || accountData.loading.albums}
    libraryError={accountData.errors.playlists || accountData.errors.albums}
    selectedCollectionId={activeView === 'playlist_detail' ? lastPlaylistId : activeView === 'album_detail' ? lastAlbumBrowseId : null}
    onOpenPlaylist={openPlaylist} onOpenAlbum={openAlbumDetail}
  />
  <div class="content-column">
    <div class="shell-toolbar">
      <button
        type="button"
        class="sidebar-toggle"
        onclick={() => (sidebarCollapsed = !sidebarCollapsed)}
        aria-label={sidebarCollapsed ? "Expandir barra lateral" : "Contraer barra lateral"}
        title={sidebarCollapsed ? "Expandir barra lateral" : "Contraer barra lateral"}
      >
        ☰
      </button>
    </div>
<main class="shell" class:home-shell={activeView !== "search_results"}>
  {#if activeView === "search_results"}
  <header class="header">
    <img src="/logo.png" alt="Side B Logo" class="app-logo" />
    <h1>Side B</h1>
    <p class="subtitle">Página de inicio y búsqueda nativa</p>

  </header>
  {/if}

  {#if (backendStatus && !backendStatus.ready) || statusError}
  <div class="backend-notice" role="status">
    {#if backendStatus && !backendStatus.ready}
      <div class="status-bar">
        <span class="dot error"></span>
        <span class="status-text error-text">{backendStatus.status}</span>
        <button
          type="button"
          class="reconnect-btn"
          disabled={isRetryingInit}
          onclick={handleRetryInit}
        >
          {isRetryingInit ? "Reconectando..." : "Reconectar"}
        </button>
      </div>
    {:else if statusError}
      <div class="status-bar">
        <span class="dot error"></span>
        <span class="status-text error-text">{statusError}</span>
        <button
          type="button"
          class="reconnect-btn"
          disabled={isRetryingInit}
          onclick={handleRetryInit}
        >
          {isRetryingInit ? "Reintentando..." : "Reintentar"}
        </button>
      </div>
    {/if}
  </div>
  {/if}

  {#if accountData.actionError}<div class="account-action-error" role="alert">{accountData.actionError}</div>{/if}
  {#if activeView === 'library'}
    <LibraryView loggedIn={authStatus.state === 'ready'} tab={accountData.tab}
      songs={accountData.songs} playlists={accountData.playlists} albums={accountData.albums} artists={accountData.artists}
      loading={accountData.loading[accountData.tab]} loadingMore={accountData.loadingMore} error={accountData.errors[accountData.tab]}
      continuation={accountData.tab === 'songs' ? accountData.songContinuation : null}
      currentTrackId={playbackState.currentTrack?.videoId ?? null} isPlaying={playbackState.isPlaying}
      likedIds={accountData.likedIds} pendingIds={accountData.pendingIds}
      onTab={(tab) => account.setTab(tab)} onRefresh={() => account.load(accountData.tab)} onLoadMore={() => account.loadMoreSongs()}
      onPlay={playLibrarySong} onOpenCard={openLibraryCard} onOpenArtist={openArtistDetail} onOpenAlbum={openAlbumDetail}
      onToggleLike={(song) => account.toggleLike(song)} onToggleSaved={(song) => account.toggleSaved(song)}
      onCreatePlaylist={(title, description) => account.createPlaylist(title, description)} onLogin={handleLogin} />
  {:else if activeView === 'playlist_detail'}
    {#key lastPlaylistId}
      <PlaylistDetailView playlist={accountData.playlist} loading={accountData.playlistLoading} loadingMore={accountData.playlistLoadingMore}
        error={accountData.playlistError} loggedIn={authStatus.state === 'ready'}
        currentTrackId={playbackState.currentTrack?.videoId ?? null} isPlaying={playbackState.isPlaying}
        likedIds={accountData.likedIds} pendingIds={accountData.pendingIds}
        onBack={goBackFromDetail} onRetry={() => lastPlaylistId && account.refreshPlaylist(lastPlaylistId)} onLoadMore={() => account.loadMorePlaylist()}
        onPlay={playPlaylistSong} onToggleLike={(song) => account.toggleLike(song)} onToggleSaved={(song) => account.toggleSaved(song)}
        onToggleLibrary={() => account.togglePlaylistLibrary()} onOpenArtist={openArtistDetail} onOpenAlbum={openAlbumDetail} onLogin={handleLogin} />
    {/key}
  {:else if activeView === 'history'}
    <HistoryView loggedIn={authStatus.state === 'ready'} groups={accountData.history} loading={accountData.loading.history} error={accountData.errors.history}
      currentTrackId={playbackState.currentTrack?.videoId ?? null} isPlaying={playbackState.isPlaying}
      likedIds={accountData.likedIds} pendingIds={accountData.pendingIds} onLogin={handleLogin} onRefresh={() => account.load('history')}
      onPlay={(items, index) => { void playCollection(items, index, {kind:'history',id:'history',title:'Historial'}).catch(() => {}); }}
      onToggleLike={(song) => account.toggleLike(song)} onToggleSaved={(song) => account.toggleSaved(song)}
      onOpenArtist={openArtistDetail} onOpenAlbum={openAlbumDetail} />
  {:else if activeView === "album_detail"}
    {#key lastAlbumBrowseId}
      <AlbumDetailView album={selectedAlbum} isLoading={isAlbumLoading} error={albumError}
        currentTrackId={playbackState.currentTrack?.videoId ?? null} isPlaying={playbackState.isPlaying}
        loggedIn={authStatus.state === "ready"} onBack={goBackFromDetail}
        onRetry={() => lastAlbumBrowseId && openAlbumDetail(lastAlbumBrowseId, undefined, false)}
        onPlay={playAlbum} onOpenArtist={openArtistDetail} onOpenAlbum={openAlbumDetail}
        onOpenCatalog={openCatalog} onToggleLibrary={toggleAlbumLibrary} onOpenPlaylist={openPlaylist}
        onPlaySong={(item) => handlePlaySong(item.id, {title:item.title,artists:item.subtitle ?? '',thumbnail:item.thumbnail,duration:item.duration})} />
    {/key}
  {:else if activeView === "artist_detail"}
    {#key lastArtistBrowseId}
      <ArtistDetailView artist={selectedArtist} isLoading={isArtistLoading} error={artistError}
        currentTrackId={playbackState.currentTrack?.videoId ?? null} isPlaying={playbackState.isPlaying}
        loggedIn={authStatus.state === "ready"} onBack={goBackFromDetail}
        onRetry={() => lastArtistBrowseId && openArtistDetail(lastArtistBrowseId, false)}
        onPlay={playArtist} onStartRadio={startArtistRadio} onToggleSubscription={toggleArtistSubscription}
        onOpenAlbum={openAlbumDetail} onOpenArtist={openArtistDetail} onOpenCatalog={openCatalog} onOpenPlaylist={openPlaylist}
        onPlaySong={(item) => handlePlaySong(item.id, {title:item.title,artists:item.subtitle ?? '',thumbnail:item.thumbnail,duration:item.duration})} />
    {/key}
  {:else if activeView === "catalog"}
    {#key catalogTarget?.id}
      <CatalogView title={catalogTarget?.title ?? "Catálogo"} items={catalogItems}
        isLoading={isCatalogLoading} error={catalogError} onBack={goBackFromDetail}
        onRetry={() => catalogTarget && openCatalog(catalogTarget.id, catalogTarget.params, catalogTarget.title, false)}
        onOpenAlbum={openAlbumDetail} onOpenArtist={openArtistDetail} onOpenPlaylist={openPlaylist}
        onPlaySong={(item) => handlePlaySong(item.id, { title: item.title, artists: item.subtitle ?? "", thumbnail: item.thumbnail, duration: item.duration })} />
    {/key}

  <!-- VISTA 2: Inicio como en macOS -->
  {:else if primaryNav === "home"}
    <HomeView
      chips={homePage?.chips ?? []}
      sections={homePage?.sections ?? []}
      selectedChipParams={activeChipParams}
      isLoading={isHomeLoading}
      error={homeError}
      hasMore={Boolean(homePage?.continuation)}
      isLoadingMore={isHomeLoadingMore}
      moreError={homeMoreError}
      onLoadMore={() => loadMoreHome()}
      onOpenArtist={openArtistDetail}
      onOpenPlaylist={openPlaylist}
      onOpenCatalog={openCatalog}
      onSelectChip={(params) => loadHomePage(params)}
      onRetry={() => loadHomePage(activeChipParams)}
      onOpenAlbum={(browseId) => openAlbumDetail(browseId, "home")}
      onPlaySong={(item) => handlePlaySong(item.id, {
        title: item.title,
        artists: item.artists ?? item.subtitle ?? "",
        thumbnail: item.thumbnail,
        duration: item.duration,
      })}
    />

  <!-- VISTA 3: BUSCAR (Canciones y Álbumes con detalle W03/W04) -->
  {:else}
    <div class="search-view-container">
      <nav class="mode-tabs" aria-label="Modo de búsqueda">
        <button
          type="button"
          class="tab-btn"
          class:active={searchMode === "songs"}
          disabled={isSearchLoading}
          onclick={() => handleSwitchSearchMode("songs")}
        >
          <svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor">
            <path d="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z" />
          </svg>
          Canciones
        </button>
        <button
          type="button"
          class="tab-btn"
          class:active={searchMode === "albums"}
          disabled={isSearchLoading}
          onclick={() => handleSwitchSearchMode("albums")}
        >
          <svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor">
            <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 14.5c-2.49 0-4.5-2.01-4.5-4.5S9.51 7.5 12 7.5s4.5 2.01 4.5 4.5-2.01 4.5-4.5 4.5zm0-5.5c-.55 0-1 .45-1 1s.45 1 1 1 1-.45 1-1-.45-1-1-1z" />
          </svg>
          Álbumes
        </button>
      </nav>

      <section class="search-section">
        <form class="search-form" onsubmit={handleSearchFormSubmit}>
          <div class="input-wrapper">
            <svg
              class="search-icon"
              viewBox="0 0 24 24"
              width="18"
              height="18"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
            >
              <circle cx="11" cy="11" r="8"></circle>
              <line x1="21" y1="21" x2="16.65" y2="16.65"></line>
            </svg>
            <input
              id="search-input"
              type="text"
              placeholder={searchMode === "songs" ? "Buscar canciones o artistas..." : "Buscar álbumes o discografías..."}
              bind:value={query}
              disabled={isSearchLoading}
            />
            {#if query && !isSearchLoading}
              <button
                type="button"
                class="clear-btn"
                onclick={() => (query = "")}
                aria-label="Limpiar búsqueda"
              >
                &times;
              </button>
            {/if}
          </div>
          <button
            type="submit"
            class="submit-btn"
            disabled={isSearchLoading || !query.trim()}
          >
            {isSearchLoading ? "Buscando..." : "Buscar"}
          </button>
        </form>

        <div class="quick-chips">
          <span class="chip-label">Sugerencias:</span>
          <button
            type="button"
            class="chip"
            disabled={isSearchLoading}
            onclick={() => handleQuickSearch("Daft Punk")}
          >
            Daft Punk
          </button>
          <button
            type="button"
            class="chip"
            disabled={isSearchLoading}
            onclick={() => handleQuickSearch("Radiohead")}
          >
            Radiohead
          </button>
          <button
            type="button"
            class="chip"
            disabled={isSearchLoading}
            onclick={() => handleQuickSearch("Gustavo Cerati")}
          >
            Gustavo Cerati
          </button>
        </div>
      </section>

      <section class="content-section">
        {#if isSearchLoading}
          <div class="state-container loading-state">
            <div class="spinner"></div>
            <p>
              {searchMode === "songs"
                ? "Buscando canciones en YouTube Music..."
                : "Buscando álbumes en YouTube Music..."}
            </p>
          </div>
        {:else if searchError}
          <div class="state-container error-state">
            <div class="error-icon">!</div>
            <h3>Error al consultar el catálogo</h3>
            <p class="error-msg">{searchError}</p>
            <button
              type="button"
              class="retry-btn"
              onclick={() => executeSearch(lastSearchedQuery || query, searchMode)}
            >
              Reintentar búsqueda
            </button>
          </div>
        {:else if searchMode === "songs"}
          {#if hasSearchedSongs && songs.length === 0}
            <div class="state-container empty-state">
              <div class="empty-icon">&#128269;</div>
              <h3>Sin resultados</h3>
              <p>No se encontraron canciones para «<strong>{lastSearchedQuery}</strong>».</p>
            </div>
          {:else if !hasSearchedSongs}
            <div class="state-container prompt-state">
              <div class="prompt-icon">&#9835;</div>
              <h3>Búsqueda de canciones</h3>
              <p>Ingresá una búsqueda arriba para probar la resolución de canciones de <code>sideb-core</code>.</p>
            </div>
          {:else}
            <div class="results-header">
              <h2>Resultados para «{lastSearchedQuery}»</h2>
              <span class="count-badge">{songs.length} canciones</span>
            </div>

            <div class="song-list">
              {#each songs as song (song.videoId)}
                <div
                  class="song-row"
                  class:is-active-track={playbackState.currentTrack?.videoId === song.videoId}
                  role="button"
                  tabindex="0"
                  onclick={() =>
                    handlePlaySong(song.videoId, {
                      title: song.title,
                      artists: song.artists,
                      thumbnail: song.thumbnail,
                      duration: song.duration,
                    })}
                  onkeydown={(e) => {
                    if (e.key === "Enter" || e.key === " ") {
                      e.preventDefault();
                      handlePlaySong(song.videoId, {
                        title: song.title,
                        artists: song.artists,
                        thumbnail: song.thumbnail,
                        duration: song.duration,
                      });
                    }
                  }}
                  title="Reproducir canción"
                >
                  <div class="thumb-container">
                    {#if song.thumbnail}
                      <img src={song.thumbnail} alt={song.title} class="thumb-img" loading="lazy" />
                    {:else}
                      <div class="thumb-fallback">&#9835;</div>
                    {/if}
                  </div>

                  <div class="meta-col">
                    <span class="song-title" title={song.title}>{song.title}</span>
                    <span class="song-artist" title={song.artists}>{song.artists}</span>
                    {#if song.album}
                      <span class="song-album" title={song.album}>• {song.album}</span>
                    {/if}
                  </div>

                  <div class="extra-col">
                    {#if playbackState.currentTrack?.videoId === song.videoId && playbackState.isPlaying}
                      <span class="tag-playing">&#9658; SONANDO</span>
                    {/if}
                    {#if song.isVideo}
                      <span class="tag-video">VIDEO</span>
                    {/if}
                    {#if song.duration}
                      <span class="song-duration">{song.duration}</span>
                    {/if}
                  </div>
                </div>
              {/each}
            </div>
          {/if}
        {:else}
          {#if hasSearchedAlbums && albums.length === 0}
            <div class="state-container empty-state">
              <div class="empty-icon">&#128269;</div>
              <h3>Sin resultados</h3>
              <p>No se encontraron álbumes para «<strong>{lastSearchedQuery}</strong>».</p>
            </div>
          {:else if !hasSearchedAlbums}
            <div class="state-container prompt-state">
              <div class="prompt-icon">&#128191;</div>
              <h3>Búsqueda de álbumes</h3>
              <p>Ingresá una búsqueda arriba para explorar discografías y abrir su detalle con pistas reales.</p>
            </div>
          {:else}
            <div class="results-header">
              <h2>Álbumes para «{lastSearchedQuery}»</h2>
              <span class="count-badge">{albums.length} álbumes</span>
            </div>

            <div class="album-grid">
              {#each albums as album (album.id)}
                <button
                  type="button"
                  class="album-card"
                  onclick={() => openAlbumDetail(album.id, "search")}
                  title={`Ver detalle de ${album.title}`}
                >
                  <div class="album-card-cover">
                    {#if album.thumbnail}
                      <img src={album.thumbnail} alt={album.title} class="album-card-img" loading="lazy" />
                    {:else}
                      <div class="album-card-fallback">&#128191;</div>
                    {/if}
                  </div>
                  <div class="album-card-info">
                    <span class="album-card-title">{album.title}</span>
                    {#if album.subtitle}
                      <span class="album-card-sub">{album.subtitle}</span>
                    {/if}
                  </div>
                </button>
              {/each}
            </div>
          {/if}
        {/if}
      </section>
    </div>
  {/if}
</main>

<div class="player-dock">
  <PlayerBar playback={playerBarState} onTogglePlayback={handleTogglePlay} onRetryPlayback={handleRetryPlayback} onPrevious={handlePrevious} onNext={handleNext} onSeek={handleSeek} onVolumeChange={handleVolumeChange} fullscreenOpen={isFullscreenOpen} onToggleFullscreen={() => (isFullscreenOpen = !isFullscreenOpen)}
    loggedIn={authStatus.state === 'ready'} liked={accountData.likedIds.has(playbackState.currentTrack?.videoId ?? '')}
    likePending={(accountData.loading.likes && !accountData.likedIds.has(playbackState.currentTrack?.videoId ?? '')) || accountData.pendingIds.has(playbackState.currentTrack?.videoId ?? '')}
    likeError={accountData.actionError || accountData.errors.likes}
    onToggleLike={() => { if (playbackState.currentTrack) void account.toggleLike(playbackState.currentTrack); }} />
</div>
  </div>
  {#if isFullscreenOpen}
    <FullscreenNowPlaying playback={playerBarState} onSelectQueue={playQueueIndex} onClose={() => (isFullscreenOpen = false)} />
  {/if}
</div>

<style>
  .account-action-error { margin: 10px 32px; padding: 10px 14px; border-radius: 8px; background: #9d303033; color: #ffd5d5; font-size: 13px; }
  :global(html), :global(body) {
    width: 100%;
    height: 100%;
    margin: 0;
    overflow: hidden;
  }

  :root {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    font-size: 15px;
    line-height: 1.5;
    color: #e4e4e7;
    background-color: #1b1b1e;
    user-select: none;
  }

  .app-frame {
    --sidebar-width: 230px;
    --sideb-sidebar: #24242a;
    --sideb-accent: #a33d45;
    --sideb-accent-highlight: #d06c70;
    display: flex;
    width: 100%;
    height: 100dvh;
    min-height: 0;
    background: #1b1b1e;
  }

  .app-frame.sidebar-collapsed { --sidebar-width: 60px; }
  .app-frame.fullscreen-open { --sidebar-width: 0px; }
  .app-frame.fullscreen-open .content-column { overflow: hidden; }

  .content-column {
    flex: 1;
    min-width: 0;
    height: 100%;
    overflow-y: auto;
    overflow-x: hidden;
    overflow-anchor: none;
  }

  .shell-toolbar {
    position: sticky;
    top: 0;
    z-index: 30;
    height: 42px;
    display: flex;
    align-items: center;
    padding: 0 16px;
    background: rgb(27 27 30 / 92%);
    border-bottom: 1px solid rgb(255 255 255 / 6%);
  }

  .sidebar-toggle {
    display: grid;
    place-items: center;
    width: 30px;
    height: 30px;
    border: 0;
    border-radius: 6px;
    color: #dedee2;
    background: transparent;
    font-size: 17px;
    cursor: pointer;
  }

  .sidebar-toggle:hover { background: rgb(255 255 255 / 9%); }
  .sidebar-toggle:focus-visible { outline: 2px solid #d06c70; outline-offset: 2px; }

  .shell {
    max-width: 900px;
    margin: 0 auto;
    padding: 2.2rem 1.5rem 6.5rem 1.5rem;
    display: flex;
    flex-direction: column;
    gap: 1.4rem;
  }

  .shell.home-shell {
    max-width: none;
    margin: 0;
    padding: 0;
    gap: 0;
  }

  .backend-notice:has(.status-bar) {
    padding: 12px 28px 0;
  }

  .header {
    text-align: center;
  }

  .app-logo {
    width: 60px;
    height: 60px;
    border-radius: 14px;
    margin: 0 auto 0.6rem auto;
    display: block;
    box-shadow: 0 4px 16px rgba(0, 0, 0, 0.4);
  }

  h1 {
    font-size: 2.1rem;
    font-weight: 700;
    margin: 0 0 0.35rem 0;
    color: #ffffff;
    letter-spacing: -0.02em;
  }

  .subtitle {
    margin: 0 0 0.85rem 0;
    color: #9ca3af;
    font-size: 0.95rem;
  }

  code {
    font-family: "Cascadia Code", Consolas, monospace;
    background: #27272e;
    padding: 0.15rem 0.4rem;
    border-radius: 4px;
    font-size: 0.85em;
    color: #f87171;
  }

  .status-bar {
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
    background: #24242a;
    border: 1px solid #32323a;
    padding: 0.35rem 0.9rem;
    border-radius: 9999px;
    font-size: 0.8rem;
    color: #9ca3af;
  }

  .dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    flex-shrink: 0;
  }

  .dot.error {
    background-color: #ef4444;
    box-shadow: 0 0 8px #ef4444;
  }

  .error-text {
    color: #fca5a5;
  }

  .reconnect-btn {
    background: #3f3f46;
    border: none;
    color: #ffffff;
    border-radius: 6px;
    padding: 0.15rem 0.5rem;
    font-size: 0.75rem;
    cursor: pointer;
    margin-left: 0.25rem;
    transition: background 0.15s;
  }

  .reconnect-btn:hover:not(:disabled) {
    background: #52525b;
  }

  .reconnect-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

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
    font-weight: 600;
    color: #ffffff;
    font-size: 0.95rem;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .song-artist {
    color: #9ca3af;
    font-size: 0.85rem;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .song-album {
    color: #6b7280;
    font-size: 0.8rem;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

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

  /* Vista Detalle de Álbum */
  .player-dock {
    position: fixed;
    z-index: 100;
    left: calc(var(--sidebar-width) + 16px);
    right: 16px;
    bottom: 16px;
    display: flex;
    justify-content: center;
    pointer-events: none;
  }

  .player-dock :global(.player-bar) { pointer-events: auto; }

  .retry-btn {
    font-size: 0.7rem;
    font-weight: 500;
    color: #ffffff;
    background: rgba(239, 68, 68, 0.4);
    border: 1px solid rgba(239, 68, 68, 0.6);
    padding: 0.1rem 0.45rem;
    border-radius: 4px;
    cursor: pointer;
  }

  .retry-btn:hover { background: rgba(239, 68, 68, 0.65); }
  /* Pistas interactivas y activas */
  .is-active-track {
    background: #252538 !important;
    border-color: #6366f1 !important;
  }

  .tag-playing {
    font-size: 0.65rem;
    font-weight: 700;
    color: #818cf8;
    background: rgba(99, 102, 241, 0.18);
    padding: 0.15rem 0.4rem;
    border-radius: 4px;
    letter-spacing: 0.04em;
    flex-shrink: 0;
  }

  .song-row {
    cursor: pointer;
  }


  @media (max-width: 640px) {
    .shell { padding-bottom: 9rem; }
    .player-dock {
      left: calc(var(--sidebar-width) + 8px);
      right: 8px;
      bottom: 8px;
    }
    .album-grid {
      grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
    }
  }
</style>
