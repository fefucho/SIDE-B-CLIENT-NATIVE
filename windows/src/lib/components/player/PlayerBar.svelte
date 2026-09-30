<script lang="ts">
  import type { PlaybackStateDto } from "$lib/types";

  interface Props {
    playback: PlaybackStateDto;
    onTogglePlayback: () => void;
    onRetryPlayback: () => void;
    onPrevious: () => void;
    onNext: () => void;
    onSeek: (seconds: number) => void;
    onVolumeChange: (volume: number) => void;
    fullscreenOpen: boolean;
    onToggleFullscreen: () => void;
    loggedIn?: boolean;
    liked?: boolean;
    likePending?: boolean;
    onToggleLike?: () => void;
    likeError?: string | null;
  }

  let { playback, onTogglePlayback, onRetryPlayback, onPrevious, onNext, onSeek, onVolumeChange, fullscreenOpen, onToggleFullscreen, loggedIn = false, liked = false, likePending = false, onToggleLike, likeError = null }: Props = $props();
  let seekDraft = $state<number | null>(null);

  const duration = $derived(finitePositive(playback.duration));
  const position = $derived(clamp(seekDraft ?? playback.position, 0, duration));
  const volume = $derived(clamp(playback.volume, 0, 100));
  const hasTrack = $derived(playback.currentTrack !== null);
  const playLabel = $derived(
    playback.error
      ? "Reintentar reproducción"
      : playback.isEnded
        ? "Reiniciar canción"
        : playback.isPlaying
          ? "Pausar"
          : "Reproducir"
  );

  function finitePositive(value: number): number {
    return Number.isFinite(value) ? Math.max(0, value) : 0;
  }

  function clamp(value: number, min: number, max: number): number {
    return Number.isFinite(value) ? Math.min(max, Math.max(min, value)) : min;
  }

  function formatTime(value: number): string {
    const total = Math.floor(finitePositive(value));
    return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
  }

  function handleSeekInput(event: Event) {
    seekDraft = clamp(Number((event.currentTarget as HTMLInputElement).value), 0, duration);
  }

  function handleSeekChange(event: Event) {
    const seconds = clamp(Number((event.currentTarget as HTMLInputElement).value), 0, duration);
    seekDraft = null;
    onSeek(seconds);
  }

  function handleVolumeInput(event: Event) {
    onVolumeChange(clamp(Number((event.currentTarget as HTMLInputElement).value), 0, 100));
  }
</script>

<footer class="player-bar" aria-label="Reproductor de audio">
  <div class="progress">
    <span class="time" aria-label={`Tiempo transcurrido ${formatTime(position)}`}>
      {formatTime(position)}
    </span>
    <input
      class="seek"
      type="range"
      min="0"
      max={duration || 1}
      step="0.25"
      value={position}
      style={`--fill:${duration ? (position / duration) * 100 : 0}%`}
      disabled={!hasTrack || playback.isLoading || duration === 0}
      oninput={handleSeekInput}
      onchange={handleSeekChange}
      aria-label="Posición de reproducción"
    />
    <span class="time time-end" aria-label={`Duración ${formatTime(duration)}`}>
      {formatTime(duration)}
    </span>
  </div>

  <div class="main-row">
    <div class="transport">
      <button type="button" class="skip" onclick={onPrevious} disabled={!hasTrack} aria-label="Pista anterior" title="Pista anterior">
        <svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><path d="M6 5h2v14H6zm3 7 10-7v14z" /></svg>
      </button>
      <button
        type="button"
        class="play-toggle"
        class:errored={!!playback.error}
        disabled={!hasTrack || playback.isLoading}
        onclick={playback.error ? onRetryPlayback : onTogglePlayback}
        aria-label={playLabel}
        title={playLabel}
      >
        {#if playback.isLoading}
          <span class="spinner" aria-hidden="true"></span>
        {:else if playback.error}
          <svg viewBox="0 0 24 24" aria-hidden="true" fill="none"><path d="M20 11a8 8 0 1 1-2.36-5.66M20 4v5h-5" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" /></svg>
        {:else if playback.isPlaying}
          <svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><rect x="5" y="3" width="5" height="18" rx="1" /><rect x="14" y="3" width="5" height="18" rx="1" /></svg>
        {:else}
          <svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><path d="M6 3.5a1 1 0 0 1 1.51-.86l13 8.5a1 1 0 0 1 0 1.72l-13 8.5A1 1 0 0 1 6 20.5z" /></svg>
        {/if}
      </button>
      <button type="button" class="skip" onclick={onNext} disabled={!hasTrack || playback.queue.currentIndex === null || playback.queue.currentIndex + 1 >= playback.queue.items.length} aria-label="Pista siguiente" title="Pista siguiente">
        <svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><path d="M16 5h2v14h-2zM5 5l10 7-10 7z" /></svg>
      </button>
    </div>

    <div class="track">
      <div class="artwork">
        {#if playback.currentTrack?.thumbnail}
          <img src={playback.currentTrack.thumbnail} alt="" />
        {:else}
          <svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><path d="M10 5v12.1a4 4 0 1 1-2-3.46V3l12-2v14.1a4 4 0 1 1-2-3.46V4.4z" /></svg>
        {/if}
      </div>
      <div class="metadata">
        <span class="title" title={playback.currentTrack?.title ?? "Sin reproducción"}>
          {playback.currentTrack?.title ?? "Sin reproducción"}
        </span>
        {#if playback.error}
          <span class="status error" role="status" title={playback.error}>{playback.error}</span>
        {:else if playback.isLoading}
          <span class="status" role="status">Cargando audio…</span>
        {:else}
          <span class="artist" title={playback.currentTrack?.artists ?? ""}>
            {playback.currentTrack?.artists || "Seleccioná una canción"}
          </span>
        {/if}
        {#if likeError}
          <span class="status like-error" role="alert" title={likeError}>{likeError}</span>
        {/if}
      </div>
      {#if loggedIn && hasTrack && onToggleLike}
        <button
          class="like-toggle"
          type="button"
          class:liked
          disabled={likePending || playback.isLoading}
          onclick={onToggleLike}
          aria-pressed={liked}
          aria-label={liked ? "Quitar de Me Gusta" : "Me Gusta"}
          title={likeError ?? (likePending ? "Actualizando Me Gusta…" : liked ? "Quitar de Me Gusta" : "Me Gusta")}
        >
          {#if likePending}<span class="like-spinner" aria-hidden="true"></span>{:else}
            <svg viewBox="0 0 24 24" aria-hidden="true" fill={liked ? "currentColor" : "none"} stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M20.8 8.7c0 4.2-6.4 9.1-8.8 11-2.4-1.9-8.8-6.8-8.8-11a4.9 4.9 0 0 1 8.8-3.1 4.9 4.9 0 0 1 8.8 3.1Z" /></svg>
          {/if}
        </button>
      {/if}
    </div>

    <div class="end-controls">
      <div class="volume">
        <svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><path d="M3 9v6h4l5 5V4L7 9zm12.5 3a4 4 0 0 0-2-3.46v6.92a4 4 0 0 0 2-3.46" /></svg>
        <input
          type="range"
          min="0"
          max="100"
          step="1"
          value={volume}
          style={`--fill:${volume}%`}
          oninput={handleVolumeInput}
          aria-label="Volumen"
        />
        <span class="volume-value">{Math.round(volume)}%</span>
      </div>
      <button
        type="button"
        class="fullscreen-toggle"
        aria-label={fullscreenOpen ? "Cerrar pantalla completa" : "Abrir pantalla completa"}
        title={fullscreenOpen ? "Cerrar pantalla completa" : "Abrir pantalla completa"}
        aria-expanded={fullscreenOpen}
        aria-controls="fullscreen-now-playing"
        onclick={onToggleFullscreen}
      >
        <svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" class:flipped={fullscreenOpen}>
          <path d="m6 14 6-6 6 6" />
        </svg>
      </button>
    </div>
  </div>
</footer>

<style>
  .player-bar {
    box-sizing: border-box;
    width: min(100%, 820px);
    min-width: 0;
    min-height: 74px;
    padding: 7px 20px 8px;
    color: #f5f5f6;
    background: rgba(36, 36, 42, 0.94);
    border: 1px solid rgba(255, 255, 255, 0.13);
    border-radius: 38px;
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.34);
    backdrop-filter: blur(18px);
    -webkit-backdrop-filter: blur(18px);
    container-type: inline-size;
  }

  .progress {
    display: grid;
    grid-template-columns: 40px minmax(0, 1fr) 40px;
    align-items: center;
    gap: 8px;
    height: 15px;
  }

  .time {
    color: rgba(255, 255, 255, 0.62);
    font-size: 10px;
    font-variant-numeric: tabular-nums;
    text-align: left;
  }

  .time-end { text-align: right; }

  input[type="range"] {
    appearance: none;
    -webkit-appearance: none;
    width: 100%;
    min-width: 0;
    margin: 0;
    border: 0;
    cursor: pointer;
    background: linear-gradient(to right, #d06c70 0 var(--fill), rgba(255, 255, 255, 0.18) var(--fill) 100%);
  }

  input[type="range"]:disabled { cursor: default; opacity: 0.45; }

  .seek { height: 3px; border-radius: 3px; }

  input[type="range"]::-webkit-slider-thumb {
    appearance: none;
    -webkit-appearance: none;
    width: 5px;
    height: 11px;
    border: 0;
    border-radius: 3px;
    background: #fff;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.5);
  }

  input[type="range"]::-moz-range-thumb {
    width: 5px;
    height: 11px;
    border: 0;
    border-radius: 3px;
    background: #fff;
  }

  .main-row {
    display: grid;
    grid-template-columns: 102px minmax(0, 1fr) 205px;
    align-items: center;
    gap: 14px;
    min-height: 42px;
  }

  .transport { display: flex; align-items: center; justify-content: center; gap: 5px; }
  .skip { display: grid; place-items: center; width: 27px; height: 32px; padding: 5px; border: 0; border-radius: 6px; color: #dedee3; background: transparent; cursor: pointer; }
  .skip:hover:not(:disabled) { color: #fff; background: rgb(255 255 255 / 10%); }
  .skip:disabled { opacity: .38; cursor: default; }
  .skip svg { width: 16px; height: 16px; }

  .play-toggle {
    display: grid;
    place-items: center;
    width: 38px;
    height: 38px;
    padding: 9px;
    border: 0;
    border-radius: 50%;
    color: #fff;
    background: #a33d45;
    cursor: pointer;
  }

  .play-toggle:hover:not(:disabled) { background: #b85058; }
  .play-toggle:disabled { opacity: 0.48; cursor: default; }
  .play-toggle.errored { color: #ffd37a; }
  .play-toggle svg { width: 20px; height: 20px; }

  .spinner {
    box-sizing: border-box;
    width: 18px;
    height: 18px;
    border: 2px solid rgba(255, 255, 255, 0.35);
    border-top-color: #fff;
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }

  @keyframes spin { to { transform: rotate(360deg); } }

  .track {
    display: flex;
    align-items: center;
    gap: 10px;
    min-width: 0;
    padding-left: 12px;
    border-left: 1px solid rgba(255, 255, 255, 0.13);
  }

  .artwork {
    display: grid;
    flex: 0 0 40px;
    place-items: center;
    width: 40px;
    height: 40px;
    overflow: hidden;
    color: #aaaab2;
    background: rgba(255, 255, 255, 0.08);
    border-radius: 7px;
  }

  .artwork img { width: 100%; height: 100%; object-fit: cover; }
  .artwork svg { width: 18px; height: 18px; }
  .metadata { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
  .title, .artist, .status { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .title { font-size: 13px; font-weight: 600; }
  .artist, .status { color: #b9b9c2; font-size: 11px; }
  .status.error { color: #ffd37a; }
  .status.like-error { color: #ff9ba1; }
  .like-toggle { display: grid; flex: 0 0 28px; place-items: center; width: 28px; height: 28px; padding: 5px; border: 0; border-radius: 50%; color: rgb(255 255 255 / 62%); background: transparent; cursor: pointer; }
  .like-toggle:hover:not(:disabled) { color: #fff; background: rgb(255 255 255 / 9%); }
  .like-toggle.liked { color: #d06c70; }
  .like-toggle:disabled { opacity: .55; cursor: wait; }
  .like-toggle svg { width: 17px; height: 17px; }
  .like-spinner { width: 13px; height: 13px; border: 2px solid rgb(255 255 255 / 30%); border-top-color: #d06c70; border-radius: 50%; animation: spin .8s linear infinite; }

  .end-controls { display: flex; align-items: center; justify-content: flex-end; gap: 10px; min-width: 0; }
  .volume { display: flex; flex: 1; align-items: center; gap: 8px; min-width: 0; }
  .volume svg { flex: 0 0 18px; width: 18px; height: 18px; color: #c6c6cd; }
  .volume input { height: 8px; border-radius: 8px; }
  .volume input::-webkit-slider-thumb { width: 10px; height: 10px; border-radius: 50%; }
  .volume input::-moz-range-thumb { width: 10px; height: 10px; border-radius: 50%; }
  .volume-value { width: 34px; color: #b9b9c2; font-size: 10px; font-variant-numeric: tabular-nums; text-align: right; }
  .fullscreen-toggle { display: grid; flex: 0 0 32px; place-items: center; width: 32px; height: 32px; padding: 5px; border: 0; border-radius: 7px; color: rgb(255 255 255 / 75%); background: transparent; cursor: pointer; }
  .fullscreen-toggle:hover { color: #fff; background: rgb(255 255 255 / 10%); }
  .fullscreen-toggle svg { width: 20px; height: 20px; transition: transform 180ms ease; }
  .fullscreen-toggle svg.flipped { transform: rotate(180deg); }

  button:focus-visible, input:focus-visible {
    outline: 2px solid #d06c70;
    outline-offset: 3px;
  }

  @container (max-width: 600px) {
    .main-row { grid-template-columns: 102px minmax(0, 1fr) 155px; gap: 8px; }
    .volume-value { display: none; }
    .track { gap: 8px; padding-left: 8px; }
  }

  @container (max-width: 430px) {
    .main-row { grid-template-columns: 102px minmax(0, 1fr); }
    .end-controls { grid-column: 1 / -1; padding: 2px 8px 3px; }
    .volume { max-width: 180px; }
  }

  @media (prefers-reduced-motion: reduce) {
    .spinner { animation-duration: 2s; }
  }
</style>
