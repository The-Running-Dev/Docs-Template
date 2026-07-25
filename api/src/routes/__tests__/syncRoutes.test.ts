import { describe, it, expect, beforeEach } from 'vitest';
import Fastify from 'fastify';
import { registerSyncRoutes } from '../syncRoutes';
import { resetContainer } from '../../lib/di/index';
import { SERVICE_TOKENS } from '../../lib/di/tokens';

async function createApp() {
  resetContainer();

  // Register mock services
  const { container } = await import('../../lib/di/container');

  // Mock IConfigService
  const mockConfig = {
    getAdminToken: () => 'test-token',
    isSyncEnabled: () => true,
    getSyncInterval: () => 'daily'
  };

  // Mock ISyncService
  const mockSync = {
    syncAll: async () => {},
    syncProject: async () => {},
    start: () => {}
  };

  container.register(
    SERVICE_TOKENS.CONFIG_SERVICE,
    () => mockConfig,
    'singleton'
  );
  container.register(SERVICE_TOKENS.SYNC_SERVICE, () => mockSync, 'singleton');

  const app = Fastify();
  await registerSyncRoutes(app);
  return app;
}

describe('Sync API', () => {
  beforeEach(() => {
    resetContainer();
  });

  it('POST /admin/sync returns 200 with valid token', async () => {
    const app = await createApp();
    const res = await app.inject({
      method: 'POST',
      url: '/admin/sync',
      headers: {
        authorization: 'Bearer test-token'
      }
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toHaveProperty('status', 'ok');
  });

  it('POST /admin/sync returns 401 without token', async () => {
    const app = await createApp();
    const res = await app.inject({
      method: 'POST',
      url: '/admin/sync'
    });
    expect(res.statusCode).toBe(401);
  });

  it('POST /admin/sync/:id returns 200 with valid token', async () => {
    const app = await createApp();
    const res = await app.inject({
      method: 'POST',
      url: '/admin/sync/123',
      headers: {
        authorization: 'Bearer test-token'
      }
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toHaveProperty('status', 'ok');
  });
});
