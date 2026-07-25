import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { FileCacheService } from '../cacheService';
import fs from 'node:fs';
import path from 'node:path';

// Mock the DI container
vi.mock('../../lib/di/index', () => ({
  getService: vi.fn(() => ({
    getAll: async () => [
      {
        category: 'test',
        subCategories: [
          {
            name: 'demo',
            projects: [
              {
                slug: 'test-project',
                title: 'Test Project',
                summary: 'Test summary',
                tags: ['test'],
                status: 'active' as const,
                url: 'https://example.com',
                repository: 'https://github.com/test/test',
                technologies: ['TypeScript'],
                category: 'test',
                subCategory: 'demo',
                createdAt: '2023-01-01',
                updatedAt: '2023-01-01'
              }
            ]
          }
        ]
      }
    ]
  }))
}));

describe('CacheService', () => {
  let cache: FileCacheService;
  const testCacheDir = path.join(process.cwd(), 'test-cache');

  beforeEach(() => {
    // Clean up test cache directory
    if (fs.existsSync(testCacheDir)) {
      fs.rmSync(testCacheDir, { recursive: true, force: true });
    }
    cache = new FileCacheService();
  });

  afterEach(() => {
    // Clean up test cache directory
    if (fs.existsSync(testCacheDir)) {
      fs.rmSync(testCacheDir, { recursive: true, force: true });
    }
  });

  it('can set and get cache', async () => {
    await cache.setCachedData('test', JSON.stringify({ value: 123 }));
    const result = await cache.getCachedData('test');
    expect(JSON.parse(result!)).toMatchObject({ value: 123 });
  });

  it('returns null for missing key', async () => {
    const result = await cache.getCachedData('missing');
    expect(result).toBeNull();
  });

  it('can invalidate specific cache entry', async () => {
    await cache.setCachedData('test1', 'data1');
    await cache.setCachedData('test2', 'data2');

    await cache.invalidateCache('test1');

    const result1 = await cache.getCachedData('test1');
    const result2 = await cache.getCachedData('test2');

    expect(result1).toBeNull();
    expect(result2).toBe('data2');
  });

  it('can invalidate all cache entries', async () => {
    await cache.setCachedData('test1', 'data1');
    await cache.setCachedData('test2', 'data2');

    await cache.invalidateCache();

    const result1 = await cache.getCachedData('test1');
    const result2 = await cache.getCachedData('test2');

    expect(result1).toBeNull();
    expect(result2).toBeNull();
  });

  it('can set and get cached projects', async () => {
    const projects = [
      {
        category: 'test',
        subCategories: [
          {
            name: 'demo',
            projects: [
              {
                slug: 'test-project',
                title: 'Test Project',
                summary: 'Test summary',
                tags: ['test'],
                status: 'active' as const,
                url: 'https://example.com',
                repository: 'https://github.com/test/test',
                technologies: ['TypeScript'],
                category: 'test',
                subCategory: 'demo',
                createdAt: '2023-01-01',
                updatedAt: '2023-01-01'
              }
            ]
          }
        ]
      }
    ];

    await cache.setCachedProjects(projects);
    const result = await cache.getCachedProjects();

    expect(result).toEqual(projects);
  });

  it('returns empty array for missing projects cache', async () => {
    // Clear cache first
    await cache.invalidateCache('projects');
    const result = await cache.getCachedProjects();
    expect(result).toEqual([]);
  });

  it('handles corrupted projects cache gracefully', async () => {
    await cache.setCachedData('projects', 'invalid json');
    const result = await cache.getCachedProjects();
    expect(result).toEqual([]);
  });

  it('can regenerate cache', async () => {
    await cache.regenerateCache();
    const result = await cache.getCachedProjects();
    expect(Array.isArray(result)).toBe(true);
  });

  it('can get cache stats', async () => {
    // Clear all cache first
    await cache.invalidateCache();

    await cache.setCachedData('test1', 'data1');
    await cache.setCachedData('test2', 'data2');

    const stats = await cache.getCacheStats();

    expect(stats.totalFiles).toBe(2);
    expect(stats.totalSize).toBeGreaterThan(0);
    expect(stats.lastModified).toBeInstanceOf(Date);
  });

  it('returns zero stats for empty cache directory', async () => {
    // Ensure cache directory doesn't exist
    await cache.invalidateCache();

    const stats = await cache.getCacheStats();

    expect(stats.totalFiles).toBe(0);
    expect(stats.totalSize).toBe(0);
    expect(stats.lastModified).toBeUndefined();
  });

  it('can check cache validity', async () => {
    await cache.setCachedData('test', 'data');

    // Should be valid (just created)
    const isValid = await cache.isCacheValid('test', 3600000); // 1 hour
    expect(isValid).toBe(true);

    // Wait a bit and then check with very short max age
    await new Promise((resolve) => setTimeout(resolve, 5));
    const isInvalid = await cache.isCacheValid('test', 1); // 1 ms
    expect(isInvalid).toBe(false);

    // Non-existent cache should be invalid
    const notExists = await cache.isCacheValid('nonexistent');
    expect(notExists).toBe(false);
  });

  it('can warm cache', async () => {
    await cache.warmCache();
    // Just ensure it doesn't throw - functionality is minimal for now
    expect(true).toBe(true);
  });

  it('handles file system errors gracefully', async () => {
    // Mock fs to throw error
    const originalWriteFileSync = fs.writeFileSync;
    vi.spyOn(fs, 'writeFileSync').mockImplementation(() => {
      throw new Error('Disk full');
    });

    await expect(cache.setCachedData('test', 'data')).rejects.toThrow(
      'Disk full'
    );

    // Restore
    fs.writeFileSync = originalWriteFileSync;
  });

  it('handles read errors gracefully', async () => {
    // Mock fs.existsSync to return true but readFileSync to throw
    vi.spyOn(fs, 'existsSync').mockReturnValue(true);
    vi.spyOn(fs, 'readFileSync').mockImplementation(() => {
      throw new Error('Permission denied');
    });

    const result = await cache.getCachedData('test');
    expect(result).toBeNull();

    // Restore
    vi.restoreAllMocks();
  });
});
