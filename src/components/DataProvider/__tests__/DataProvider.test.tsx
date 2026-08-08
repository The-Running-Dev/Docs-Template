import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render } from '@testing-library/react';
import { Features } from '../../../config/FeaturesConfig';

vi.mock('../../../config/FeaturesConfig', () => ({
  Features: {
    VersionDisplay: 'versionDisplay',
    CVPage: 'cvPage'
  },
  FeatureToConfigMap: {
    versionDisplay: 'versionDisplay',
    cvPage: 'cvPage'
  },
  useFeaturesConfig: vi.fn()
}));

const mockUseJson = vi.fn();

vi.mock('subzerodev-data-json/react', () => ({
  useJson: (...args: unknown[]) => mockUseJson(...args)
}));

vi.mock('../../../config/schemas', () => ({
  schemaRegistry: {
    cv: (raw: unknown) => ({ ok: true, value: raw })
  }
}));

import DataProvider from '../DataProvider';
import { useFeaturesConfig } from '../../../config/FeaturesConfig';

const mockUseFeaturesConfig = useFeaturesConfig as any;

const unresolvedResult = {
  ok: false as const,
  reason: 'json.unresolved' as const,
  message: 'loading',
  data: null,
  meta: {
    id: '',
    provider: 'none' as const,
    location: '',
    bytes: 0,
    digest: null,
    cached: false,
    attempts: 0,
    validated: false
  },
  loading: true,
  refetch: vi.fn()
};

describe('DataProvider', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockUseFeaturesConfig.mockReturnValue({
      versionDisplay: true,
      cvPage: true
    });
    mockUseJson.mockReturnValue(unresolvedResult);
  });

  it('renders children with static data when feature enabled and no config source', () => {
    const mockChildren = vi.fn().mockReturnValue(<div>Test Content</div>);
    const defaultData = { version: '1.0.0' };

    render(
      <DataProvider feature={Features.VersionDisplay} defaultData={defaultData}>
        {mockChildren}
      </DataProvider>
    );

    expect(mockChildren).toHaveBeenCalledWith(
      defaultData,
      false,
      null,
      expect.objectContaining({
        provider: 'JSON',
        source: 'static'
      })
    );
  });

  it('renders fallback when feature disabled', () => {
    mockUseFeaturesConfig.mockReturnValue({ versionDisplay: false });
    const fallback = <div data-testid="fallback">Feature Disabled</div>;
    const mockChildren = vi.fn();

    const { getByTestId } = render(
      <DataProvider
        feature={Features.VersionDisplay}
        defaultData={{ test: true }}
        fallback={fallback}
      >
        {mockChildren}
      </DataProvider>
    );

    expect(getByTestId('fallback')).toBeInTheDocument();
    expect(mockChildren).not.toHaveBeenCalled();
  });

  it('renders children with null data when no defaultData provided (FeatureGuard mode)', () => {
    const mockChildren = vi.fn().mockReturnValue(<div>Guarded Content</div>);

    render(
      <DataProvider feature={Features.VersionDisplay}>{mockChildren}</DataProvider>
    );

    expect(mockChildren).toHaveBeenCalledWith(null, false, null, null);
  });

  it('renders children when no feature specified', () => {
    const mockChildren = vi.fn().mockReturnValue(<div>No Feature</div>);
    const defaultData = { test: true };

    render(<DataProvider defaultData={defaultData}>{mockChildren}</DataProvider>);

    expect(mockChildren).toHaveBeenCalledWith(
      defaultData,
      false,
      null,
      expect.objectContaining({
        provider: 'JSON',
        source: 'static'
      })
    );
  });

  it('applies processor to data when provided', () => {
    const mockChildren = vi.fn().mockReturnValue(<div>Processed Content</div>);
    const defaultData = { count: 5 };
    const processor = (data: any) => ({ ...data, doubled: data.count * 2 });

    render(
      <DataProvider defaultData={defaultData} processor={processor}>
        {mockChildren}
      </DataProvider>
    );

    expect(mockChildren).toHaveBeenCalledWith(
      { count: 5, doubled: 10 },
      false,
      null,
      expect.objectContaining({
        provider: 'JSON',
        source: 'static'
      })
    );
  });

  it('reads through useJson for a feature mapped to a source (cvPage -> cv)', () => {
    mockUseJson.mockReturnValue({
      ok: true,
      reason: 'json.ok',
      data: { header: { title: 'Ben' } },
      meta: {
        id: 'cv',
        provider: 'http',
        location: 'https://example.com/cv.json',
        bytes: 42,
        digest: null,
        cached: false,
        attempts: 1,
        validated: false
      },
      loading: false,
      refetch: vi.fn()
    });

    const mockChildren = vi.fn().mockReturnValue(<div>CV</div>);

    render(
      <DataProvider feature={Features.CVPage} defaultData={{ header: { title: 'Default' } }}>
        {mockChildren}
      </DataProvider>
    );

    expect(mockUseJson).toHaveBeenCalledWith('cv');
    expect(mockChildren).toHaveBeenCalledWith(
      { header: { title: 'Ben' } },
      false,
      null,
      expect.objectContaining({ provider: 'http', source: 'cv' })
    );
  });

  it('falls back to defaultData and reports an error when the source load fails', () => {
    mockUseJson.mockReturnValue({
      ok: false,
      reason: 'json.transport',
      message: 'network error',
      data: null,
      meta: {
        id: 'cv',
        provider: 'none',
        location: '',
        bytes: 0,
        digest: null,
        cached: false,
        attempts: 1,
        validated: false
      },
      loading: false,
      refetch: vi.fn()
    });

    const mockChildren = vi.fn().mockReturnValue(<div>CV</div>);
    const defaultData = { header: { title: 'Default' } };

    render(
      <DataProvider feature={Features.CVPage} defaultData={defaultData}>
        {mockChildren}
      </DataProvider>
    );

    const call = mockChildren.mock.calls[0];

    expect(call[0]).toEqual(defaultData);
    expect(call[1]).toBe(false);
    expect(call[2]).toBeInstanceOf(Error);
    expect((call[2] as Error).message).toBe('network error');
  });
});
