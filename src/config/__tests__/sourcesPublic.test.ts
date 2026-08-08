import { describe, it, expect } from 'vitest';
import path from 'path';
import { readSourceMap } from 'subzerodev-data-json/node';

const CONFIG_PATH = path.join(__dirname, '../../../config/sources.public.yml');

describe('config/sources.public.yml (J6.4, J6.6, J6.8)', () => {
  it('parses to a valid SourceMap declaring projects, portfolio, and cv', async () => {
    const map = await readSourceMap(CONFIG_PATH);

    expect(map.version).toBe(1);
    expect(Object.keys(map.sources).sort()).toEqual([
      'cv',
      'portfolio',
      'projects'
    ]);
  });

  it('declares an explicit `at` for every source, never a default (J6.6)', async () => {
    const map = await readSourceMap(CONFIG_PATH);

    for (const entry of Object.values(map.sources)) {
      expect(entry.at).toBe('runtime');
    }
  });

  it('declares an explicit cache policy for every source (J6.8, I31: no default)', async () => {
    const map = await readSourceMap(CONFIG_PATH);

    expect(map.sources.projects.cache).toBe('manual');
    expect(map.sources.portfolio.cache).toBe('manual');
    // Carries over HttpDataProvider's exact 5-minute TTL (src/context/HttpDataProvider.tsx,
    // deleted by this migration) rather than silently defaulting to `manual`.
    expect(map.sources.cv.cache).toEqual({ ttlMs: 300000 });
  });

  it('omits unwrap (defaults to none) since the payloads are raw, not enveloped', async () => {
    const map = await readSourceMap(CONFIG_PATH);

    for (const entry of Object.values(map.sources)) {
      expect(entry.unwrap).toBeUndefined();
    }
  });
});
