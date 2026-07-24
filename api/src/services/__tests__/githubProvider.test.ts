import { describe, it, expect, beforeEach, vi } from 'vitest';
import { GitHubRepoProvider } from '../githubProvider';
import { IConfigService } from '../repositories/interfaces';

// Mock Octokit
const mockOctokit = {
  repos: {
    get: vi.fn(),
    listCommits: vi.fn()
  }
};

vi.mock('@octokit/rest', () => ({
  Octokit: vi.fn(() => mockOctokit)
}));

const mockConfig: IConfigService = {
  getGitHubToken: () => 'mock-token'
} as any;

describe('GitHubRepoProvider', () => {
  let provider: GitHubRepoProvider;

  beforeEach(() => {
    vi.clearAllMocks();
    provider = new GitHubRepoProvider(mockConfig);
  });

  it('should extract repo stats from GitHub API', async () => {
    const mockRepoData = {
      data: {
        stargazers_count: 150,
        forks_count: 25,
        language: 'TypeScript',
        size: 1024,
        open_issues_count: 5
      }
    };

    const mockCommitData = {
      data: [
        {
          commit: {
            author: {
              date: '2024-01-15T10:30:00Z'
            }
          }
        }
      ]
    };

    mockOctokit.repos.get.mockResolvedValue(mockRepoData);
    mockOctokit.repos.listCommits.mockResolvedValue(mockCommitData);

    const stats = await provider.getRepoStats('https://github.com/user/repo');

    expect(stats).toEqual({
      stars: 150,
      forks: 25,
      language: 'TypeScript',
      size: 1024,
      lastCommit: new Date('2024-01-15T10:30:00Z'),
      openIssues: 5
    });
  });

  it('should handle SSH URLs', async () => {
    const mockRepoData = {
      data: {
        stargazers_count: 100,
        forks_count: 10,
        language: 'JavaScript',
        size: 512,
        open_issues_count: 2
      }
    };

    const mockCommitData = {
      data: [
        {
          commit: {
            author: {
              date: '2024-01-10T15:45:00Z'
            }
          }
        }
      ]
    };

    mockOctokit.repos.get.mockResolvedValue(mockRepoData);
    mockOctokit.repos.listCommits.mockResolvedValue(mockCommitData);

    const stats = await provider.getRepoStats('git@github.com:user/repo.git');

    expect(stats.stars).toBe(100);
    expect(stats.language).toBe('JavaScript');
    expect(mockOctokit.repos.get).toHaveBeenCalledWith({
      owner: 'user',
      repo: 'repo'
    });
  });

  it('should handle repositories with no language', async () => {
    const mockRepoData = {
      data: {
        stargazers_count: 50,
        forks_count: 5,
        language: null,
        size: 256,
        open_issues_count: 1
      }
    };

    const mockCommitData = {
      data: [
        {
          commit: {
            author: {
              date: '2024-01-01T12:00:00Z'
            }
          }
        }
      ]
    };

    mockOctokit.repos.get.mockResolvedValue(mockRepoData);
    mockOctokit.repos.listCommits.mockResolvedValue(mockCommitData);

    const stats = await provider.getRepoStats(
      'https://github.com/user/no-lang-repo'
    );

    expect(stats.language).toBe('unknown');
  });

  it('should handle repositories with no commits', async () => {
    const mockRepoData = {
      data: {
        stargazers_count: 0,
        forks_count: 0,
        language: 'Python',
        size: 10,
        open_issues_count: 0
      }
    };

    const mockCommitData = {
      data: []
    };

    mockOctokit.repos.get.mockResolvedValue(mockRepoData);
    mockOctokit.repos.listCommits.mockResolvedValue(mockCommitData);

    const stats = await provider.getRepoStats(
      'https://github.com/user/empty-repo'
    );

    expect(stats.lastCommit).toBeInstanceOf(Date);
    expect(stats.stars).toBe(0);
  });

  it('should throw error for invalid URL', async () => {
    await expect(
      provider.getRepoStats('https://invalid-url.com/repo')
    ).rejects.toThrow('Invalid GitHub repository URL');
  });

  it('should handle API errors', async () => {
    mockOctokit.repos.get.mockRejectedValue(new Error('API Error'));

    await expect(
      provider.getRepoStats('https://github.com/user/error-repo')
    ).rejects.toThrow('API Error');
  });

  it('should implement rate limiting', async () => {
    const mockRepoData = {
      data: {
        stargazers_count: 1,
        forks_count: 1,
        language: 'JavaScript',
        size: 1,
        open_issues_count: 1
      }
    };

    const mockCommitData = { data: [] };

    mockOctokit.repos.get.mockResolvedValue(mockRepoData);
    mockOctokit.repos.listCommits.mockResolvedValue(mockCommitData);

    const start = Date.now();

    // Make two rapid calls
    await Promise.all([
      provider.getRepoStats('https://github.com/user/repo1'),
      provider.getRepoStats('https://github.com/user/repo2')
    ]);

    const elapsed = Date.now() - start;

    // Should take at least 1000ms due to rate limiting
    expect(elapsed).toBeGreaterThanOrEqual(1000);
  });
});
