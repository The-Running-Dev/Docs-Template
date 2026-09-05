import { createJsonLoader } from 'subzerodev-data-json';
import type { JsonLoader, SourceMap } from 'subzerodev-data-json';

// @ts-ignore - generated at build time by scripts/pre-build.ts (processSourceMap)
import { sourcesPublic } from '../../data';

let loader: JsonLoader | null = null;

const EMPTY_SOURCE_MAP: SourceMap = { version: 1, sources: {} };

/**
 * `sourcesPublic` is only well-formed when scripts/pre-build.ts's
 * processSourceMap step ran successfully (config/sources.public.yml present
 * and parseable) — that step warns-and-continues on failure rather than
 * failing the build, so a broken/missing config file otherwise reaches here
 * as `undefined`. `createJsonLoader` reads `map.version` unconditionally, so
 * passing that through crashes every page at Root render. Fall back to an
 * empty map instead: every `useJson()` id then resolves to a
 * `json.unresolved` result (no source declared) rather than throwing.
 */
function resolveSourceMap(): SourceMap {
  const map = sourcesPublic as SourceMap | undefined;

  if (map && map.version === 1 && map.sources) {
    return map;
  }

  console.error(
    '[jsonLoader] config/sources.public.yml is missing or failed to convert at build time — falling back to an empty source map; all useJson() reads will resolve to json.unresolved instead of loading data.'
  );

  return EMPTY_SOURCE_MAP;
}

/**
 * The single JsonLoader for this app's declared HTTP sources
 * (config/sources.public.yml). Constructed once and handed to JsonProvider
 * at the composition root (src/theme/Root.tsx, J6.3/J6.4).
 */
function buildLoader(sourceMap: SourceMap): JsonLoader {
  return createJsonLoader(sourceMap, {
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

export function getJsonLoader(): JsonLoader {
  if (!loader) {
    try {
      loader = buildLoader(resolveSourceMap());
    } catch (error) {
      // createJsonLoader validates every entry (normalizeSourceMap,
      // checkRequiredPorts) and throws synchronously on the first invalid
      // one. Falling through here would crash every page at Root render for
      // a single bad source entry, instead of just the feature it belongs
      // to — fall back to the same empty map used for a missing config file.
      console.error(
        '[jsonLoader] config/sources.public.yml failed validation — falling back to an empty source map; all useJson() reads will resolve to json.unresolved instead of loading data.',
        error
      );

      loader = buildLoader(EMPTY_SOURCE_MAP);
    }
  }

  return loader;
}
