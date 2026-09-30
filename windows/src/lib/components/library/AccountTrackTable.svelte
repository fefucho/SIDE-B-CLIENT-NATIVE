<script lang="ts">
  import type { AccountSongDto as SongDto } from "$lib/account/types";
  type AccountTrackDto = SongDto;
  interface Props {
    items: AccountTrackDto[]; currentTrackId: string | null; isPlaying: boolean;
    onPlay: (index: number) => void; onOpenArtist?: (id: string) => void;
    onOpenAlbum?: (id: string) => void; hideAlbumColumn?: boolean; numbered?: boolean;
    likedIds?: Set<string>; pendingIds?: Set<string>;
    onToggleLike?: (track: AccountTrackDto) => void; onToggleSaved?: (track: AccountTrackDto) => void;
  }
  let { items, currentTrackId, isPlaying, onPlay, onOpenArtist, onOpenAlbum, hideAlbumColumn = false, numbered = true, likedIds = new Set<string>(), pendingIds = new Set<string>(), onToggleLike, onToggleSaved }: Props = $props();
  let failedImages = $state(new Set<number>());
  const hasAlbumColumn = $derived(!hideAlbumColumn && items.some((track) => Boolean(track.album)));
  const hasActions = $derived(Boolean(onToggleLike || onToggleSaved));
  function markImageFailed(index: number) { failedImages = new Set(failedImages).add(index); }
</script>

<!-- Keyboard focus is needed to scroll this horizontally overflowing table without a mouse. -->
<!-- svelte-ignore a11y_no_noninteractive_tabindex -->
<div class="table-scroll" role="region" aria-label="Canciones de la biblioteca o playlist" tabindex="0">
  <table class:with-album={hasAlbumColumn} class:with-actions={hasActions}>
    <thead><tr><th class="index" scope="col">{#if numbered}#{/if}</th><th class="track-heading" scope="col">Título</th>{#if hasAlbumColumn}<th class="album-heading" scope="col">Álbum</th>{/if}<th class="duration" scope="col"><span class="sr-only">Duración</span>◷</th>{#if hasActions}<th class="actions-heading" scope="col"><span class="sr-only">Acciones</span></th>{/if}</tr></thead>
    <tbody>
      {#each items as track, index (track.videoId + ":" + index)}
        {@const active = currentTrackId === track.videoId}
        <tr class:active>
          <td class="index"><button type="button" class="row-play" aria-label={`Reproducir ${track.title}`} onclick={() => onPlay(index)}>{#if active && isPlaying}<span aria-hidden="true">♫</span>{:else if numbered}<span aria-hidden="true">{index + 1}</span>{:else}<span aria-hidden="true">▶</span>{/if}</button></td>
          <td class="track-cell">
            {#if track.thumbnail && !failedImages.has(index)}<img class="cover" src={track.thumbnail} alt="" loading="lazy" onerror={() => markImageFailed(index)} />{:else}<div class="cover fallback" aria-hidden="true">♫</div>{/if}
            <div class="song-meta"><button class="song-title" type="button" onclick={() => onPlay(index)} title={track.title}>{track.title}</button>
              <div class="artist-line">
                {#if track.artistId && onOpenArtist}<button type="button" class="metadata-link" onclick={() => onOpenArtist!(track.artistId!)}>{track.artists}</button>
                {:else}<span>{track.artists}</span>{/if}
              </div>
            </div>
          </td>
          {#if hasAlbumColumn}<td class="album-cell">{#if track.albumId && onOpenAlbum}<button type="button" class="metadata-link" onclick={() => onOpenAlbum!(track.albumId!)}>{track.album}</button>{:else}<span>{track.album}</span>{/if}</td>{/if}
          <td class="duration">{track.duration ?? "—"}</td>
          {#if hasActions}<td class="actions">
            {#if onToggleLike}<button type="button" class="action-button" class:liked={likedIds.has(track.videoId)} disabled={pendingIds.has(track.videoId)} aria-label={likedIds.has(track.videoId) ? `Quitar Me gusta de ${track.title}` : `Marcar ${track.title} como Me gusta`} aria-pressed={likedIds.has(track.videoId)} title={likedIds.has(track.videoId) ? "Quitar Me gusta" : "Me gusta"} onclick={() => onToggleLike?.(track)}>{likedIds.has(track.videoId) ? "♥" : "♡"}</button>{/if}
            {#if onToggleSaved && track.library && (track.library.inLibrary ? track.library.removeToken : track.library.addToken)}<button type="button" class="action-button" class:saved={track.library.inLibrary} disabled={pendingIds.has(track.videoId)} aria-label={track.library.inLibrary ? `Quitar ${track.title} de la biblioteca` : `Guardar ${track.title} en la biblioteca`} aria-pressed={track.library.inLibrary} title={track.library.inLibrary ? "Quitar de la biblioteca" : "Guardar en la biblioteca"} onclick={() => onToggleSaved?.(track)}>{track.library.inLibrary ? "▣" : "▢"}</button>{/if}
          </td>{/if}
        </tr>
      {/each}
    </tbody>
  </table>
</div>

<style>
  .table-scroll { min-width: 0; overflow-x: auto; padding: 0 20px 0 16px; outline: none; }
  .table-scroll:focus-visible { box-shadow: inset 0 0 0 2px var(--sideb-highlight); }
  table { width: 100%; min-width: 430px; border-collapse: collapse; table-layout: fixed; color: #aaaab1; font-size: 12px; }
  table.with-album { min-width: 600px; }
  table.with-actions { min-width: 520px; }
  table.with-album.with-actions { min-width: 660px; }
  th { height: 32px; border-bottom: 1px solid rgb(255 255 255 / 9%); font-size: 11px; font-weight: 450; text-align: left; }
  td { height: 52px; border-bottom: 1px solid rgb(255 255 255 / 4%); }
  tbody tr:hover { background: rgb(255 255 255 / 5%); }
  tbody tr.active .song-title { color: var(--sideb-highlight, #d06c70); font-weight: 650; }
  .index { width: 42px; text-align: center; }
  .row-play { width: 30px; height: 32px; border: 0; color: inherit; background: transparent; font: inherit; cursor: pointer; }
  .row-play:hover, .row-play:focus-visible, tr:hover .row-play { color: #fff; }
  .track-heading { padding-left: 8px; }
  .track-cell { display: flex; align-items: center; gap: 11px; min-width: 0; padding: 0 8px; }
  .cover { flex: none; width: 40px; height: 40px; border-radius: 6px; object-fit: cover; background: #303036; }
  .fallback { display: grid; place-items: center; color: #c9c9cf; font-size: 20px; }
  .song-meta { display: flex; min-width: 0; flex-direction: column; gap: 3px; }
  .song-title, .metadata-link { display: block; max-width: 100%; overflow: hidden; padding: 0; border: 0; color: #f2f2f4; background: none; font: inherit; text-align: left; text-overflow: ellipsis; white-space: nowrap; cursor: pointer; }
  .song-title { font-size: 13px; font-weight: 550; }
  .artist-line { display: flex; min-width: 0; align-items: center; gap: 5px; overflow: hidden; color: #a6a6ad; white-space: nowrap; }
  .artist-line span:first-child, .artist-line .metadata-link { overflow: hidden; text-overflow: ellipsis; }
  .metadata-link { display: inline; color: #aaaab1; font-size: 12px; }
  .metadata-link:hover { color: #fff; text-decoration: underline; }
  .album-heading, .album-cell { width: 22%; padding: 0 12px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .duration { width: 70px; padding-right: 8px; text-align: right; font-variant-numeric: tabular-nums; }
  .actions-heading, .actions { width: 82px; padding: 0 6px; text-align: right; }
  .actions { white-space: nowrap; }
  .action-button { width: 32px; height: 32px; margin-left: 4px; border: 0; border-radius: 6px; color: #aaaab1; background: transparent; font-size: 18px; cursor: pointer; }
  .action-button:hover:not(:disabled) { color: #fff; background: var(--sideb-surface-hover); }
  .action-button.liked { color: #e57980; }
  .action-button.saved { color: var(--sideb-highlight); }
  .action-button:disabled { opacity: .5; cursor: wait; }
  .sr-only { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0,0,0,0); white-space: nowrap; }
  button:focus-visible { outline: 2px solid var(--sideb-highlight); outline-offset: 2px; }
</style>
