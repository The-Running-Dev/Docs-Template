import { useCallback, useMemo } from 'react';
import { useJson } from 'subzerodev-data-json/react';
import {
  PortfolioData,
  FlattenedTechnologyItem
} from '../components/Portfolio/models';
import { portfolioSchema } from '../config/schemas';
import { getJsonLoader } from '../data/jsonLoader';

export function usePortfolio() {
  const jsonResult = useJson<unknown>('portfolio');

  // Deps are the individual primitives/reference (not `jsonResult` itself):
  // useJson returns a new object literal every render, so depending on the
  // whole result would defeat this memo and re-run zod validation on every
  // render.
  const validated = useMemo(() => {
    if (jsonResult.loading || !jsonResult.ok) return null;

    return portfolioSchema(jsonResult.data);
  }, [jsonResult.loading, jsonResult.ok, jsonResult.data]);

  const data = validated?.ok ? (validated.value as PortfolioData) : null;

  const loading = jsonResult.loading;
  // `'message' in jsonResult` (not `!jsonResult.ok`): this repo's tsconfig
  // has strictNullChecks off, and TS doesn't reliably narrow a discriminated
  // union's negated branch without it — an `in` check narrows correctly
  // either way.
  const error =
    !jsonResult.loading && 'message' in jsonResult
      ? new Error(jsonResult.message)
      : validated && 'message' in validated
        ? new Error(`Schema Validation Failed for "portfolio": ${validated.message}`)
        : null;

  const metadata = jsonResult.meta;

  // `portfolio` declares `cache: manual` (config/sources.public.yml), so a
  // plain `jsonResult.refetch()` would replay the cached entry rather than
  // re-reading the source (see useProjects.ts's identical `cache: manual`
  // situation). Drop the cache entry first so refetch always does a fresh
  // read.
  const refetch = useCallback(async () => {
    getJsonLoader().invalidate('portfolio');
    await jsonResult.refetch();
  }, [jsonResult.refetch]);

  // Portfolio-specific business logic
  const getProjectsByCategory = useCallback(
    (category: string) => {
      if (!data?.projects) return [];
      return data.projects.filter((p) =>
        p.category?.toLowerCase().includes(category.toLowerCase())
      );
    },
    [data]
  );

  const getTechnologiesByCategory = useCallback(
    (category: string) => {
      if (!data?.technologies) return [];
      return data.technologies.filter((tech) =>
        tech.name.toLowerCase().includes(category.toLowerCase())
      );
    },
    [data]
  );

  const getFlattenedTechnologies =
    useCallback((): FlattenedTechnologyItem[] => {
      if (!data?.technologies) return [];

      return data.technologies.flatMap((category) => {
        const categoryName = category.name;

        if (!category.subCategories || category.subCategories.length === 0) {
          return [
            {
              name: categoryName,
              link: category.link,
              category: categoryName,
              subCategories: undefined
            }
          ];
        }

        return category.subCategories.map((subCat) => ({
          name: subCat.name,
          link: subCat.link,
          category: categoryName,
          subCategories: subCat.subCategories || undefined
        }));
      });
    }, [data]);

  const getStats = useCallback(() => {
    if (!data) return null;

    return {
      totalProjects: data.projects?.length || 0,
      totalTechnologies: data.technologies?.length || 0,
      totalSubCategories:
        data.technologies?.reduce(
          (total, tech) => total + (tech.subCategories?.length || 0),
          0
        ) || 0,
      totalStats: data.stats?.length || 0,
      stats: data.stats || []
    };
  }, [data]);

  return {
    data,
    loading,
    error,
    metadata,
    refetch,
    // Business logic methods
    getProjectsByCategory,
    getTechnologiesByCategory,
    getFlattenedTechnologies,
    getStats
  };
}
