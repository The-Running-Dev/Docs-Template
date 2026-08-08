import React from 'react';
import { useJson } from 'subzerodev-data-json/react';
import type { SourceId } from 'subzerodev-data-json';
import {
  useFeaturesConfig,
  FeatureToConfigMap,
  Features
} from '../../config/FeaturesConfig';
import { schemaRegistry, SchemaId } from '../../config/schemas';
import { DataProviderComponentProps } from './models';

/**
 * The only features with a declared HTTP source (config/sources.public.yml).
 * Every other feature/DataProvider usage renders defaultData directly.
 */
const FeatureToSourceId: Partial<Record<Features, SchemaId>> = {
  [Features.CVPage]: 'cv',
  [Features.PortfolioPage]: 'portfolio',
  [Features.ProjectsPage]: 'projects'
};

/**
 * DataProvider - a feature gate composed with useJson (J6.3)
 *
 * Renders default/static data directly when `feature` has no mapped source
 * (e.g. Badges, VersionDisplay), or when a feature is disabled. Otherwise
 * reads through useJson and validates the result against that source's zod
 * schema (subzerodev-data-json/react's useJson has no `validate` parameter,
 * so schema resolution — SourceEntry.schema's "consumer's schema registry" —
 * happens here rather than through JsonRequest.validate).
 *
 * Can also act as a simple FeatureGuard when no defaultData is provided.
 */
function DataProvider<TData = any, TProcessedData = TData>({
  feature,
  defaultData,
  processor,
  fallback = null,
  children
}: DataProviderComponentProps<
  TData,
  TProcessedData
>): React.ReactElement | null {
  const featuresConfig = useFeaturesConfig();
  const isEnabled = feature
    ? featuresConfig[FeatureToConfigMap[feature as Features]]
    : true;

  const sourceId =
    feature !== undefined ? FeatureToSourceId[feature as Features] : undefined;

  // Called unconditionally so hook order stays stable across every
  // DataProvider usage, whether or not `feature` maps to a source: an empty
  // id is a cheap, side-effect-free json.unresolved (no network call) that
  // is simply ignored below when sourceId is undefined.
  const jsonResult = useJson<unknown>((sourceId ?? '') as SourceId);

  if (!isEnabled) {
    return fallback as React.ReactElement | null;
  }

  const hasDefaultData = !(defaultData === undefined || defaultData === null);

  if (!sourceId) {
    // Simple feature-gating mode - when no defaultData provided, act like FeatureGuard
    if (!hasDefaultData) {
      return <>{children(null as TProcessedData, false, null, null)}</>;
    }

    const processedData =
      processor && defaultData ? processor(defaultData) : defaultData;

    const staticMeta = {
      provider: 'JSON',
      source: 'static',
      location: 'default',
      timestamp: new Date().toISOString(),
      dataSize: defaultData ? JSON.stringify(defaultData).length : 0
    };

    return (
      <>{children(processedData as TProcessedData, false, null, staticMeta)}</>
    );
  }

  let data: TData | null = null;
  let error: Error | null = null;

  // `'message' in x` rather than `x.ok`/`!x.ok`: this repo's tsconfig has
  // strictNullChecks off, and TS doesn't reliably narrow a discriminated
  // union through that without it — an `in` check does. `message` only
  // exists on the `ok: false` branch (both branches carry `data`/`meta`).
  if (!jsonResult.loading) {
    if ('message' in jsonResult) {
      error = new Error(jsonResult.message);
    } else {
      const validated = schemaRegistry[sourceId](jsonResult.data);

      if ('value' in validated) {
        data = validated.value as TData;
      } else {
        error = new Error(
          `Schema Validation Failed for "${sourceId}": ${validated.message}`
        );
      }
    }
  }

  const effectiveData = data ?? (defaultData as TData | undefined) ?? null;
  const processedData =
    processor && effectiveData
      ? processor(effectiveData)
      : (effectiveData as unknown as TProcessedData);

  const meta = {
    provider: jsonResult.meta.provider,
    source: sourceId,
    location: jsonResult.meta.location,
    cached: jsonResult.meta.cached,
    timestamp: new Date().toISOString(),
    dataSize: jsonResult.meta.bytes
  };

  return (
    <>{children(processedData, jsonResult.loading, error, meta)}</>
  );
}

export default DataProvider;
