export interface WindowFullscreenApi {
  isFullscreen(): Promise<boolean>;
  setFullscreen(fullscreen: boolean): Promise<void>;
}

export type WindowAction = 'enter-player-fullscreen' | 'exit-player-fullscreen' | 'toggle-native-fullscreen';

export class WindowControllerError extends Error {
  constructor(readonly action: WindowAction, cause: unknown) {
    const detail = cause instanceof Error ? cause.message : String(cause);
    const message = action === 'enter-player-fullscreen'
      ? 'No se pudo activar la pantalla completa de reproducción.'
      : action === 'exit-player-fullscreen'
        ? 'No se pudo restaurar el tamaño anterior de la ventana.'
        : 'No se pudo cambiar la pantalla completa de la ventana.';
    super(detail ? `${message} ${detail}` : message, { cause });
    this.name = 'WindowControllerError';
  }
}

async function tauriWindowApi(): Promise<WindowFullscreenApi> {
  if (typeof window === 'undefined') {
    throw new Error('La API de ventana sólo está disponible en la aplicación de escritorio.');
  }
  const { getCurrentWindow } = await import('@tauri-apps/api/window');
  const nativeWindow = getCurrentWindow();
  return {
    isFullscreen: () => nativeWindow.isFullscreen(),
    setFullscreen: fullscreen => nativeWindow.setFullscreen(fullscreen),
  };
}

/** Serializes native window transitions and restores only the state changed for player fullscreen. */
export class WindowController {
  private operationQueue: Promise<void> = Promise.resolve();
  private playerFullscreenPrevious: boolean | null = null;

  constructor(private readonly apiProvider: () => Promise<WindowFullscreenApi> = tauriWindowApi) {}

  enterPlayerFullscreen(): Promise<void> {
    return this.enqueue('enter-player-fullscreen', async api => {
      if (this.playerFullscreenPrevious !== null) return;
      const wasFullscreen = await api.isFullscreen();
      this.playerFullscreenPrevious = wasFullscreen;
      if (!wasFullscreen) {
        try {
          await api.setFullscreen(true);
        } catch (error) {
          this.playerFullscreenPrevious = null;
          throw error;
        }
      }
    });
  }

  exitPlayerFullscreen(): Promise<void> {
    return this.enqueue('exit-player-fullscreen', async api => {
      const previous = this.playerFullscreenPrevious;
      if (previous === null) return;
      const current = await api.isFullscreen();
      if (current !== previous) await api.setFullscreen(previous);
      this.playerFullscreenPrevious = null;
    });
  }

  toggleNativeFullscreen(): Promise<void> {
    return this.enqueue('toggle-native-fullscreen', async api => {
      const current = await api.isFullscreen();
      await api.setFullscreen(!current);
    });
  }

  private enqueue(action: WindowAction, operation: (api: WindowFullscreenApi) => Promise<void>): Promise<void> {
    const run = this.operationQueue.then(async () => {
      try {
        await operation(await this.apiProvider());
      } catch (error) {
        if (error instanceof WindowControllerError) throw error;
        throw new WindowControllerError(action, error);
      }
    });
    this.operationQueue = run.catch(() => undefined);
    return run;
  }
}
