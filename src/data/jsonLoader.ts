import { createJsonLoader } from 'subzerodev-data-json';
import type { JsonLoader, SourceMap } from 'subzerodev-data-json';

// @ts-ignore - generated at build time by scripts/pre-build.ts (processSourceMap)
import { sourcesPublic } from '../../data';

let loader: JsonLoader | null = null;

/**
 * The single JsonLoader for this app's declared HTTP sources
 * (config/sources.public.yml). Constructed once and handed to JsonProvider
 * at the composition root (src/theme/Root.tsx, J6.3/J6.4).
 */
export function getJsonLoader(): JsonLoader {
  if (!loader) {
    loader = createJsonLoader(sourcesPublic as SourceMap, {
      fetch: (url, init) => fetch(url, init),
      clock: () => Date.now(),
      // Required alongside `fetch` (I6): every http read carries a timeout
      // (default or declared) that needs a cancellable wait to enforce it.
      schedule: (ms) => {
        let timer: ReturnType<typeof setTimeout>;
        const promise = new Promise<void>((resolve) => {
          timer = setTimeout(resolve, ms);
        });

        return {
          promise,
          cancel: () => clearTimeout(timer)
        };
      }
    });
  }

  return loader;
}
