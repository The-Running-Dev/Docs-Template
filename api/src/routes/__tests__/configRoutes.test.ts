import { describe, it, expect } from 'vitest';
import Fastify from 'fastify';
import { registerConfigRoutes } from '../configRoutes';

async function createApp() {
  const app = Fastify();
  await registerConfigRoutes(app);
  return app;
}

describe('Config API', () => {
  it('GET /v1 returns 200 and version object', async () => {
    const app = await createApp();
    const res = await app.inject({ method: 'GET', url: '/v1' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toHaveProperty('version');
  });

  // Add more tests for config updates as needed
});
