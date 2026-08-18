import { useCallback, useMemo } from 'react';
import { useJson } from 'subzerodev-data-json/react';
import {
  ProjectCategory,
  ProjectStats
} from '../../shared/types/project-types';
import { projectsSchema } from '../config/schemas';
import { getJsonLoader } from '../data/jsonLoader';

export function useProjects() {
  const jsonResult = useJson<unknown>('projects');

  // Deps are the individual primitives/reference (not `jsonResult` itself):
  // useJson returns a new object literal every render, so depending on the
  // whole result would defeat this memo and re-run zod validation on every
  // render (e.g. every keystroke in a filter that re-renders this hook's
  // consumer).
  const validated = useMemo(() => {
    if (jsonResult.loading || !jsonResult.ok) return null;

    return projectsSchema(jsonResult.data);
  }, [jsonResult.loading, jsonResult.ok, jsonResult.data]);

  const data = validated?.ok ? (validated.value as ProjectCategory[]) : null;

  const loading = jsonResult.loading;
  // `'message' in jsonResult` (not `!jsonResult.ok`): this repo's tsconfig
  // has strictNullChecks off, and TS doesn't reliably narrow a discriminated
  // union's negated branch without it — an `in` check narrows correctly
  // either way.
  const error =
    !jsonResult.loading && 'message' in jsonResult
      ? new Error(jsonResult.message)
      : validated && 'message' in validated
        ? new Error(`Schema Validation Failed for "projects": ${validated.message}`)
        : null;

  const metadata = jsonResult.meta;

  // Projects-specific business logic
  const getProjectsByTag = useCallback(
    (tag: string) => {
      if (!data) return [];

      const allProjects = data.flatMap((cat) =>
        cat.subCategories.flatMap((sub) => sub.projects)
      );

      return allProjects.filter((project) =>
        project.tags?.some((projectTag) =>
          projectTag.toLowerCase().includes(tag.toLowerCase())
        )
      );
    },
    [data]
  );

  const getProjectsByCategory = useCallback(
    (category: string) => {
      if (!data) return [];

      const categoryData = data.find(
        (cat) => cat.category.toLowerCase() === category.toLowerCase()
      );

      if (!categoryData) return [];

      return categoryData.subCategories.flatMap((sub) => sub.projects);
    },
    [data]
  );

  const getRecentProjects = useCallback(
    (monthsBack: number = 6) => {
      if (!data) return [];

      const cutoffDate = new Date();
      cutoffDate.setMonth(cutoffDate.getMonth() - monthsBack);

      const allProjects = data.flatMap((cat) =>
        cat.subCategories.flatMap((sub) => sub.projects)
      );

      return allProjects
        .filter((project) => {
          if (!project.lastModified) return false;

          const projectDate = new Date(project.lastModified);

          return projectDate > cutoffDate;
        })
        .sort((a, b) => {
          const dateA = new Date(a.lastModified!);
          const dateB = new Date(b.lastModified!);

          return dateB.getTime() - dateA.getTime(); // Most recent first
        });
    },
    [data]
  );

  const getAllProjects = useCallback(() => {
    if (!data) return [];

    return data.flatMap((cat) =>
      cat.subCategories.flatMap((sub) => sub.projects)
    );
  }, [data]);

  const getProjectStats = useCallback((): ProjectStats => {
    if (!data) {
      return {
        totalProjects: 0,
        recentProjects: 0,
        totalTechnologies: 0,
        averageAge: 'N/A'
      };
    }

    const allProjects = getAllProjects();
    const recentProjects = getRecentProjects();

    // Calculate unique technologies from all tags
    const allTags = new Set(
      allProjects.flatMap((project) => project.tags || [])
    );

    // Calculate average age
    const projectsWithDates = allProjects.filter((p) => p.lastModified);
    let averageAge = 'N/A';

    if (projectsWithDates.length > 0) {
      const now = new Date();
      const totalDays = projectsWithDates.reduce((sum, project) => {
        const projectDate = new Date(project.lastModified!);
        const daysDiff = Math.floor(
          (now.getTime() - projectDate.getTime()) / (1000 * 60 * 60 * 24)
        );
        return sum + daysDiff;
      }, 0);

      const avgDays = Math.floor(totalDays / projectsWithDates.length);

      if (avgDays < 30) {
        averageAge = `${avgDays} days`;
      } else if (avgDays < 365) {
        averageAge = `${Math.floor(avgDays / 30)} months`;
      } else {
        averageAge = `${Math.floor(avgDays / 365)} years`;
      }
    }

    return {
      totalProjects: allProjects.length,
      recentProjects: recentProjects.length,
      totalTechnologies: allTags.size,
      averageAge
    };
  }, [data, getAllProjects, getRecentProjects]);

  const getAvailableTags = useCallback(() => {
    if (!data) return [];

    const allTags = new Set(
      data.flatMap((cat) =>
        cat.subCategories.flatMap((sub) =>
          sub.projects.flatMap((project) => project.tags || [])
        )
      )
    );

    return Array.from(allTags).sort();
  }, [data]);

  const getAvailableCategories = useCallback(() => {
    if (!data) return [];

    return data.map((cat) => cat.category);
  }, [data]);

  // `projects` declares `cache: manual` (config/sources.public.yml), so a
  // plain `jsonResult.refetch()` would replay the cached entry rather than
  // re-reading the source (verified against the package: a `manual` policy
  // reuses its cache entry across repeated `loadById` calls until
  // `invalidate()` is called). Drop the cache entry first so refetch always
  // does a fresh read — this is what admin's "refresh after save" relies on.
  const refetch = useCallback(async () => {
    getJsonLoader().invalidate('projects');
    await jsonResult.refetch();
  }, [jsonResult.refetch]);

  return {
    data,
    loading,
    error,
    metadata,
    refetch,
    // Business logic methods
    getProjectsByTag,
    getProjectsByCategory,
    getRecentProjects,
    getAllProjects,
    getProjectStats,
    getAvailableTags,
    getAvailableCategories
  };
}
