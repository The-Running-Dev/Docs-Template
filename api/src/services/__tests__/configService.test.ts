import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { ConfigService } from '../configService';

describe('ConfigService', () => {
  let originalEnv: Record<string, string | undefined>;

  beforeEach(() => {
    // Save original environment
    originalEnv = { ...process.env };
  });

  afterEach(() => {
    // Restore original environment
    process.env = originalEnv;
  });

  it('returns default database type', () => {
    const config = new ConfigService();
    expect(config.getDatabaseType()).toBe('sqlite');
  });

  it('always returns database as project repository type', () => {
    const config = new ConfigService();
    expect(config.getProjectRepositoryType()).toBe('database');
  });

  it('returns configured database type from environment', () => {
    process.env.DATABASE_TYPE = 'postgres';
    const config = new ConfigService();
    expect(config.getDatabaseType()).toBe('postgres');
  });

  it('returns default database type for invalid value', () => {
    process.env.DATABASE_TYPE = 'invalid';
    const config = new ConfigService();
    expect(config.getDatabaseType()).toBe('sqlite');
  });

  it('always returns database repository type', () => {
    // Environment variable no longer affects the result
    process.env.PROJECT_REPOSITORY = 'database';
    const config = new ConfigService();
    expect(config.getProjectRepositoryType()).toBe('database');
  });

  it('returns correct port configuration', () => {
    process.env.PORT = '8080';
    const config = new ConfigService();
    expect(config.getPort()).toBe(8080);
  });

  it('returns default port when not configured', () => {
    delete process.env.PORT;
    const config = new ConfigService();
    expect(config.getPort()).toBe(4000);
  });

  it('returns correct base path configuration', () => {
    process.env.BASE_PATH = '/v2';
    const config = new ConfigService();
    expect(config.getBasePath()).toBe('/v2');
  });

  it('returns correct CORS origin configuration', () => {
    process.env.CORS_ORIGIN = 'https://example.com';
    const config = new ConfigService();
    expect(config.getCorsOrigin()).toBe('https://example.com');
  });

  it('returns admin token when configured', () => {
    process.env.ADMIN_TOKEN = 'secret123';
    const config = new ConfigService();
    expect(config.getAdminToken()).toBe('secret123');
  });

  it('returns undefined admin token when not configured', () => {
    delete process.env.ADMIN_TOKEN;
    const config = new ConfigService();
    expect(config.getAdminToken()).toBeUndefined();
  });

  it('returns GitHub token when configured', () => {
    process.env.GITHUB_TOKEN = 'ghp_123';
    const config = new ConfigService();
    expect(config.getGitHubToken()).toBe('ghp_123');
  });

  it('returns GitLab token when configured', () => {
    process.env.GITLAB_TOKEN = 'glpat_123';
    const config = new ConfigService();
    expect(config.getGitLabToken()).toBe('glpat_123');
  });

  it('returns sync enabled when configured', () => {
    process.env.SYNC_ENABLED = 'true';
    const config = new ConfigService();
    expect(config.isSyncEnabled()).toBe(true);
  });

  it('returns sync disabled by default', () => {
    delete process.env.SYNC_ENABLED;
    const config = new ConfigService();
    expect(config.isSyncEnabled()).toBe(false);
  });

  it('returns cache enabled by default', () => {
    delete process.env.CACHE_ENABLED;
    const config = new ConfigService();
    expect(config.isCacheEnabled()).toBe(true);
  });

  it('returns cache disabled when configured', () => {
    process.env.CACHE_ENABLED = 'false';
    const config = new ConfigService();
    expect(config.isCacheEnabled()).toBe(false);
  });

  it('returns correct sync interval', () => {
    process.env.SYNC_INTERVAL = 'weekly';
    const config = new ConfigService();
    expect(config.getSyncInterval()).toBe('weekly');
  });

  it('returns correct sync cron', () => {
    process.env.SYNC_CRON = '0 0 * * *';
    const config = new ConfigService();
    expect(config.getSyncCron()).toBe('0 0 * * *');
  });

  it('returns correct cache TTL', () => {
    process.env.CACHE_TTL = '7200';
    const config = new ConfigService();
    expect(config.getCacheTTL()).toBe(7200);
  });

  it('detects development environment', () => {
    process.env.NODE_ENV = 'development';
    const config = new ConfigService();
    expect(config.isDevelopment()).toBe(true);
    expect(config.isProduction()).toBe(false);
  });

  it('detects production environment', () => {
    process.env.NODE_ENV = 'production';
    const config = new ConfigService();
    expect(config.isDevelopment()).toBe(false);
    expect(config.isProduction()).toBe(true);
  });

  it('can get and set custom values', () => {
    const config = new ConfigService();
    config.set('CUSTOM_KEY', 'custom-value');
    expect(config.get('CUSTOM_KEY')).toBe('custom-value');
  });

  it('returns default value for missing key', () => {
    const config = new ConfigService();
    expect(config.get('MISSING_KEY', 'default')).toBe('default');
  });

  it('validates configuration in production', () => {
    process.env.NODE_ENV = 'production';
    process.env.ADMIN_TOKEN = 'secret';

    const config = new ConfigService();
    expect(() => config.validateConfiguration()).not.toThrow();
  });

  it('throws error for missing required config in production', () => {
    process.env.NODE_ENV = 'production';
    delete process.env.ADMIN_TOKEN;

    const config = new ConfigService();
    expect(() => config.validateConfiguration()).toThrow(
      'Missing required configuration: ADMIN_TOKEN'
    );
  });

  it('does not throw error for missing config in development', () => {
    process.env.NODE_ENV = 'development';
    delete process.env.ADMIN_TOKEN;

    const config = new ConfigService();
    expect(() => config.validateConfiguration()).not.toThrow();
  });

  it('warns about in-memory database', () => {
    const consoleSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

    process.env.DATABASE_URL = 'sqlite::memory:';
    const config = new ConfigService();
    config.validateConfiguration();

    expect(consoleSpy).toHaveBeenCalledWith(
      'Using in-memory SQLite database - data will not persist'
    );

    consoleSpy.mockRestore();
  });

  it('returns database URL', () => {
    process.env.DATABASE_URL = 'postgresql://user:pass@localhost/db';
    const config = new ConfigService();
    expect(config.getDatabaseUrl()).toBe('postgresql://user:pass@localhost/db');
  });

  it('gets all configuration without exposing sensitive values', () => {
    process.env.ADMIN_TOKEN = 'secret123';
    process.env.GITHUB_TOKEN = 'ghp_secret';
    process.env.PORT = '8080';

    const config = new ConfigService();
    const allConfig = config.getAll();

    expect(allConfig.ADMIN_TOKEN).toBe('[HIDDEN]');
    expect(allConfig.GITHUB_TOKEN).toBe('[HIDDEN]');
    expect(allConfig.PORT).toBe(8080);
  });

  it('shows undefined for missing sensitive values in getAll', () => {
    delete process.env.ADMIN_TOKEN;
    delete process.env.GITHUB_TOKEN;

    const config = new ConfigService();
    const allConfig = config.getAll();

    expect(allConfig.ADMIN_TOKEN).toBeUndefined();
    expect(allConfig.GITHUB_TOKEN).toBeUndefined();
  });
});
