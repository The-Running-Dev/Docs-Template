import { describe, it, expect } from 'vitest';
import Fastify from 'fastify';
import { registerAuthRoutes } from '../authRoutes';

async function createApp() {
  const app = Fastify();
  await registerAuthRoutes(app);
  return app;
}

describe('Auth API', () => {
  it('GET /auth/me without token returns 401', async () => {
    const app = await createApp();
    const res = await app.inject({ method: 'GET', url: '/auth/me' });
    expect(res.statusCode).toBe(401);
  });

  // Add more tests for login, register, etc. as needed
});
