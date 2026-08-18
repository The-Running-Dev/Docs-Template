import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';

describe('useAppInitialization', () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    vi.resetModules();
  });

  it('preloads only enabled features', async () => {
    vi.doMock('../../config/FeaturesConfig', async () => {
      const actual = await vi.importActual<any>('../../config/FeaturesConfig');
      return {
        ...actual,
        useFeaturesConfig: vi.fn(() => ({
          // Only Portfolio enabled
          portfolioPage: true,
          projectsPage: false
        }))
      };
    });

    const preload = vi.fn().mockResolvedValue(undefined);

    vi.doMock('../../data/jsonLoader', () => ({
      getJsonLoader: () => ({ preload })
    }));

    const { useAppInitialization } = await import('../useAppInitialization');
    renderHook(() => useAppInitialization());

    await waitFor(() => {
      expect(preload).toHaveBeenCalled();
    }, { timeout: 1000 });

    expect(preload.mock.calls[preload.mock.calls.length - 1][0]).toEqual([
      'portfolio'
    ]);
  });

  it('preloads both when both features enabled', async () => {
    vi.doMock('../../config/FeaturesConfig', async () => {
      const actual = await vi.importActual<any>('../../config/FeaturesConfig');
      return {
        ...actual,
        useFeaturesConfig: vi.fn(() => ({ portfolioPage: true, projectsPage: true }))
      };
    });

    const preload = vi.fn().mockResolvedValue(undefined);

    vi.doMock('../../data/jsonLoader', () => ({
      getJsonLoader: () => ({ preload })
    }));

    const { useAppInitialization } = await import('../useAppInitialization');
    renderHook(() => useAppInitialization());

    await waitFor(() => {
      expect(preload).toHaveBeenCalled();
    }, { timeout: 1000 });

    const arg = preload.mock.calls[preload.mock.calls.length - 1][0] as string[];
    expect([...arg].sort()).toEqual(['portfolio', 'projects']);
  });

  it('does not preload when no relevant feature is enabled', async () => {
    vi.doMock('../../config/FeaturesConfig', async () => {
      const actual = await vi.importActual<any>('../../config/FeaturesConfig');
      return {
        ...actual,
        useFeaturesConfig: vi.fn(() => ({ portfolioPage: false, projectsPage: false }))
      };
    });

    const preload = vi.fn().mockResolvedValue(undefined);

    vi.doMock('../../data/jsonLoader', () => ({
      getJsonLoader: () => ({ preload })
    }));

    const { useAppInitialization } = await import('../useAppInitialization');
    renderHook(() => useAppInitialization());

    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(preload).not.toHaveBeenCalled();
  });
});
