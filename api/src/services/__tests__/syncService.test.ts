import { describe, it, expect, beforeEach, vi } from 'vitest';
import { SyncService } from '../syncService';
import {
  IProjectRepository,
  IRepoProvider,
  ICacheService,
  IConfigService,
  FlatProject
} from '../repositories/interfaces';

// Mock node-cron

vi.mock('node-cron', () => ({
  default: {
    schedule: vi.fn()
  },
  schedule: vi.fn()
}));

import cron from 'node-cron';
const mockSchedule = vi.mocked(cron.schedule);

describe('SyncService', () => {
  let syncService: SyncService;
  let mockRepo: IProjectRepository;
  let mockProvider: IRepoProvider;
  let mockCache: ICacheService;
  let mockConfig: IConfigService;

  beforeEach(() => {
    vi.clearAllMocks();

    mockRepo = {
      getFlat: vi.fn(),
      getByNumericId: vi.fn(),
      save: vi.fn()
    } as any;

    mockProvider = {
      getRepoStats: vi.fn()
    } as any;

    mockCache = {
      regenerateCache: vi.fn()
    } as any;

    mockConfig = {
      isSyncEnabled: vi.fn(),
      getSyncInterval: vi.fn()
    } as any;

    syncService = new SyncService(
      mockRepo,
      mockProvider,
      mockCache,
      mockConfig
    );
  });

  it('should not start cron job when sync is disabled', () => {
    vi.mocked(mockConfig.isSyncEnabled).mockReturnValue(false);

    syncService.start();

    expect(mockSchedule).not.toHaveBeenCalled();
  });

  it('should start daily cron job when sync is enabled', () => {
    vi.mocked(mockConfig.isSyncEnabled).mockReturnValue(true);
    vi.mocked(mockConfig.getSyncInterval).mockReturnValue('daily');

    const mockTask = {
      id: 'mock-id',
      start: vi.fn(),
      stop: vi.fn(),
      getStatus: vi.fn(),
      destroy: vi.fn(),
      isRunning: vi.fn(),
      getNextDates: vi.fn(),
      addCallback: vi.fn(),
      removeCallback: vi.fn(),
      getCallbacks: vi.fn(),
      execute: vi.fn(),
      getNextRun: vi.fn(),
      on: vi.fn(),
      off: vi.fn(),
      once: vi.fn()
    };
    mockSchedule.mockReturnValue(mockTask);

    syncService.start();

    expect(mockSchedule).toHaveBeenCalledWith(
      '0 0 * * *',
      expect.any(Function)
    );
  });

  it('should start weekly cron job when configured', () => {
    vi.mocked(mockConfig.isSyncEnabled).mockReturnValue(true);
    vi.mocked(mockConfig.getSyncInterval).mockReturnValue('weekly');

    const mockTask = {
      id: 'mock-id',
      start: vi.fn(),
      stop: vi.fn(),
      getStatus: vi.fn(),
      destroy: vi.fn(),
      isRunning: vi.fn(),
      getNextDates: vi.fn(),
      addCallback: vi.fn(),
      removeCallback: vi.fn(),
      getCallbacks: vi.fn(),
      execute: vi.fn(),
      getNextRun: vi.fn(),
      on: vi.fn(),
      off: vi.fn(),
      once: vi.fn()
    };
    mockSchedule.mockReturnValue(mockTask);

    syncService.start();

    expect(mockSchedule).toHaveBeenCalledWith(
      '0 0 * * 0',
      expect.any(Function)
    );
  });

  it('should sync all projects', async () => {
    const mockProjects: FlatProject[] = [
      {
        category: 'demo',
        subCategory: 'test',
        slug: 'project1',
        project: {
          title: 'Project 1',
          summary: 'Test project',
          tags: [],
          repoUrl: 'https://github.com/user/project1',
          syncEnabled: true
        }
      },
      {
        category: 'demo',
        subCategory: 'test',
        slug: 'project2',
        project: {
          title: 'Project 2',
          summary: 'Another test project',
          tags: [],
          repoUrl: 'https://github.com/user/project2',
          syncEnabled: true
        }
      }
    ];

    const mockStats = {
      stars: 50,
      forks: 10,
      language: 'TypeScript',
      size: 1024,
      lastCommit: new Date(),
      openIssues: 2
    };

    vi.mocked(mockRepo.getFlat).mockResolvedValue(mockProjects);
    vi.mocked(mockProvider.getRepoStats).mockResolvedValue(mockStats);
    vi.mocked(mockRepo.save).mockResolvedValue(mockProjects[0].project);

    await syncService.syncAll();

    expect(mockProvider.getRepoStats).toHaveBeenCalledTimes(2);
    expect(mockProvider.getRepoStats).toHaveBeenCalledWith(
      'https://github.com/user/project1'
    );
    expect(mockProvider.getRepoStats).toHaveBeenCalledWith(
      'https://github.com/user/project2'
    );
    expect(mockCache.regenerateCache).toHaveBeenCalled();
  });

  it('should skip projects without repo URL', async () => {
    const mockProjects: FlatProject[] = [
      {
        category: 'demo',
        subCategory: 'test',
        slug: 'project1',
        project: {
          title: 'Project 1',
          summary: 'Test project',
          tags: [],
          // No repoUrl
          syncEnabled: true
        }
      }
    ];

    vi.mocked(mockRepo.getFlat).mockResolvedValue(mockProjects);

    await syncService.syncAll();

    expect(mockProvider.getRepoStats).not.toHaveBeenCalled();
    expect(mockCache.regenerateCache).toHaveBeenCalled();
  });

  it('should skip projects with sync disabled', async () => {
    const mockProjects: FlatProject[] = [
      {
        category: 'demo',
        subCategory: 'test',
        slug: 'project1',
        project: {
          title: 'Project 1',
          summary: 'Test project',
          tags: [],
          repoUrl: 'https://github.com/user/project1',
          syncEnabled: false
        }
      }
    ];

    vi.mocked(mockRepo.getFlat).mockResolvedValue(mockProjects);

    await syncService.syncAll();

    expect(mockProvider.getRepoStats).not.toHaveBeenCalled();
    expect(mockCache.regenerateCache).toHaveBeenCalled();
  });

  it('should sync single project by ID', async () => {
    const mockProject: FlatProject = {
      category: 'demo',
      subCategory: 'test',
      slug: 'project1',
      project: {
        title: 'Project 1',
        summary: 'Test project',
        tags: [],
        repoUrl: 'https://github.com/user/project1',
        syncEnabled: true
      }
    };

    const mockStats = {
      stars: 100,
      forks: 20,
      language: 'JavaScript',
      size: 2048,
      lastCommit: new Date(),
      openIssues: 5
    };

    vi.mocked(mockRepo.getByNumericId).mockResolvedValue(mockProject);
    vi.mocked(mockProvider.getRepoStats).mockResolvedValue(mockStats);

    await syncService.syncProject(123);

    expect(mockRepo.getByNumericId).toHaveBeenCalledWith(123);
    expect(mockProvider.getRepoStats).toHaveBeenCalledWith(
      'https://github.com/user/project1'
    );
    expect(mockRepo.save).toHaveBeenCalledWith(
      'demo',
      'test',
      'project1',
      expect.objectContaining({
        stats: mockStats,
        lastSyncedAt: expect.any(Date)
      })
    );
    expect(mockCache.regenerateCache).toHaveBeenCalled();
  });

  it('should handle sync errors gracefully', async () => {
    const mockProjects: FlatProject[] = [
      {
        category: 'demo',
        subCategory: 'test',
        slug: 'failing-project',
        project: {
          title: 'Failing Project',
          summary: 'This will fail',
          tags: [],
          repoUrl: 'https://github.com/user/failing-project',
          syncEnabled: true
        }
      }
    ];

    vi.mocked(mockRepo.getFlat).mockResolvedValue(mockProjects);
    vi.mocked(mockProvider.getRepoStats).mockRejectedValue(
      new Error('Network error')
    );

    const consoleSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

    await syncService.syncAll();

    expect(consoleSpy).toHaveBeenCalledWith(
      'Failed to sync Failing Project:',
      expect.any(Error)
    );
    expect(mockCache.regenerateCache).toHaveBeenCalled();

    consoleSpy.mockRestore();
  });

  it('should respect sync intervals and skip recent syncs', async () => {
    const recentSyncTime = new Date(Date.now() - 30 * 60 * 1000); // 30 minutes ago

    const mockProjects: FlatProject[] = [
      {
        category: 'demo',
        subCategory: 'test',
        slug: 'recent-project',
        project: {
          title: 'Recent Project',
          summary: 'Recently synced',
          tags: [],
          repoUrl: 'https://github.com/user/recent-project',
          syncEnabled: true,
          syncInterval: 'daily',
          lastSyncedAt: recentSyncTime
        }
      }
    ];

    vi.mocked(mockRepo.getFlat).mockResolvedValue(mockProjects);

    await syncService.syncAll();

    // Should not sync because it was synced recently
    expect(mockProvider.getRepoStats).not.toHaveBeenCalled();
    expect(mockCache.regenerateCache).toHaveBeenCalled();
  });

  it('should force sync when requested', async () => {
    const recentSyncTime = new Date(Date.now() - 30 * 60 * 1000);

    const mockProject: FlatProject = {
      category: 'demo',
      subCategory: 'test',
      slug: 'recent-project',
      project: {
        title: 'Recent Project',
        summary: 'Recently synced',
        tags: [],
        repoUrl: 'https://github.com/user/recent-project',
        syncEnabled: true,
        syncInterval: 'daily',
        lastSyncedAt: recentSyncTime
      }
    };

    const mockStats = {
      stars: 75,
      forks: 15,
      language: 'Python',
      size: 1536,
      lastCommit: new Date(),
      openIssues: 3
    };

    vi.mocked(mockRepo.getByNumericId).mockResolvedValue(mockProject);
    vi.mocked(mockProvider.getRepoStats).mockResolvedValue(mockStats);

    await syncService.syncProject(123);

    // Should sync despite recent sync because it's forced
    expect(mockProvider.getRepoStats).toHaveBeenCalledWith(
      'https://github.com/user/recent-project'
    );
    expect(mockCache.regenerateCache).toHaveBeenCalled();
  });
});
