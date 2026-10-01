<script lang="ts">
  import PlayerIcon from "../player/PlayerIcon.svelte";
  import type { PlaybackStateDto, QueueEntryDto } from "$lib/types";
  import ArtistCredits from "$lib/components/ArtistCredits.svelte";

  type Panel = "queue" | "lyrics" | "related";
  interface Props {
    playback: PlaybackStateDto;
    onSelectQueue: (index: number) => void;
    onClose: () => void;
    selectedPanel?: Panel;
    onSelectPanel?: (panel: Panel) => void;
    onOpenArtist?: (id: string) => void;
    onOpenAlbum?: (id: string) => void;
    onOpenMenu?: (event: MouseEvent) => void;
    onQueueContextMenu?: (event: MouseEvent, entry: QueueEntryDto) => void;
    loggedIn?: boolean;
    liked?: boolean;
    likePending?: boolean;
    onToggleLike?: () => void;
    onRetryRadio?: () => void;
  }

  let {
    playback, onSelectQueue, onClose, selectedPanel, onSelectPanel, onOpenArtist, onOpenAlbum,
    onOpenMenu, onQueueContextMenu, loggedIn = false, liked = false, likePending = false,
    onToggleLike, onRetryRadio,
  }: Props = $props();
  let localPanel = $state<Panel>("queue");
  let failedArtworkUrl = $state<string | null>(null);
  const panel = $derived(selectedPanel ?? localPanel);
  const currentTrack = $derived(playback.currentTrack);
  const queueTitle = $derived(playback.queue.source?.kind === 'radio'
    ? `Radio de ${playback.queue.source.title || currentTrack?.title || 'esta canción'}`
    : playback.queue.source?.title || 'Cola de reproducción');

  function formatDuration(seconds: number | null) {
    if (seconds === null || !Number.isFinite(seconds) || seconds <= 0) return '';
    const total = Math.floor(seconds);
    return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, '0')}`;
  }

  const panels: { id: Panel; label: string }[] = [
    { id: "queue", label: "Cola" },
    { id: "lyrics", label: "Letras" },
    { id: "related", label: "Relacionado" },
  ];

  function selectPanel(value: Panel) {
    localPanel = value;
    onSelectPanel?.(value);
  }
  function handleContextMenu(event: MouseEvent, entry: QueueEntryDto) {
    if (!onQueueContextMenu) return;
    event.preventDefault();
    onQueueContextMenu(event, entry);
  }
</script>

<svelte:head><title>{currentTrack?.title ? `${currentTrack.title} · Side B` : "Reproducción · Side B"}</title></svelte:head>

<section id="fullscreen-now-playing" class="fullscreen" aria-label="Pantalla completa de reproducción">
  {#if currentTrack?.thumbnail && failedArtworkUrl !== currentTrack.thumbnail}
    <div class="backdrop-art" style={`background-image: url("${currentTrack.thumbnail}")`} aria-hidden="true"></div>
  {/if}
  <div class="backdrop-shade" aria-hidden="true"></div>

  <button type="button" class="close-button" onclick={onClose} aria-label="Cerrar pantalla completa" title="Cerrar pantalla completa">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M6 6 18 18M18 6 6 18" /></svg>
  </button>

  <div class="layout">
    <div class="art-column">
      <div class="art-block">
        <div class="artwork">
          {#if currentTrack?.thumbnail && failedArtworkUrl !== currentTrack.thumbnail}
            <img src={currentTrack.thumbnail} alt={`Portada de ${currentTrack.title}`} onerror={() => failedArtworkUrl = currentTrack?.thumbnail ?? null} />
          {:else}
            <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M10 5v12.1a4 4 0 1 1-2-3.46V3l12-2v14.1a4 4 0 1 1-2-3.46V4.4z" /></svg>
          {/if}
        </div>
        <div class="track-info" role="group" aria-label="Canción actual" oncontextmenu={(event) => { if (onOpenMenu && currentTrack) { event.preventDefault(); onOpenMenu(event); } }}>
          <div class="title-line">
            <h1 title={currentTrack?.title ?? "Sin reproducción"}>{currentTrack?.title ?? "Sin reproducción"}</h1>
            {#if loggedIn && onToggleLike && currentTrack}
              <button class="like-button" type="button" class:liked disabled={likePending || playback.isLoading} aria-pressed={liked} aria-label={liked ? "Quitar de Me Gusta" : "Me Gusta"} title={liked ? "Quitar de Me Gusta" : "Me Gusta"} onclick={onToggleLike}>
                <svg viewBox="0 0 24 24" aria-hidden="true" fill={liked ? "currentColor" : "none"} stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M20.8 8.7c0 4.2-6.4 9.1-8.8 11-2.4-1.9-8.8-6.8-8.8-11a4.9 4.9 0 0 1 8.8-3.1 4.9 4.9 0 0 1 8.8 3.1Z" /></svg>
              </button>
            {/if}
            {#if onOpenMenu && currentTrack}<button class="more-button" type="button" aria-label="Más opciones de la canción" title="Más opciones" onclick={onOpenMenu}><svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg></button>{/if}
          </div>
          <div class="artist-line">
            <ArtistCredits artistRuns={currentTrack?.artistRuns} artists={currentTrack?.artists ?? "Seleccioná una canción"} artistId={currentTrack?.artistId} {onOpenArtist} album={currentTrack?.album} albumId={currentTrack?.albumId} {onOpenAlbum} />
          </div>
        </div>
      </div>
    </div>

    <div class="side-column">
      <div class="tablist" role="tablist" aria-label="Panel de reproducción">
        {#each panels as item (item.id)}
          <button type="button" id={`fullscreen-tab-${item.id}`} role="tab" aria-selected={panel === item.id} aria-controls="fullscreen-panel" class:active={panel === item.id} onclick={() => selectPanel(item.id)}>
            <PlayerIcon name={item.id} size={14} />
            {item.label}
          </button>
        {/each}
      </div>

      <div id="fullscreen-panel" class="panel" role="tabpanel" aria-labelledby={`fullscreen-tab-${panel}`}>
        {#if panel === "queue"}
          <div class="queue-content">
            <header class="queue-heading">
              <div class="queue-context"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M4 6h16M4 12h16M4 18h16" /></svg><span>{queueTitle}</span><span class="separator" aria-hidden="true">·</span><span class="count">{playback.queue.items.length} canciones</span></div>
              {#if playback.queue.radio?.loading}<span class="radio-state" role="status"><span class="spinner" aria-hidden="true"></span>Preparando radio…</span>
              {:else if playback.queue.radio?.error}<div class="radio-error" role="alert"><span>{playback.queue.radio.error}</span>{#if playback.queue.radio.canRetry && onRetryRadio}<button type="button" onclick={onRetryRadio}>Reintentar</button>{/if}</div>{/if}
            </header>
            {#if playback.queue.items.length}
              <div class="queue-list" aria-label="Pistas en cola">
                {#each playback.queue.items as entry, index (entry.entryId)}
                  <div class="queue-row" role="group" aria-label={`Opciones de ${entry.title}`} class:current={index === playback.queue.currentIndex} oncontextmenu={(event) => handleContextMenu(event, entry)}>
                    <button type="button" class="queue-select" aria-current={index === playback.queue.currentIndex ? "true" : undefined} aria-label={`Reproducir ${entry.title}`} onclick={() => onSelectQueue(index)}>
                      <span class="queue-index">{#if index === playback.queue.currentIndex}<svg viewBox="0 0 24 24" aria-label={playback.isPlaying ? 'Sonando' : 'Pausado'} fill="currentColor"><path d="M3 9v6h4l5 5V4L7 9zm12.5 3a4 4 0 0 0-2-3.46v6.92a4 4 0 0 0 2-3.46" /></svg>{:else}{index + 1}{/if}</span>
                      <span class="queue-art">{#if entry.thumbnail}<img src={entry.thumbnail} alt="" loading="lazy" />{:else}<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M10 5v12.1a4 4 0 1 1-2-3.46V3l12-2v14.1a4 4 0 1 1-2-3.46V4.4z" /></svg>{/if}</span>
                      <span class="queue-meta"><span class="queue-title">{entry.title}</span><ArtistCredits artistRuns={entry.artistRuns} artists={entry.artists} album={entry.album} /></span>
                      <span class="queue-duration">{formatDuration(entry.duration)}</span>
                    </button>
                    {#if onQueueContextMenu}<button type="button" class="row-menu" aria-label={`Más opciones para ${entry.title}`} title="Más opciones" onclick={(event) => onQueueContextMenu?.(event, entry)}><svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg></button>{/if}
                  </div>
                {/each}
              </div>
            {:else}
              <div class="empty-panel"><svg class="empty-icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M4 6h16M4 12h16M4 18h16" /></svg><p>No hay pistas en la cola</p></div>
            {/if}
          </div>
        {:else if panel === "lyrics"}
          <div class="empty-panel"><svg class="empty-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true"><path d="M5 6h14M5 11h12M5 16h8M5 20h5" /></svg><p>Las letras todavía no están disponibles en Windows.</p></div>
        {:else}
          <div class="empty-panel"><svg class="empty-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true"><path d="M4 7h11M4 12h11M4 17h11M18 5v11m-2-2 2 2 2-2" /></svg><p>Las recomendaciones todavía no están disponibles en Windows.</p></div>
        {/if}
      </div>
    </div>
  </div>
</section>

<style>
  .fullscreen { position: fixed; inset: 0 0 0 var(--sidebar-width, 0px); z-index: 80; box-sizing: border-box; container-type: inline-size; height: 100dvh; max-height: 100dvh; overflow: hidden; isolation: isolate; color: #fff; background: #1b1b1e; }
  .backdrop-art { position: absolute; inset: -12%; z-index: -2; background-size: cover; background-position: center; filter: blur(75px) brightness(.55); transform: scale(1.08); pointer-events: none; }
  .backdrop-shade { position: absolute; inset: 0; z-index: -1; background: linear-gradient(180deg, rgb(12 12 15 / 70%), rgb(17 17 20 / 83%)); pointer-events: none; }
  .close-button { position: absolute; top: 44px; right: 12px; z-index: 2; display: grid; place-items: center; width: 32px; height: 32px; padding: 6px; border: 0; border-radius: 8px; color: rgb(255 255 255 / 75%); background: rgb(255 255 255 / 9%); cursor: pointer; }
  .close-button:hover { color: #fff; background: rgb(255 255 255 / 16%); }.close-button svg { width: 18px; height: 18px; }
  .layout {
    --inset: clamp(24px, 3.5cqw, 48px);
    --column-gap: clamp(24px, 2.8cqw, 40px);
    --available-width: calc(100cqw - var(--inset) * 2 - var(--column-gap));
    --max-art: max(100px, calc(100dvh - 264px));
    /* Preserve the Mac 600/686 panel/artwork balance on taller, wider windows. */
    --panel-cap: max(600px, calc(var(--max-art) * .875));
    --panel-max: max(300px, calc(var(--available-width) * .56));
    --panel-width: min(var(--panel-max), max(min(340px, var(--panel-max)), min(var(--panel-cap), calc(var(--available-width) * .52))));
    /* Once artwork reaches its height limit, its column stops accumulating empty space. */
    --art-column-width: max(100px, min(calc(var(--available-width) - var(--panel-width)), calc(var(--max-art) / .9)));
    box-sizing: border-box;
    display: grid;
    grid-template-columns: var(--art-column-width) var(--panel-width);
    align-items: stretch;
    gap: var(--column-gap);
    width: calc(var(--art-column-width) + var(--panel-width) + var(--column-gap) + var(--inset) * 2);
    max-width: 100%;
    height: 100dvh;
    max-height: 100dvh;
    min-width: 0;
    min-height: 0;
    margin-inline: auto;
    padding: 52px var(--inset) 112px;
    overflow: hidden;
  }
  .art-column { display: grid; place-items: center; min-width: 0; min-height: 0; overflow: hidden; }
  .art-block { width: min(90%, max(100px, calc(100dvh - 264px))); max-width: 100%; min-width: 0; max-height: 100%; }
  .artwork { display: grid; place-items: center; width: 100%; aspect-ratio: 1; max-height: calc(100dvh - 264px); overflow: hidden; border-radius: 16px; color: rgb(255 255 255 / 42%); background: rgb(255 255 255 / 8%); box-shadow: 0 10px 30px rgb(0 0 0 / 42%); }
  .artwork img { display: block; width: 100%; height: 100%; object-fit: cover; }.artwork svg { width: 22%; max-width: 80px; }
  .track-info { box-sizing: border-box; display: flex; width: 100%; height: 68px; flex-direction: column; justify-content: center; gap: 4px; margin-top: 16px; }
  .title-line { display: flex; min-width: 0; align-items: center; gap: 8px; }.title-line h1 { flex: 1; min-width: 0; overflow: hidden; margin: 0; font-size: 28px; font-weight: 700; line-height: 1.2; text-overflow: ellipsis; white-space: nowrap; }
  .artist-line { display: flex; min-width: 0; align-items: center; overflow: hidden; color: rgb(255 255 255 / 76%); font-size: 17.5px; font-weight: 500; white-space: nowrap; }
  .like-button, .more-button { display: grid; flex: 0 0 30px; place-items: center; width: 30px; height: 30px; padding: 6px; border: 0; border-radius: 50%; color: rgb(255 255 255 / 70%); background: transparent; cursor: pointer; }.like-button svg, .more-button svg { width: 18px; height: 18px; }.like-button:hover, .more-button:hover { color: white; background: rgb(255 255 255 / 10%); }.like-button.liked { color: #d06c70; }.like-button:disabled { opacity: .5; cursor: wait; }
  .side-column { display: flex; min-width: 0; min-height: 0; height: 100%; flex-direction: column; align-items: center; gap: 14px; overflow: hidden; }
  .tablist { box-sizing: border-box; display: flex; flex: 0 0 40px; height: 40px; align-items: center; gap: 0; max-width: 100%; padding: 4px; border-radius: 999px; background: #343437; box-shadow: inset 0 0 0 1px rgb(255 255 255 / 12%); }
  .tablist button { display: inline-flex; flex: none; align-items: center; justify-content: center; gap: 7px; height: 32px; padding: 8px 16px; border: 0; border-radius: 999px; color: rgb(255 255 255 / 65%); background: transparent; font: inherit; font-size: 13px; font-weight: 500; line-height: 16px; white-space: nowrap; cursor: pointer; }.tablist button.active { color: #fff; background: #a33d45; font-weight: 650; }.tablist button:hover:not(.active) { color: #fff; }
  .panel { box-sizing: border-box; display: flex; width: 100%; min-width: 0; min-height: 0; flex: 1; overflow: hidden; }
  .queue-content { display: flex; width: 100%; min-width: 0; min-height: 0; flex: 1; flex-direction: column; overflow: hidden; }.queue-heading { display: flex; flex: none; min-width: 0; flex-direction: column; gap: 8px; padding: 2px 8px 8px; }.queue-context { display: flex; min-width: 0; align-items: center; gap: 8px; color: rgb(255 255 255 / 90%); font-size: 12px; font-weight: 650; }.queue-context svg { flex: 0 0 14px; width: 14px; height: 14px; }.queue-context > span:nth-child(2) { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }.count { flex: none; color: rgb(255 255 255 / 53%); font-size: 11px; font-weight: 500; white-space: nowrap; }
  .radio-state, .radio-error { display: flex; align-items: center; gap: 8px; color: rgb(255 255 255 / 67%); font-size: 11px; }.radio-error { color: #ffb7bb; }.radio-error button { flex: none; padding: 3px 8px; border: 1px solid rgb(255 255 255 / 15%); border-radius: 999px; color: #fff; background: rgb(255 255 255 / 8%); font: inherit; cursor: pointer; }.spinner { width: 12px; height: 12px; border: 2px solid rgb(255 255 255 / 24%); border-top-color: #d06c70; border-radius: 50%; animation: spin .8s linear infinite; }@keyframes spin { to { transform: rotate(360deg); } }
  .queue-list { min-width: 0; min-height: 0; flex: 1; overflow-y: auto; overscroll-behavior: contain; scrollbar-color: rgb(255 255 255 / 28%) transparent; scrollbar-width: thin; }
  .queue-row { display: flex; min-width: 0; align-items: center; gap: 6px; margin-bottom: 2px; padding: 0 4px; border-radius: 8px; }.queue-row:hover, .queue-row.current { background: rgb(255 255 255 / 7%); }.queue-select { box-sizing: border-box; display: flex; min-width: 0; flex: 1; height: 46px; align-items: center; gap: 6px; padding: 3px 2px; border: 0; border-radius: 7px; color: inherit; background: transparent; font: inherit; text-align: left; cursor: pointer; }.queue-art { display: grid; flex: 0 0 36px; margin-right: 9px; place-items: center; width: 36px; height: 36px; overflow: hidden; border-radius: 6px; color: rgb(255 255 255 / 58%); background: rgb(255 255 255 / 10%); }.queue-art img { width: 100%; height: 100%; object-fit: cover; }.queue-art svg { width: 19px; height: 19px; }.queue-meta { display: flex; min-width: 0; flex: 1; flex-direction: column; gap: 3px; }.queue-title { display: block; min-width: 0; overflow: hidden; padding: 0; border: 0; color: rgb(255 255 255 / 92%); background: transparent; font: inherit; font-size: 13px; font-weight: 500; line-height: 16px; text-align: left; text-overflow: ellipsis; white-space: nowrap; }.current .queue-title { font-weight: 650; }.queue-meta :global(.artist-credits) { color: rgb(255 255 255 / 60%); font-size: 11.5px; line-height: 14px; }
  .queue-index { display: grid; flex: 0 0 22px; place-items: center; color: rgb(255 255 255 / 55%); font-size: 11.5px; }.queue-index svg { width: 12px; height: 12px; color: white; }.queue-duration { flex: 0 0 36px; color: rgb(255 255 255 / 45%); font-size: 11.5px; font-variant-numeric: tabular-nums; text-align: right; }
  .row-menu { display: grid; flex: 0 0 30px; place-items: center; width: 30px; height: 30px; border: 0; border-radius: 6px; color: rgb(255 255 255 / 60%); background: transparent; cursor: pointer; }.row-menu svg { width: 16px; height: 16px; }.row-menu:hover { color: #fff; background: rgb(255 255 255 / 10%); }
  .empty-panel { display: flex; min-width: 0; min-height: 0; flex: 1; flex-direction: column; align-items: center; justify-content: center; gap: 12px; padding: 20px; color: rgb(255 255 255 / 55%); text-align: center; }.empty-panel p { max-width: 32ch; margin: 0; font-size: 14px; }.empty-icon { width: 36px; height: 36px; color: rgb(255 255 255 / 28%); }
  button:focus-visible { outline: 2px solid #d06c70; outline-offset: 3px; }
  @media (prefers-reduced-motion: reduce) { .spinner { animation: none; } }
</style>
