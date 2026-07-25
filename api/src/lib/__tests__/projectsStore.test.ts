import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import fs from 'node:fs';
import {
  slugify,
  getFlatFromStorage,
  combineToNested,
  getProjectsCombined,
  getProject,
  saveProject,
  deleteProject
} from '../projectsStore';

// Mock fs module
vi.mock('node:fs');

const mockFs = vi.mocked(fs);

describe('ProjectsStore', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('slugify', () => {
    it('converts strings to valid slugs', () => {
      expect(slugify('Hello World')).toBe('hello-world');
      expect(slugify('My Project 123')).toBe('my-project-123');
      expect(slugify('Special@Characters#')).toBe('special-characters');
      expect(slugify('  Multiple   Spaces  ')).toBe('multiple-spaces');
    });

    it('handles empty strings', () => {
      expect(slugify('')).toBe('');
      expect(slugify('   ')).toBe('');
    });

    it('handles non-latin characters', () => {
      expect(slugify('café')).toBe('caf');
      expect(slugify('naïve')).toBe('na-ve');
    });

    it('removes consecutive dashes', () => {
      expect(slugify('hello--world')).toBe('hello-world');
      expect(slugify('hello---world')).toBe('hello-world');
    });

    it('removes leading and trailing dashes', () => {
      expect(slugify('-hello-world-')).toBe('hello-world');
      expect(slugify('--hello--')).toBe('hello');
    });
  });

  describe('getFlatFromStorage', () => {
    it('loads projects from storage directory', () => {
      // Mock directory structure
      mockFs.existsSync.mockImplementation((path: any) => {
        if (path.includes('storage/projects')) return true;
        if (path.includes('demo')) return true;
        if (path.includes('examples')) return true;
        return false;
      });

      mockFs.readdirSync.mockImplementation((path: any) => {
        if (path.includes('storage/projects')) return ['demo'] as any;
        if (path.includes('demo')) return ['examples'] as any;
        if (path.includes('examples')) return ['test-project.json'] as any;
        return [] as any;
      });

      mockFs.statSync.mockReturnValue({ isDirectory: () => true } as any);

      const mockProject = {
        title: 'Test Project',
        summary: 'A test project',
        tags: ['test'],
        status: 'active',
        url: 'https://example.com',
        repository: 'https://github.com/test/test',
        technologies: ['TypeScript'],
        category: 'demo',
        subCategory: 'examples',
        createdAt: '2023-01-01',
        updatedAt: '2023-01-01'
      };

      mockFs.readFileSync.mockReturnValue(JSON.stringify(mockProject));

      const result = getFlatFromStorage();
      expect(Array.isArray(result)).toBe(true);
    });

    it('handles file system errors gracefully', () => {
      mockFs.existsSync.mockImplementation(() => {
        throw new Error('File system error');
      });

      const consoleSpy = vi
        .spyOn(console, 'error')
        .mockImplementation(() => {});

      const result = getFlatFromStorage();
      expect(result).toEqual([]);
      expect(consoleSpy).toHaveBeenCalled();

      consoleSpy.mockRestore();
    });
  });

  describe('combineToNested', () => {
    it('combines flat projects into nested structure', () => {
      const flatProjects = [
        {
          category: 'demo',
          subCategory: 'examples',
          slug: 'test-project',
          project: {
            title: 'Test Project',
            summary: 'A test project',
            tags: ['test'],
            status: 'active' as const,
            url: 'https://example.com',
            repository: 'https://github.com/test/test',
            technologies: ['TypeScript'],
            category: 'demo',
            subCategory: 'examples',
            createdAt: '2023-01-01',
            updatedAt: '2023-01-01'
          }
        }
      ];

      const result = combineToNested(flatProjects);
      expect(result).toHaveLength(1);
      expect(result[0].category).toBe('demo');
      expect(result[0].subCategories).toHaveLength(1);
      expect(result[0].subCategories[0].name).toBe('examples');
      expect(result[0].subCategories[0].projects).toHaveLength(1);
    });

    it('handles empty array', () => {
      const result = combineToNested([]);
      expect(result).toEqual([]);
    });
  });

  describe('getProjectsCombined', () => {
    it('returns combined project structure', () => {
      // Mock the file system calls that will be made internally
      mockFs.existsSync.mockReturnValue(false);

      const result = getProjectsCombined();
      expect(Array.isArray(result)).toBe(true);
    });
  });

  describe('getProject', () => {
    it('finds project by category, subcategory, and slug', () => {
      const mockProject = {
        title: 'Test Project',
        summary: 'A test project',
        tags: ['test'],
        status: 'active' as const,
        url: 'https://example.com',
        repository: 'https://github.com/test/test',
        technologies: ['TypeScript'],
        category: 'demo',
        subCategory: 'examples',
        createdAt: '2023-01-01',
        updatedAt: '2023-01-01'
      };

      mockFs.existsSync.mockReturnValue(true);
      mockFs.readFileSync.mockReturnValue(JSON.stringify(mockProject));

      const result = getProject('demo', 'examples', 'test-project');
      expect(result).toEqual(mockProject);
    });

    it('returns null for non-existent project', () => {
      mockFs.existsSync.mockReturnValue(false);

      const result = getProject('demo', 'examples', 'nonexistent');
      expect(result).toBeNull();
    });

    it('handles JSON parsing errors gracefully', () => {
      mockFs.existsSync.mockReturnValue(true);
      mockFs.readFileSync.mockReturnValue('invalid json');

      const consoleSpy = vi
        .spyOn(console, 'error')
        .mockImplementation(() => {});

      const result = getProject('demo', 'examples', 'test-project');
      expect(result).toBeNull();
      expect(consoleSpy).toHaveBeenCalled();

      consoleSpy.mockRestore();
    });
  });

  describe('saveProject', () => {
    it('saves project to correct file path', () => {
      const project = {
        title: 'New Project',
        summary: 'A new project',
        tags: ['new'],
        syncEnabled: true,
        syncInterval: 'daily' as const
      };

      mockFs.mkdirSync.mockImplementation(() => undefined as any);
      mockFs.writeFileSync.mockImplementation(() => {});

      const result = saveProject('demo', 'examples', 'new-project', project);

      expect(mockFs.mkdirSync).toHaveBeenCalled();
      expect(mockFs.writeFileSync).toHaveBeenCalledWith(
        expect.stringContaining('new-project.json.tmp'),
        expect.stringContaining('"title": "New Project"'),
        'utf8'
      );
      expect(result).toEqual({
        ...project,
        lastModified: expect.any(String)
      });
    });

    it('handles file system errors when saving', () => {
      const project = {
        title: 'New Project',
        summary: 'A new project',
        tags: ['new'],
        status: 'active' as const,
        url: 'https://example.com',
        repository: 'https://github.com/test/new',
        technologies: ['TypeScript'],
        category: 'demo',
        subCategory: 'examples',
        createdAt: '2023-01-01',
        updatedAt: '2023-01-01'
      };

      mockFs.mkdirSync.mockImplementation(() => {
        throw new Error('Permission denied');
      });

      expect(() =>
        saveProject('demo', 'examples', 'new-project', project)
      ).toThrow('Permission denied');
    });
  });

  describe('deleteProject', () => {
    it('deletes project file', () => {
      mockFs.existsSync.mockReturnValue(true);
      mockFs.unlinkSync.mockImplementation(() => {});

      deleteProject('demo', 'examples', 'test-project');

      expect(mockFs.unlinkSync).toHaveBeenCalledWith(
        expect.stringContaining('test-project.json')
      );
    });

    it('handles deletion of non-existent project', () => {
      mockFs.existsSync.mockReturnValue(false);

      // Should not throw an error - just do nothing
      expect(() =>
        deleteProject('demo', 'examples', 'nonexistent')
      ).not.toThrow();
    });

    it('handles file system errors when deleting', () => {
      mockFs.existsSync.mockReturnValue(true);
      mockFs.unlinkSync.mockImplementation(() => {
        throw new Error('Permission denied');
      });

      expect(() => deleteProject('demo', 'examples', 'test-project')).toThrow(
        'Permission denied'
      );
    });
  });
});
