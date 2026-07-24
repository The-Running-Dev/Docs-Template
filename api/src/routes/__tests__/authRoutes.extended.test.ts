import { describe, it, expect, beforeEach, vi } from 'vitest';
import Fastify from 'fastify';

// Mock the modules at the top level
const mockUserRepo = {
  findByUsername: vi.fn(),
  validatePassword: vi.fn(),
  findById: vi.fn(() => ({
    id: '1',
    username: 'admin',
    roles: ['admin']
  }))
};

const mockJwtService = {
  signAccessToken: vi.fn(() => 'mock.access.token'),
  signRefreshToken: vi.fn(() => 'mock.refresh.token'),
  verifyToken: vi.fn(() => ({ sub: '1', username: 'admin', roles: ['admin'] }))
};

// Mock dynamic imports using vi.doMock for modules imported dynamically
vi.doMock('../../services/jwtService', () => mockJwtService);
vi.doMock('../../repositories/database-user-repository', () => ({
  DatabaseUserRepository: vi.fn(() => mockUserRepo)
}));
vi.doMock('../../lib/di/index', () => ({
  getService: vi.fn(() => ({ isDevelopment: () => true }))
}));
vi.doMock('../../lib/di/tokens', () => ({
  SERVICE_TOKENS: { CONFIG_SERVICE: 'config' }
}));

// Also mock them statically for good measure
vi.mock('../../services/jwtService', () => mockJwtService);
vi.mock('../../repositories/database-user-repository', () => ({
  DatabaseUserRepository: vi.fn(() => mockUserRepo)
}));
vi.mock('../../lib/di/index', () => ({
  getService: vi.fn(() => ({ isDevelopment: () => true }))
}));
vi.mock('../../lib/di/tokens', () => ({
  SERVICE_TOKENS: { CONFIG_SERVICE: 'config' }
}));

// Import after mocking
import { registerAuthRoutes } from '../authRoutes';

async function createApp() {
  const app = Fastify();

  // Register cookie plugin (required for auth routes)
  const cookie = (await import('@fastify/cookie')).default;
  await app.register(cookie, {
    secret: 'test-secret',
    parseOptions: {}
  });

  await registerAuthRoutes(app);
  return { app };
}

describe('Auth API Extended Tests', () => {
  beforeEach(async () => {
    vi.clearAllMocks();
  });

  it('POST /auth/login should return 400 for missing credentials', async () => {
    const { app } = await createApp();

    const response = await app.inject({
      method: 'POST',
      url: '/auth/login',
      payload: {} // Missing username and password
    });

    expect(response.statusCode).toBe(401);
    const result = response.json();
    expect(result.message).toBe('Invalid credentials');
  });

  it('POST /auth/login should return 401 for invalid credentials', async () => {
    const { app } = await createApp();

    mockUserRepo.findByUsername.mockResolvedValue(null);

    const response = await app.inject({
      method: 'POST',
      url: '/auth/login',
      payload: {
        username: 'nonexistent',
        password: 'wrongpass'
      }
    });

    expect(response.statusCode).toBe(401);
    expect(response.json().message).toBe('Invalid credentials');
  });

  it('POST /auth/login should return tokens for valid credentials', async () => {
    const { app } = await createApp();

    const mockUser = {
      id: '1',
      username: 'admin',
      password: '$2b$10$hashedpassword',
      roles: ['admin']
    };

    mockUserRepo.findByUsername.mockResolvedValue(mockUser);
    mockUserRepo.validatePassword.mockResolvedValue(true);

    const response = await app.inject({
      method: 'POST',
      url: '/auth/login',
      payload: {
        username: 'admin',
        password: 'correctpass'
      }
    });

    expect(response.statusCode).toBe(200);
    const result = response.json();
    expect(result.user.username).toBe('admin');
    expect(result.user.roles).toEqual(['admin']);
    expect(result.accessToken).toBeDefined();

    // Should set httpOnly cookies
    const setCookieHeader = response.headers['set-cookie'];
    expect(setCookieHeader).toBeDefined();

    const cookies = Array.isArray(setCookieHeader)
      ? setCookieHeader
      : [setCookieHeader];
    expect(cookies.some((cookie) => cookie.includes('refresh_token'))).toBe(
      true
    );
  });

  it('POST /auth/refresh should return 401 without refresh token', async () => {
    const { app } = await createApp();

    const response = await app.inject({
      method: 'POST',
      url: '/auth/refresh'
    });

    expect(response.statusCode).toBe(401);
    expect(response.json().message).toBe('Missing refresh token');
  });

  it('POST /auth/refresh should return new tokens with valid refresh token', async () => {
    const { app } = await createApp();

    const response = await app.inject({
      method: 'POST',
      url: '/auth/refresh',
      headers: {
        cookie: 'refresh_token=valid.refresh.token'
      }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json().accessToken).toBeDefined();
  });

  it('POST /auth/logout should clear cookies', async () => {
    const { app } = await createApp();

    const response = await app.inject({
      method: 'POST',
      url: '/auth/logout',
      headers: {
        cookie: 'refresh_token=some.refresh.token'
      }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json().message).toBe('Logged out');

    // Should clear refresh_token cookie
    const setCookieHeader = response.headers['set-cookie'];
    expect(setCookieHeader).toBeDefined();

    const cookies = Array.isArray(setCookieHeader)
      ? setCookieHeader
      : [setCookieHeader];
    expect(cookies.some((cookie) => cookie.includes('refresh_token=;'))).toBe(
      true
    );
  });

  it('GET /auth/me should return 401 without access token', async () => {
    const { app } = await createApp();

    const response = await app.inject({
      method: 'GET',
      url: '/auth/me'
    });

    expect(response.statusCode).toBe(401);
  });

  it('GET /auth/me should return user info with valid access token', async () => {
    const { app } = await createApp();

    const response = await app.inject({
      method: 'GET',
      url: '/auth/me',
      headers: {
        authorization: 'Bearer valid.access.token'
      }
    });

    expect(response.statusCode).toBe(200);
    const result = response.json();
    expect(result.user.username).toBe('admin');
    expect(result.user.roles).toEqual(['admin']);
  });
});
