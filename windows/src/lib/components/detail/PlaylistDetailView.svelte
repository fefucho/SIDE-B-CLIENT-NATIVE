<script lang="ts">
  import type { AccountPlaylistDto as PlaylistDetailDto, AccountSongDto as SongDto } from "$lib/account/types";
  import AccountTrackTable from "../library/AccountTrackTable.svelte";
  import DescriptionModal from "./DescriptionModal.svelte";

  type PlaylistViewDto = PlaylistDetailDto & {
    subtitle?: string | null;
    description?: string | null;
    inLibrary?: boolean;
    owned?: boolean;
  };

  interface Props {
    playlist: PlaylistViewDto | null; loading: boolean; loadingMore: boolean; error: string | null;
    loggedIn: boolean; currentTrackId: string | null; isPlaying: boolean; likedIds: Set<string>; pendingIds: Set<string>;
    onBack: () => void; onRetry: () => void; onLoadMore: () => void; onPlay: (index: number) => void;
    onToggleLike: (track: SongDto) => void; onToggleSaved: (track: SongDto) => void;
    onToggleLibrary: () => Promise<void>; onOpenArtist: (id: string) => void; onOpenAlbum: (id: string) => void;
    onLogin: () => void;
  }
  let {
    playlist, loading, loadingMore, error, loggedIn, currentTrackId, isPlaying, likedIds, pendingIds,
    onBack, onRetry, onLoadMore, onPlay, onToggleLike, onToggleSaved, onToggleLibrary, onOpenArtist, onOpenAlbum, onLogin,
  }: Props = $props();
  let showDescription = $state(false);
  let failedArtwork = $state(false);
  let saving = $state(false);
  let actionError = $state<string | null>(null);
  const canSavePlaylist = $derived(Boolean(playlist && loggedIn && playlist.id !== "LM" && !playlist.owned));

  async function toggleLibrary() {
    if (!canSavePlaylist || saving) return;
    saving = true;
    actionError = null;
    try { await onToggleLibrary(); }
    catch (cause) { actionError = cause instanceof Error ? cause.message : String(cause); }
    finally { saving = false; }
  }
</script>

<main class="playlist-page" aria-busy={loading}>
  <div class="topline"><button class="back" type="button" onclick={onBack}>‹ <span>Volver</span></button>{#if loading && playlist}<span class="updating" role="status">Actualizando playlist…</span>{/if}</div>
  {#if loading && !playlist}
    <div class="skeleton" role="status" aria-label="Cargando playlist"><div class="sk-art"></div><div class="sk-info"><i></i><i></i><i></i></div></div>
  {:else if !playlist && error}
    <section class="state" role="alert"><div class="state-icon">!</div><h2>No se pudo cargar la playlist</h2><p>{error}</p><button class="primary" type="button" onclick={onRetry}>Reintentar</button></section>
  {:else if !playlist && !loggedIn}
    <section class="state"><div class="state-icon">♙</div><h2>Iniciá sesión para abrir esta playlist</h2><button class="primary" type="button" onclick={onLogin}>Iniciar sesión</button></section>
  {:else if !playlist}
    <section class="state"><div class="state-icon">♫</div><h2>Playlist no disponible</h2><p>Vuelve atrás o intenta cargarla de nuevo.</p><button class="primary" type="button" onclick={onRetry}>Reintentar</button></section>
  {:else}
    <div class="scroll-content">
      <header class="playlist-header">
        {#if playlist.thumbnail && !failedArtwork}<img class="artwork" src={playlist.thumbnail} alt={`Portada de ${playlist.title}`} loading="eager" onerror={() => failedArtwork = true} />{:else}<div class="artwork placeholder" aria-hidden="true">{playlist.id === "LM" ? "♥" : "♫"}</div>{/if}
        <div class="metadata">
          <div class="eyebrow">{playlist.id === "LM" ? "COLECCIÓN" : "PLAYLIST"}</div>
          <h1>{playlist.title}</h1>
          {#if playlist.subtitle}<p class="subtitle">{playlist.subtitle}</p>{/if}
          {#if playlist.description}<button class="description" type="button" onclick={() => showDescription = true} aria-label="Leer descripción completa">{playlist.description}<span> más</span></button>{/if}
          {#if !playlist.subtitle}<p class="count">{playlist.items.length}{playlist.continuation ? '+' : ''} canciones</p>{/if}
          <div class="actions">
            <button class="play" type="button" disabled={!playlist.items.length} onclick={() => onPlay(0)}>▶ <span>Reproducir</span></button>
            {#if canSavePlaylist}<button class="save" type="button" disabled={saving} aria-pressed={Boolean(playlist.inLibrary)} onclick={toggleLibrary}>{playlist.inLibrary ? "▣ En biblioteca" : "▢ Guardar"}</button>{/if}
          </div>
        </div>
      </header>
      {#if actionError}<div class="inline-error" role="alert">{actionError}</div>{/if}
      {#if error && playlist}<div class="inline-error" role="alert">No se pudo actualizar: {error}<button type="button" onclick={onRetry}>Reintentar</button></div>{/if}
      {#if playlist.items.length}
        <AccountTrackTable items={playlist.items} {currentTrackId} {isPlaying} onPlay={onPlay} onOpenArtist={onOpenArtist} onOpenAlbum={onOpenAlbum} {likedIds} {pendingIds} onToggleLike={loggedIn ? onToggleLike : undefined} onToggleSaved={loggedIn ? onToggleSaved : undefined} />
      {:else if loadingMore}<div class="loading-inline" role="status">Cargando canciones…</div>
      {:else}<p class="no-tracks">Esta playlist todavía no tiene canciones disponibles.</p>{/if}
      {#if playlist.continuation}<div class="more"><button type="button" disabled={loadingMore} onclick={onLoadMore}>{loadingMore ? "Cargando…" : "Cargar más canciones"}</button></div>{/if}
      <div class="bottom-space" aria-hidden="true"></div>
    </div>
  {/if}
  {#if showDescription && playlist?.description}<DescriptionModal title={playlist.title} description={playlist.description} onClose={() => showDescription = false} />{/if}
</main>

<style>
  .playlist-page { position: relative; box-sizing: border-box; min-width: 0; min-height: 100%; color: #f7f7f8; background: var(--sideb-background, #1b1b1e); }
  .topline { position: sticky; z-index: 2; top: 0; display: flex; min-height: 38px; align-items: center; justify-content: space-between; padding: 0 20px; background: linear-gradient(#1b1b1e 75%, transparent); }
  .back { padding: 4px 8px; border: 0; border-radius: 6px; color: #dddde2; background: transparent; font: inherit; font-size: 13px; cursor: pointer; }.back:hover { background: var(--sideb-surface); }.back:first-letter { font-size: 20px; vertical-align: -1px; }
  .updating { color: #aaaab1; font-size: 11px; }
  .playlist-header { display: flex; align-items: flex-start; gap: 24px; padding: 28px 32px 16px; }
  .artwork { box-sizing: border-box; width: 180px; height: 180px; flex: 0 0 180px; border-radius: 10px; object-fit: cover; background: var(--sideb-surface); box-shadow: 0 8px 18px #0006; }
  .placeholder { display: grid; place-items: center; color: #dddde2; font-size: 56px; }
  .metadata { display: flex; min-width: 0; min-height: 180px; flex-direction: column; align-items: flex-start; gap: 7px; }
  .eyebrow { color: #aaaab1; font-size: 11px; font-weight: 700; letter-spacing: 1.2px; }.metadata h1 { max-width: 100%; margin: 0; color: #f7f7f8; font-size: 32px; font-weight: 700; line-height: 1.15; overflow-wrap: anywhere; }
  .subtitle, .count { margin: 0; color: #b5b5bc; font-size: 12px; }.subtitle { font-size: 14px; font-weight: 500; }
  .description { display: -webkit-box; max-width: min(720px, 60vw); overflow: hidden; padding: 0; border: 0; color: #aaaab1; background: transparent; font: inherit; font-size: 12px; line-height: 17px; text-align: left; -webkit-box-orient: vertical; -webkit-line-clamp: 2; line-clamp: 2; cursor: pointer; }.description span { color: #f1f1f3; font-weight: 600; }.description:hover { color: #dedee2; }
  .actions { display: flex; flex-wrap: wrap; gap: 10px; margin-top: auto; padding-top: 8px; }.play, .save { min-height: 34px; padding: 7px 15px; border: 1px solid var(--sideb-surface-border); border-radius: 999px; color: white; background: var(--sideb-surface); font: inherit; font-size: 13px; font-weight: 600; cursor: pointer; }.play { border-color: transparent; background: var(--sideb-accent); }.play:hover, .save:hover { filter: brightness(1.12); }.play:disabled, .save:disabled { opacity: .55; cursor: wait; }
  .inline-error { display: flex; align-items: center; gap: 10px; margin: 0 32px 8px; padding: 8px 12px; border-radius: 7px; color: #ffd5d5; background: #9d303033; font-size: 12px; }.inline-error button { margin-left: auto; border: 0; color: inherit; background: transparent; font: inherit; text-decoration: underline; cursor: pointer; }
  .no-tracks, .loading-inline { margin: 0; padding: 20px 32px; color: #a6a6ad; font-size: 13px; }.loading-inline { text-align: center; }
  .more { display: flex; justify-content: center; padding: 18px 32px; }.more button { padding: 8px 16px; border: 1px solid var(--sideb-surface-border); border-radius: 999px; color: white; background: var(--sideb-surface); font: inherit; cursor: pointer; }.more button:disabled { opacity: .55; }
  .bottom-space { height: 130px; }
  .state { display: flex; min-height: 320px; flex-direction: column; align-items: center; justify-content: center; gap: 12px; padding: 24px; color: #b9b9c0; text-align: center; }.state h2 { margin: 0; color: #f3f3f5; font-size: 18px; }.state p { max-width: 50ch; margin: 0; font-size: 13px; }.state-icon { color: #ccc; font-size: 34px; }
  .primary { padding: 8px 15px; border: 0; border-radius: 999px; color: white; background: var(--sideb-accent); font: inherit; font-size: 13px; cursor: pointer; }
  .skeleton { display: flex; gap: 24px; padding: 20px 32px 22px; }.sk-art { width: 180px; height: 180px; flex: none; border-radius: 10px; background: #ffffff12; animation: pulse 1.3s ease-in-out infinite alternate; }.sk-info { display: flex; flex-direction: column; gap: 14px; padding-top: 8px; }.sk-info i { width: 260px; height: 15px; border-radius: 5px; background: #ffffff12; }.sk-info i:first-child { width: 90px; height: 11px; }.sk-info i:nth-child(2) { width: min(420px, 45vw); height: 30px; }
  @keyframes pulse { to { opacity: .5; } } button:focus-visible { outline: 2px solid var(--sideb-highlight); outline-offset: 3px; }
  @media (max-width: 640px) { .playlist-header { gap: 16px; padding: 20px; }.artwork { width: 128px; height: 128px; flex-basis: 128px; }.metadata { min-height: 128px; }.metadata h1 { font-size: 24px; }.description { max-width: 100%; }.skeleton { gap: 16px; padding: 16px 20px; }.sk-art { width: 128px; height: 128px; }.inline-error { margin-inline: 20px; } }
  @media (max-width: 480px) { .playlist-header { flex-direction: column; }.artwork { width: 180px; height: 180px; flex-basis: 180px; }.metadata { min-height: 0; }.actions { margin-top: 4px; } }
  @media (prefers-reduced-motion: reduce) { .sk-art { animation: none; } }
</style>
