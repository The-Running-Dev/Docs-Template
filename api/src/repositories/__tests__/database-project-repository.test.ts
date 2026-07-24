import { describe, it, expect, beforeEach, vi } from 'vitest';
import { DatabaseProjectRepository } from '../database-project-repository';
import { IConfigService } from '../interfaces';
import { ProjectEntity } from '../entities/project-entity';

// Mock the DataSource
const mockDataSource = {
  getRepository: vi.fn(),
  initialize: vi.fn(),
  isInitialized: false
} as any;

// Mock TypeORM
vi.mock('typeorm', () => ({
  DataSource: vi.fn(() => mockDataSource),
  Entity: () => () => {},
  PrimaryGeneratedColumn: () => () => {},
  Column: () => () => {},
  CreateDateColumn: () => () => {},
  UpdateDateColumn: () => () => {}
}));

const mockConfig: IConfigService = {
  getDatabaseUrl: () => 'sqlite::memory:',
  getDatabaseType: () => 'sqlite',
  isDevelopment: () => true,
  getProjectRepositoryType: () => 'database'
} as any;

describe('DatabaseProjectRepository', () => {
  let repo: DatabaseProjectRepository;
  let mockRepository: any;

  beforeEach(() => {
    mockRepository = {
      find: vi.fn(),
      findOne: vi.fn(),
      save: vi.fn(),
      count: vi.fn()
    };

    mockDataSource.getRepository.mockReturnValue(mockRepository);
    mockDataSource.initialize.mockResolvedValue(undefined);

    repo = new DatabaseProjectRepository(mockConfig);
  });

  it('should initialize database connection', async () => {
    mockRepository.find.mockResolvedValue([]);
    await repo.getAll();
    expect(mockDataSource.initialize).toHaveBeenCalled();
  });

  it('should return empty array when no projects exist', async () => {
    mockRepository.find.mockResolvedValue([]);

    const result = await repo.getAll();

    expect(result).toEqual([]);
    expect(mockRepository.find).toHaveBeenCalled();
  });

  it('should convert database entities to domain objects', async () => {
    const mockEntity: Partial<ProjectEntity> = {
      id: 1,
      title: 'Test Project',
      summary: 'Test Summary',
      category: 'demo',
      subCategory: 'test',
      slug: 'test-project',
      tags: ['tag1', 'tag2'],
      githubUrl: 'https://github.com/user/repo',
      stars: 10,
      forks: 2
    };

    mockRepository.find.mockResolvedValue([mockEntity]);

    const result = await repo.getFlat();

    expect(result).toHaveLength(1);
    expect(result[0].project.title).toBe('Test Project');
    expect(result[0].project.tags).toEqual(['tag1', 'tag2']);
  });

  it('should find project by composite key', async () => {
    const mockEntity: Partial<ProjectEntity> = {
      id: 1,
      title: 'Test Project',
      category: 'demo',
      subCategory: 'test',
      slug: 'test-project'
    };

    mockRepository.findOne.mockResolvedValue(mockEntity);

    const result = await repo.getById('demo', 'test', 'test-project');

    expect(result).toBeDefined();
    expect(result?.title).toBe('Test Project');
    expect(mockRepository.findOne).toHaveBeenCalledWith({
      where: { category: 'demo', subCategory: 'test', slug: 'test-project' }
    });
  });

  it('should return null when project not found', async () => {
    mockRepository.findOne.mockResolvedValue(null);

    const result = await repo.getById('nonexistent', 'category', 'slug');

    expect(result).toBeNull();
  });

  it('should count total projects', async () => {
    mockRepository.count.mockResolvedValue(42);

    const result = await repo.count();

    expect(result).toBe(42);
    expect(mockRepository.count).toHaveBeenCalled();
  });
});
