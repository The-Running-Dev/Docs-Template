import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';
import * as yaml from 'js-yaml';
import { createJsonLoader } from 'subzerodev-data-json';
import type { SourceMap } from 'subzerodev-data-json';

const CONFIG_PATH = path.join(__dirname, '../../../config/sources.public.yml');

function loadSourceMap(): SourceMap {
  return yaml.load(fs.readFileSync(CONFIG_PATH, 'utf-8')) as SourceMap;
}

describe('config/sources.public.yml (J6.4, J6.6, J6.8)', () => {
  it('declares projects, portfolio, and cv', () => {
    const map = loadSourceMap();

    expect(map.version).toBe(1);
    expect(Object.keys(map.sources).sort()).toEqual([
      'cv',
      'portfolio',
      'projects'
    ]);
  });

  // subzerodev-data-json's own readSourceMap would do this at build time, but
  // it is not in the published 0.1.0 (see scripts/pre-build.ts,
  // processSourceMap). Running the map through createJsonLoader here applies
  // the package's real entry check -- normalizeSourceMap plus
  // checkRequiredPorts -- so a malformed entry still fails in CI rather than
  // only at runtime in a browser.
  it('is accepted by the package as a valid SourceMap', () => {
    const map = loadSourceMap();

    expect(() =>
      createJsonLoader(map, {
        fetch: () => Promise.resolve(new Response('{}')),
        clock: () => 0,
        schedule: () => ({ promise: Promise.resolve(), cancel: () => {} })
      })
    ).not.toThrow();
  });

  it('declares an explicit `at` for every source, never a default (J6.6)', () => {
    const map = loadSourceMap();

    for (const entry of Object.values(map.sources)) {
      expect(entry.at).toBe('runtime');
    }
  });

  it('declares an explicit cache policy for every source (J6.8, I31: no default)', () => {
    const map = loadSourceMap();

    expect((map.sources.projects as any).cache).toBe('manual');
    expect((map.sources.portfolio as any).cache).toBe('manual');
    // Carries over HttpDataProvider's exact 5-minute TTL (src/context/HttpDataProvider.tsx,
    // deleted by this migration) rather than silently defaulting to `manual`.
    expect((map.sources.cv as any).cache).toEqual({ ttlMs: 300000 });
  });

  it('omits unwrap (defaults to none) since the payloads are raw, not enveloped', () => {
    const map = loadSourceMap();

    for (const entry of Object.values(map.sources)) {
      expect(entry.unwrap).toBeUndefined();
    }
  });
});
