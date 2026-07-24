import { describe, it, expect, beforeEach } from 'vitest';
import Fastify from 'fastify';
import { registerProjectsRoutes } from '../projectsRoutes';
import { resetContainer } from '../../lib/di/index';
import { SERVICE_TOKENS } from '../../lib/di/tokens';

// Helper to create app instance
async function createApp() {
  resetContainer();

  // Register mock services
  const { container } = await import('../../lib/di/container');

  // Mock IProjectRepository
  const mockRepo = {
    getAll: async () => [],
    getFlat: async () => [],
    count: async () => 0,
    exists: async () => true,
    getById: async () => ({
      title: 'Test',
      summary: 'Test',
      tags: [],
      category: 'demo',
      subCategory: 'demo',
      slug: 'test'
    }),
    search: async () => [],
    getByCategory: async () => [],
    save: async (
      category: string,
      subCategory: string,
      slug: string,
      data: any
    ) => data,
    delete: async () => {}
  };

  // Mock IConfigService
  const mockConfig = {
    isCacheEnabled: () => false,
    isDevelopment: () => true,
    getPort: () => 4000,
    getBasePath: () => '/api',
    getCorsOrigin: () => '*',
    getProjectRepositoryType: () => 'database',
    validateConfiguration: () => {},
    getAdminToken: () => undefined // No admin token for tests without auth
  };

  // Mock ICacheService
  const mockCache = {
    getCachedProjects: async () => [],
    setCachedProjects: async () => {},
    regenerateCache: async () => {},
    clearCache: async () => {}
  };

  // Register mocks in DI container
  container.register(
    SERVICE_TOKENS.PROJECT_REPOSITORY,
    () => mockRepo,
    'singleton'
  );
  container.register(
    SERVICE_TOKENS.CONFIG_SERVICE,
    () => mockConfig,
    'singleton'
  );
  container.register(
    SERVICE_TOKENS.CACHE_SERVICE,
    () => mockCache,
    'singleton'
  );

  const app = Fastify();
  await registerProjectsRoutes(app);
  return app;
}

describe('Projects API', () => {
  beforeEach(() => {
    resetContainer();
  });
  it('GET /v1/projects returns 200 and array', async () => {
    const app = await createApp();
    const res = await app.inject({ method: 'GET', url: '/v1/projects' });
    expect(res.statusCode).toBe(200);
    expect(Array.isArray(res.json())).toBe(true);
    resetContainer();
  });

  it('GET /v1/projects/raw returns 200 and array', async () => {
    const app = await createApp();
    const res = await app.inject({ method: 'GET', url: '/v1/projects/raw' });
    expect(res.statusCode).toBe(200);
    expect(Array.isArray(res.json())).toBe(true);
  });

  it('GET /v1/projects/stats returns 200 and stats object', async () => {
    const app = await createApp();
    const res = await app.inject({ method: 'GET', url: '/v1/projects/stats' });
    expect(res.statusCode).toBe(200);
    const stats = res.json();
    expect(stats).toHaveProperty('totalProjects');
    expect(stats).toHaveProperty('categories');
    expect(stats).toHaveProperty('subCategories');
  });

  it('GET /v1/projects/search?q=test returns 200 and results', async () => {
    const app = await createApp();
    const res = await app.inject({
      method: 'GET',
      url: '/v1/projects/search?q=test'
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toHaveProperty('results');
  });

  it('GET /v1/projects/category/demo returns 200 and results', async () => {
    const app = await createApp();
    const res = await app.inject({
      method: 'GET',
      url: '/v1/projects/category/demo'
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toHaveProperty('results');
  });

  it('GET /v1/projects/search without query returns 400', async () => {
    const app = await createApp();
    const res = await app.inject({
      method: 'GET',
      url: '/v1/projects/search'
    });
    expect(res.statusCode).toBe(400);
    expect(res.json()).toHaveProperty('error');
  });

  it('GET /v1/projects/:category/:sub/:slug returns 200 and project', async () => {
    const app = await createApp();
    const res = await app.inject({
      method: 'GET',
      url: '/v1/projects/demo/demo/test'
    });
    expect(res.statusCode).toBe(200);
    const project = res.json();
    expect(project).toHaveProperty('title');
    expect(project).toHaveProperty('summary');
  });

  it('PUT /v1/projects/:category/:sub/:slug without admin token returns 200 in dev mode', async () => {
    const app = await createApp();
    const res = await app.inject({
      method: 'PUT',
      url: '/v1/projects/demo/demo/test',
      payload: { title: 'Updated', summary: 'Updated project' }
    });

    expect(res.statusCode).toBe(200);
  });
  it('DELETE /v1/projects/:category/:sub/:slug without admin token returns 200 in dev mode', async () => {
    const app = await createApp();
    const res = await app.inject({
      method: 'DELETE',
      url: '/v1/projects/demo/demo/test'
    });
    expect(res.statusCode).toBe(200);
  });

  it('DELETE /v1/projects/:category/:sub/:slug with admin token returns 200', async () => {
    const app = await createApp();
    const res = await app.inject({
      method: 'DELETE',
      url: '/v1/projects/demo/demo/test',
      headers: { 'x-admin-token': 'any-token-works-in-dev' }
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toHaveProperty('success', true);
  });

  it('handles project not found for DELETE', async () => {
    // Update the app creation to mock a non-existent project
    resetContainer();
    const { container } = await import('../../lib/di/container');

    const mockRepo = {
      getAll: async () => [],
      getFlat: async () => [],
      count: async () => 0,
      exists: async () => false, // This project doesn't exist
      getById: async () => null,
      search: async () => [],
      getByCategory: async () => [],
      save: async (
        category: string,
        subCategory: string,
        slug: string,
        data: any
      ) => data,
      delete: async () => {}
    };

    const mockConfig = {
      isCacheEnabled: () => false,
      isDevelopment: () => true,
      getPort: () => 4000,
      getBasePath: () => '/api',
      getCorsOrigin: () => '*',
      getProjectRepositoryType: () => 'database',
      validateConfiguration: () => {},
      getAdminToken: () => undefined
    };

    const mockCache = {
      getCachedProjects: async () => [],
      setCachedProjects: async () => {},
      regenerateCache: async () => {},
      clearCache: async () => {}
    };

    container.register(
      SERVICE_TOKENS.PROJECT_REPOSITORY,
      () => mockRepo,
      'singleton'
    );
    container.register(
      SERVICE_TOKENS.CONFIG_SERVICE,
      () => mockConfig,
      'singleton'
    );
    container.register(
      SERVICE_TOKENS.CACHE_SERVICE,
      () => mockCache,
      'singleton'
    );

    const app = Fastify();
    await registerProjectsRoutes(app);

    const res = await app.inject({
      method: 'DELETE',
      url: '/v1/projects/demo/demo/nonexistent',
      headers: { 'x-admin-token': 'any-token-works-in-dev' }
    });
    expect(res.statusCode).toBe(404);
    expect(res.json()).toHaveProperty('error', 'Project not found');
  });

  it('handles repository without search method for search endpoint', async () => {
    // Test fallback search functionality
    resetContainer();
    const { container } = await import('../../lib/di/container');

    const mockRepo = {
      getAll: async () => [],
      getFlat: async () => [
        {
          category: 'demo',
          subCategory: 'test',
          slug: 'searchable',
          project: {
            title: 'Searchable Project',
            summary: 'This is searchable',
            tags: ['search', 'test']
          }
        }
      ],
      count: async () => 1,
      exists: async () => true,
      getById: async () => null
      // No search method - will use fallback
    };

    const mockConfig = {
      isCacheEnabled: () => false,
      isDevelopment: () => true,
      getPort: () => 4000,
      getBasePath: () => '/api',
      getCorsOrigin: () => '*',
      getProjectRepositoryType: () => 'database',
      validateConfiguration: () => {}
    };

    const mockCache = {
      getCachedProjects: async () => [],
      setCachedProjects: async () => {},
      regenerateCache: async () => {},
      clearCache: async () => {}
    };

    container.register(
      SERVICE_TOKENS.PROJECT_REPOSITORY,
      () => mockRepo,
      'singleton'
    );
    container.register(
      SERVICE_TOKENS.CONFIG_SERVICE,
      () => mockConfig,
      'singleton'
    );
    container.register(
      SERVICE_TOKENS.CACHE_SERVICE,
      () => mockCache,
      'singleton'
    );

    const app = Fastify();
    await registerProjectsRoutes(app);

    const res = await app.inject({
      method: 'GET',
      url: '/v1/projects/search?q=searchable'
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().results).toHaveLength(1);
  });

  it('handles repository without getByCategory method for category endpoint', async () => {
    // Test fallback category functionality
    resetContainer();
    const { container } = await import('../../lib/di/container');

    const mockRepo = {
      getAll: async () => [],
      getFlat: async () => [
        {
          category: 'demo',
          subCategory: 'test',
          slug: 'categorized',
          project: {
            title: 'Demo Project',
            summary: 'In demo category',
            tags: []
          }
        }
      ],
      count: async () => 1,
      exists: async () => true,
      getById: async () => null
      // No getByCategory method - will use fallback
    };

    const mockConfig = {
      isCacheEnabled: () => false,
      isDevelopment: () => true,
      getPort: () => 4000,
      getBasePath: () => '/api',
      getCorsOrigin: () => '*',
      getProjectRepositoryType: () => 'database',
      validateConfiguration: () => {}
    };

    const mockCache = {
      getCachedProjects: async () => [],
      setCachedProjects: async () => {},
      regenerateCache: async () => {},
      clearCache: async () => {}
    };

    container.register(
      SERVICE_TOKENS.PROJECT_REPOSITORY,
      () => mockRepo,
      'singleton'
    );
    container.register(
      SERVICE_TOKENS.CONFIG_SERVICE,
      () => mockConfig,
      'singleton'
    );
    container.register(
      SERVICE_TOKENS.CACHE_SERVICE,
      () => mockCache,
      'singleton'
    );

    const app = Fastify();
    await registerProjectsRoutes(app);

    const res = await app.inject({
      method: 'GET',
      url: '/v1/projects/category/demo'
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().results).toHaveLength(1);
  });
});
