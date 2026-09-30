<script lang="ts">
  import type { PlaybackStateDto } from "$lib/types";

  type Panel = "queue" | "lyrics" | "recommended";

  interface Props {
    playback: PlaybackStateDto;
    onSelectQueue: (index: number) => void;
    onClose: () => void;
  }

  let { playback, onSelectQueue, onClose }: Props = $props();
  let selectedPanel = $state<Panel>("queue");

  const panels: { id: Panel; label: string }[] = [
    { id: "queue", label: "Cola" },
    { id: "lyrics", label: "Letras" },
    { id: "recommended", label: "Relacionado" },
  ];
</script>

<section id="fullscreen-now-playing" class="fullscreen" aria-label="Pantalla completa de reproducción">
  {#if playback.currentTrack?.thumbnail}
    <div class="backdrop-art" style={`background-image: url("${playback.currentTrack.thumbnail}")`} aria-hidden="true"></div>
  {/if}
  <div class="backdrop-shade" aria-hidden="true"></div>

  <button type="button" class="close-button" onclick={onClose} aria-label="Cerrar pantalla completa" title="Cerrar pantalla completa">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M6 6 18 18M18 6 6 18" /></svg>
  </button>

  <div class="layout">
    <div class="art-column">
      <div class="art-block">
        <div class="artwork">
          {#if playback.currentTrack?.thumbnail}
            <img src={playback.currentTrack.thumbnail} alt={`Portada de ${playback.currentTrack.title}`} />
          {:else}
            <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M10 5v12.1a4 4 0 1 1-2-3.46V3l12-2v14.1a4 4 0 1 1-2-3.46V4.4z" /></svg>
          {/if}
        </div>
        <div class="track-info">
          <h1 title={playback.currentTrack?.title ?? "Sin reproducción"}>{playback.currentTrack?.title ?? "Sin reproducción"}</h1>
          <p title={playback.currentTrack?.artists ?? ""}>{playback.currentTrack?.artists || "Seleccioná una canción"}</p>
        </div>
      </div>
    </div>

    <div class="side-column">
      <div class="tablist" role="tablist" aria-label="Panel de reproducción">
        {#each panels as panel}
          <button
            type="button"
            id={`fullscreen-tab-${panel.id}`}
            role="tab"
            aria-selected={selectedPanel === panel.id}
            aria-controls="fullscreen-panel"
            class:active={selectedPanel === panel.id}
            onclick={() => (selectedPanel = panel.id)}
          >
            {#if panel.id === "queue"}
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M4 6h16M4 12h16M4 18h16" /></svg>
            {:else if panel.id === "lyrics"}
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M5 6h14M5 11h12M5 16h8M5 20h5" /></svg>
            {:else}
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M4 7h11M4 12h11M4 17h11M18 5v11m-2-2 2 2 2-2" /></svg>
            {/if}
            {panel.label}
          </button>
        {/each}
      </div>

      <div id="fullscreen-panel" class="panel" role="tabpanel" aria-labelledby={`fullscreen-tab-${selectedPanel}`}>
        {#if selectedPanel === "queue"}
          {#if playback.currentTrack}
            <div class="queue-content">
              <div class="queue-heading"><span>{playback.queue.source?.title ?? "Cola de reproducción"}</span><span>{playback.queue.items.length} canciones</span></div>
              {#each playback.queue.items as entry, index (entry.entryId)}
                {#if index === playback.queue.currentIndex}<div class="queue-label">REPRODUCIENDO AHORA</div>{:else if index === (playback.queue.currentIndex ?? -1) + 1}<div class="next-label">A CONTINUACIÓN</div>{/if}
                <button type="button" class="queue-row" class:current={index === playback.queue.currentIndex} aria-current={index === playback.queue.currentIndex ? "true" : undefined} onclick={() => onSelectQueue(index)}>
                  <div class="queue-art">{#if entry.thumbnail}<img src={entry.thumbnail} alt="" />{:else}<span aria-hidden="true">♫</span>{/if}</div>
                  <div class="queue-meta"><span class="queue-title">{entry.title}</span><span class="queue-artist">{entry.artists}</span></div>
                  {#if index === playback.queue.currentIndex && playback.isPlaying}<span class="playing-mark" aria-label="Sonando">▮▮</span>{/if}
                </button>
              {:else}
                <div class="empty-next">No hay pistas en la cola.</div>
              {/each}
            </div>
          {:else}
            <div class="empty-panel"><span class="empty-icon" aria-hidden="true">♫</span><p>No hay pistas en la cola</p></div>
          {/if}
        {:else if selectedPanel === "lyrics"}
          <div class="empty-panel"><span class="empty-icon" aria-hidden="true">“ ”</span><p>Las letras todavía no están disponibles en Windows.</p></div>
        {:else}
          <div class="empty-panel"><span class="empty-icon" aria-hidden="true">♫</span><p>Las recomendaciones todavía no están disponibles en Windows.</p></div>
        {/if}
      </div>
    </div>
  </div>
</section>

<style>
  .fullscreen { position: fixed; inset: 0; z-index: 80; box-sizing: border-box; overflow: auto; isolation: isolate; color: #fff; background: #1b1b1e; }
  .backdrop-art { position: fixed; inset: -12%; z-index: -2; background-size: cover; background-position: center; filter: blur(75px) brightness(.55); transform: scale(1.08); pointer-events: none; }
  .backdrop-shade { position: fixed; inset: 0; z-index: -1; background: linear-gradient(180deg, rgb(12 12 15 / 70%), rgb(17 17 20 / 83%)); pointer-events: none; }
  .close-button { position: absolute; top: 14px; right: 22px; z-index: 1; display: grid; place-items: center; width: 32px; height: 32px; padding: 6px; border: 0; border-radius: 8px; color: rgb(255 255 255 / 75%); background: rgb(255 255 255 / 9%); cursor: pointer; }
  .close-button:hover { color: #fff; background: rgb(255 255 255 / 16%); }
  .close-button svg { width: 18px; height: 18px; }
  .layout { box-sizing: border-box; display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: clamp(24px, 2.8vw, 40px); width: 100%; min-height: 100dvh; padding: 52px clamp(24px, 3.5vw, 48px) 112px; }
  .art-column { display: grid; place-items: center; min-width: 0; min-height: 0; }
  .art-block { width: min(95%, max(100px, calc(100dvh - 264px))); min-width: 0; }
  .artwork { display: grid; place-items: center; width: 100%; aspect-ratio: 1; overflow: hidden; border-radius: 16px; color: rgb(255 255 255 / 42%); background: rgb(255 255 255 / 8%); box-shadow: 0 10px 30px rgb(0 0 0 / 42%); }
  .artwork img { width: 100%; height: 100%; object-fit: cover; }
  .artwork svg { width: 22%; max-width: 80px; }
  .track-info { min-width: 0; margin-top: 16px; }
  .track-info h1 { overflow: hidden; margin: 0; font-size: clamp(21px, 2.3vw, 28px); font-weight: 700; line-height: 1.25; text-overflow: ellipsis; white-space: nowrap; }
  .track-info p { overflow: hidden; margin: 4px 0 0; color: rgb(255 255 255 / 78%); font-size: clamp(14px, 1.4vw, 18px); font-weight: 600; text-overflow: ellipsis; white-space: nowrap; }
  .side-column { display: flex; flex-direction: column; align-items: center; gap: 14px; min-width: 0; min-height: 0; }
  .tablist { display: flex; align-items: center; gap: 0; max-width: 100%; padding: 4px; border: 1px solid rgb(255 255 255 / 12%); border-radius: 999px; background: rgb(255 255 255 / 8%); }
  .tablist button { display: inline-flex; align-items: center; justify-content: center; gap: 7px; min-width: 0; padding: 8px 16px; border: 0; border-radius: 999px; color: rgb(255 255 255 / 65%); background: transparent; font: inherit; font-size: 13px; font-weight: 500; white-space: nowrap; cursor: pointer; }
  .tablist button.active { color: #fff; background: #a33d45; font-weight: 650; }
  .tablist button:hover:not(.active) { color: #fff; }
  .tablist svg { flex: 0 0 14px; width: 14px; height: 14px; }
  .panel { box-sizing: border-box; flex: 1; width: 100%; min-height: 0; overflow-y: auto; }
  .queue-content { padding-top: 4px; }
  .queue-heading { display: flex; justify-content: space-between; gap: 10px; padding: 8px 8px 18px; color: rgb(255 255 255 / 88%); font-size: 12px; font-weight: 650; }
  .queue-heading span:last-child { color: rgb(255 255 255 / 50%); font-size: 11px; font-weight: 500; white-space: nowrap; }
  .queue-label, .next-label { padding: 0 8px 10px; color: rgb(255 255 255 / 52%); font-size: 10px; font-weight: 700; letter-spacing: .08em; }
  .queue-row { box-sizing: border-box; display: flex; width: 100%; align-items: center; gap: 11px; min-height: 52px; padding: 5px 8px; border: 0; border-radius: 8px; color: inherit; background: transparent; text-align: left; cursor: pointer; }
  .queue-row:hover { background: rgb(255 255 255 / 7%); }
  .queue-row.current { background: rgb(255 255 255 / 8%); }
  .queue-art { display: grid; flex: 0 0 46px; place-items: center; width: 46px; height: 46px; overflow: hidden; border-radius: 6px; background: rgb(255 255 255 / 10%); }
  .queue-art img { width: 100%; height: 100%; object-fit: cover; }
  .queue-meta { display: flex; flex: 1; flex-direction: column; gap: 3px; min-width: 0; }
  .queue-title, .queue-artist { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .queue-title { font-size: 13px; font-weight: 650; }
  .queue-artist { color: rgb(255 255 255 / 60%); font-size: 11px; }
  .playing-mark { color: #d06c70; font-size: 12px; letter-spacing: 2px; }
  .next-label { padding-top: 26px; }
  .empty-next { padding: 12px 8px; color: rgb(255 255 255 / 54%); font-size: 13px; }
  .empty-panel { display: flex; flex: 1; flex-direction: column; align-items: center; justify-content: center; gap: 12px; min-height: 240px; color: rgb(255 255 255 / 55%); text-align: center; }
  .empty-panel p { max-width: 32ch; margin: 0; font-size: 14px; }
  .empty-icon { color: rgb(255 255 255 / 25%); font-size: 38px; }
  button:focus-visible { outline: 2px solid #d06c70; outline-offset: 3px; }

  @media (max-width: 780px) {
    .layout { display: flex; flex-direction: column; gap: 32px; padding: 52px 24px 132px; }
    .art-block { width: min(100%, 310px, 40dvh); }
    .side-column { flex: 1; min-height: 240px; }
    .panel { min-height: 240px; }
  }
  @media (max-width: 480px) {
    .layout { padding-inline: 16px; }
    .tablist button { gap: 5px; padding: 8px 10px; font-size: 11px; }
    .tablist svg { width: 12px; height: 12px; }
  }
  @media (prefers-reduced-motion: reduce) { .fullscreen { scroll-behavior: auto; } }
</style>
