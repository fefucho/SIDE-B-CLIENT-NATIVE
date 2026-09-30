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
  import { CatalogController, emptyCatalogData, type CatalogData } from "$lib/catalog/controller";
  import { HomeController, emptyHomeData } from "$lib/home/controller";
  import SearchView from "$lib/components/search/SearchView.svelte";
  import { SearchController, emptySearchData, type SearchMode } from "$lib/search/controller";
  import { PlaybackController, emptyPlaybackData, parseDuration } from "$lib/player/controller";
  import FullscreenNowPlaying from "$lib/components/fullscreen/FullscreenNowPlaying.svelte";
  import { invoke } from "@tauri-apps/api/core";
  import { listen, type UnlistenFn } from "@tauri-apps/api/event";
  import type {
    SongDto,
    BrowseCardDto,
    BackendStatusDto,
    AuthStatusDto,
    CommandError,
  } from "$lib/types";

  type PrimaryNav = "home" | "search" | "library" | "likes" | "history";
  type ActiveView = "feed" | "search_results" | "album_detail" | "artist_detail" | "catalog" | "library" | "playlist_detail" | "history";

  let primaryNav = $state<PrimaryNav>("home");
  let activeView = $state<ActiveView>("feed");
  let sidebarCollapsed = $state(false);
  let isFullscreenOpen = $state(false);
  let accountData = $state(emptyAccountData());
  const account = new AccountController((command, args) => invoke(command, args), data => { accountData = data; });
  let lastPlaylistId = $state<string | null>(null);

  let homeData = $state(emptyHomeData());
  const home = new HomeController((command, args) => invoke(command, args), data => { homeData = data; });
  const homePage = $derived(homeData.page);
  let searchData = $state(emptySearchData());
  const search = new SearchController((command, args) => invoke(command, args), data => { searchData = data; });

  let catalogData = $state(emptyCatalogData());
  const catalog = new CatalogController((command, args) => invoke(command, args), data => { catalogData = data; });
  const selectedAlbum = $derived(catalogData.album);
  const lastAlbumBrowseId = $derived(catalogData.albumId);
  const isAlbumLoading = $derived(catalogData.albumLoading);
  const albumError = $derived(catalogData.albumError);
  const selectedArtist = $derived(catalogData.artist);
  const lastArtistBrowseId = $derived(catalogData.artistId);
  const isArtistLoading = $derived(catalogData.artistLoading);
  const artistError = $derived(catalogData.artistError);
  const catalogItems = $derived(catalogData.items);
  const catalogTarget = $derived(catalogData.target);
  const isCatalogLoading = $derived(catalogData.loading);
  const catalogError = $derived(catalogData.error);
  type NavigationSnapshot = {
    view: ActiveView; primary: PrimaryNav; scroll: number;
    details: CatalogData; playlistId: string | null;
  };
  let navigationHistory: NavigationSnapshot[] = [];

  // Estado Backend
  let backendStatus = $state<BackendStatusDto | null>(null);
  let statusError = $state<string | null>(null);
  let isRetryingInit = $state(false);
  let authStatus = $state<AuthStatusDto>({ state: "guest", name: null, email: null, thumbnail: null, message: null });

  let playbackState = $state(emptyPlaybackData());
  let playbackError = $state<string | null>(null);
  const player = new PlaybackController((command, args) => invoke(command, args),
    (name, handler) => listen(name, handler), snapshot => {
      playbackState = snapshot.state;
      playbackError = snapshot.error;
    });
  const playerBarState = $derived({ ...playbackState, error: playbackError || playbackState.error });

  let sessionRevision = 0;

  function applyAuthStatus(next: AuthStatusDto) {
    const changedAccount = (next.state === "guest" || next.state === "ready")
      && (authStatus.state !== next.state || authStatus.email !== next.email);
    authStatus = next;
    if (changedAccount) {
      home.reset();
      search.reset();
      catalog.reset();
      ++sessionRevision;
      player.invalidatePending();
      account.reset(next.state === "ready");
      lastPlaylistId = null;
      navigationHistory = [];
      activeView = primaryNav === "home" ? "feed" : primaryNav === "search" ? "search_results" : primaryNav === "history" ? "history" : primaryNav === "likes" ? "playlist_detail" : "library";
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

  function loadHomePage(chipParams: string | null = null) { return home.load(chipParams); }
  function loadMoreHome() { return home.loadMore(); }
  function executeSearch(targetQuery: string, mode: SearchMode = searchData.mode) {
    if (!targetQuery.trim()) return;
    invalidateDetails(); navigationHistory = [];
    primaryNav = "search"; activeView = "search_results";
    scrollContentToTop();
    void search.execute(targetQuery, mode);
  }

  function handleSwitchNav(nav: PrimaryNav) {
    if (nav === 'library' || nav === 'likes' || nav === 'history') { openAccountNav(nav); return; }
    navigationHistory = [];
    invalidateDetails();
    primaryNav = nav;
    if (nav === "home") {
      activeView = "feed";
      if (!homePage && !homeData.loading) {
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
    if (searchData.mode === mode && activeView === "search_results") return;
    activeView = "search_results";
    search.setMode(mode);
  }
  function handleQuickSearch(query: string) { executeSearch(query); }

  function invalidateDetails() { catalog.invalidate(); }

  function pushNavigation() {
    navigationHistory.push({ view: activeView, primary: primaryNav,
      scroll: document.querySelector<HTMLElement>(".content-column")?.scrollTop ?? 0,
      details: catalog.data, playlistId: lastPlaylistId });
    if (navigationHistory.length > 40) navigationHistory.shift();
    invalidateDetails();
  }

  async function openAlbumDetail(id: string, _origin?: "home" | "search", remember = true) {
    if (!id.trim()) return;
    if (remember) pushNavigation();
    activeView = "album_detail"; scrollContentToTop();
    await catalog.openAlbum(id);
  }
  async function openArtistDetail(id: string, remember = true) {
    if (!id.trim()) return;
    if (remember) pushNavigation();
    activeView = "artist_detail"; scrollContentToTop();
    await catalog.openArtist(id);
  }
  async function openCatalog(id: string, params: string | null, title: string, remember = true) {
    if (!id.trim()) return;
    if (remember) pushNavigation();
    activeView = "catalog"; scrollContentToTop();
    await catalog.openGrid(id, params, title);
  }

  async function goBackFromDetail() {
    invalidateDetails();
    const previous = navigationHistory.pop();
    if (!previous) { handleSwitchNav(primaryNav === 'likes' ? 'home' : primaryNav); return; }
    activeView = previous.view; primaryNav = previous.primary;
    catalog.restore(previous.details);
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
    catalog.updateAlbum(current => current.browseId === album.browseId ? { ...current, inLibrary: save } : current);
    for (const snapshot of navigationHistory) if (snapshot.details.album?.browseId === album.browseId) snapshot.details.album = { ...snapshot.details.album, inLibrary: save };
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
    catalog.updateArtist(current => current.channelId === artist.channelId ? { ...current, subscribed: subscribe } : current);
    for (const snapshot of navigationHistory) if (snapshot.details.artist?.channelId === artist.channelId) snapshot.details.artist = { ...snapshot.details.artist, subscribed: subscribe };
    void account.load('artists');
  }

  async function playCollection(items: SongDto[], index: number, source: {kind:string;id:string;title:string}, shuffle = false, fallbackThumbnail: string | null = null, fallbackArtist = "") {
    const indexed = items.map((song, originalIndex) => ({ song, originalIndex })).filter(({ song }) => song.videoId.trim());
    const entries = indexed.map(({ song }) => ({
      entryId: crypto.randomUUID(), videoId: song.videoId, title: song.title,
      artists: song.artists || fallbackArtist, thumbnail: song.thumbnail || fallbackThumbnail,
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
    await player.playSong(track, { queueItems: entries, queueIndex: startIndex, queueSource: source });
  }

  function playAlbum(index: number, shuffle = false) {
    if (selectedAlbum) void playCollection(selectedAlbum.items, index,
      {kind: "album", id: selectedAlbum.browseId, title: selectedAlbum.title}, shuffle, selectedAlbum.thumbnail, selectedAlbum.artist ?? "").catch(() => {});
  }

  function playArtist(index: number, shuffle = false) {
    if (selectedArtist) void playCollection(selectedArtist.topSongs, index,
      {kind: "artist", id: selectedArtist.channelId, title: selectedArtist.name}, shuffle, selectedArtist.thumbnail, selectedArtist.name).catch(() => {});
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
    const identity = catalog.captureIdentity();
    try {
      const items = await invoke<SongDto[]>("get_artist_radio", { playlistId: artist.radioPlaylistId });
      if (revision !== sessionRevision || !catalog.isCurrentIdentity(identity)) return;
      await playCollection(items, 0, {kind: "radio", id: artist.radioPlaylistId, title: `Mix de ${artist.name}`});
    } catch (error) { throw new Error(extractErrorMessage(error, "No se pudo iniciar el mix.")); }
  }

  async function handlePlaySong(videoId: string,
    meta?: { title?: string; artists?: string; thumbnail?: string | null; duration?: string | null }) {
    await player.playSong({ videoId, title: meta?.title ?? "Canción", artists: meta?.artists ?? "",
      thumbnail: meta?.thumbnail ?? null, duration: meta?.duration ?? null }).catch(() => {});
  }
  function playQueueIndex(index: number) { void player.playQueueIndex(index).catch(() => {}); }
  function handleNext() { return player.next(); }
  function handlePrevious() { return player.previous(); }
  function handleTogglePlay() { return player.toggle().catch(() => {}); }
  function handleRetryPlayback() { return player.retry().catch(() => {}); }
  function handleSeek(seconds: number) { return player.seek(seconds); }
  function handleVolumeChange(volume: number) { return player.setVolume(volume); }

  let unlistenAuth: UnlistenFn | null = null;
  let mounted = false;

  onMount(() => {
    mounted = true;
    checkBackendStatus();
    invoke<AuthStatusDto>("get_auth_status").then(applyAuthStatus).catch(() => {});
    window.addEventListener("keydown", handleWindowKeydown);

    void player.connect();

    listen<AuthStatusDto>("auth-status-changed", (event) => applyAuthStatus(event.payload))
      .then((unlisten) => { if (mounted) unlistenAuth = unlisten; else unlisten(); });

    return () => {
      mounted = false;
      account.reset(false);
      window.removeEventListener("keydown", handleWindowKeydown);
      void player.dispose();
      home.reset();
      search.reset();
      catalog.reset();
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
      selectedChipParams={homeData.chipParams}
      isLoading={homeData.loading}
      error={homeData.error}
      hasMore={Boolean(homePage?.continuation)}
      isLoadingMore={homeData.loadingMore}
      moreError={homeData.moreError}
      onLoadMore={() => loadMoreHome()}
      onOpenArtist={openArtistDetail}
      onOpenPlaylist={openPlaylist}
      onOpenCatalog={openCatalog}
      onSelectChip={(params) => loadHomePage(params)}
      onRetry={() => loadHomePage(homeData.chipParams)}
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
    <SearchView data={searchData} backendReady={backendStatus?.ready ?? false}
      currentTrackId={playbackState.currentTrack?.videoId ?? null} isPlaying={playbackState.isPlaying}
      onSubmit={executeSearch} onQueryChange={(query) => search.setQuery(query)}
      onModeChange={handleSwitchSearchMode} onQuickSearch={handleQuickSearch}
      onPlaySong={(song) => handlePlaySong(song.videoId, song)}
      onOpenAlbum={(album) => openAlbumDetail(album.id, "search")} />
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

  @media (max-width: 640px) {
    .shell { padding-bottom: 9rem; }
    .player-dock {
      left: calc(var(--sidebar-width) + 8px);
      right: 8px;
      bottom: 8px;
    }
  }
</style>
