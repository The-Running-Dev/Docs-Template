import { useEffect } from 'react';
import { Features, useFeaturesConfig, FeatureToConfigMap } from '../config/FeaturesConfig';
import { getJsonLoader } from '../data/jsonLoader';

const PRELOAD_SOURCES: Array<{ id: string; feature: Features }> = [
  { id: 'portfolio', feature: Features.PortfolioPage },
  { id: 'projects', feature: Features.ProjectsPage }
];

/**
 * Warms the projects/portfolio caches on mount so navigating to those pages
 * doesn't wait on a fresh fetch — the replacement for the old DataLoader +
 * zustand store preload (J6.1).
 */
export function useAppInitialization() {
  const features = useFeaturesConfig();

  useEffect(() => {
    const enabledIds = PRELOAD_SOURCES.filter(
      (source) => features[FeatureToConfigMap[source.feature]]
    ).map((source) => source.id);

    if (enabledIds.length === 0) return;

    getJsonLoader()
      .preload(enabledIds)
      .catch((error) => {
        console.error('Failed to Preload App Data:', error);
      });
  }, [features]);
}
