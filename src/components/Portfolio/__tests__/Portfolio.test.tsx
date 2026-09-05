import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';

// Mock feature flags
vi.mock('../../config', () => ({
  useFeaturesConfig: () => ({ portfolioPage: true })
}));

// Mock Docusaurus context via local wrapper to avoid loading real package
vi.mock('../../../docusaurus/useDocusaurusContext', () => ({
  default: () => ({ siteConfig: { title: 'Site Title' } })
}));

// Stub child components to focus on top-level behavior
vi.mock('../components', () => ({
  Stats: ({ stats }: any) => <div data-testid="Stats">{stats?.length}</div>,
  Categories: ({ categories }: any) => <div data-testid="Categories">{categories?.length}</div>,
  RecentProjects: ({ projects }: any) => <div data-testid="Recent">{projects?.length}</div>,
  TechStack: ({ technologies }: any) => <div data-testid="Tech">{technologies?.length}</div>
}));

function pendingResult(id: string) {
  return {
    ok: false as const,
    reason: 'json.unresolved' as const,
    message: 'loading',
    data: null,
    meta: {
      id,
      provider: 'none' as const,
      location: '',
      bytes: 0,
      digest: null,
      cached: false,
      attempts: 0,
      validated: false
    },
    loading: true,
    refetch: vi.fn()
  };
}

function okResult(id: string, data: unknown) {
  return {
    ok: true as const,
    reason: 'json.ok' as const,
    data,
    meta: {
      id,
      provider: 'http' as const,
      location: `https://example.com/${id}.json`,
      bytes: 10,
      digest: null,
      cached: false,
      attempts: 1,
      validated: false
    },
    loading: false,
    refetch: vi.fn()
  };
}

function errorResult(id: string, message: string) {
  return {
    ok: false as const,
    reason: 'json.transport' as const,
    message,
    data: null,
    meta: {
      id,
      provider: 'none' as const,
      location: '',
      bytes: 0,
      digest: null,
      cached: false,
      attempts: 1,
      validated: false
    },
    loading: false,
    refetch: vi.fn()
  };
}

let portfolioResult: any = pendingResult('portfolio');
let projectsResult: any = okResult('projects', []);

vi.mock('subzerodev-data-json/react', () => ({
  useJson: (id: string) => (id === 'portfolio' ? portfolioResult : projectsResult)
}));

vi.mock('../../../config/schemas', () => ({
  portfolioSchema: (raw: unknown) => ({ ok: true, value: raw }),
  projectsSchema: (raw: unknown) => ({ ok: true, value: raw })
}));

import Portfolio from '../Portfolio';

describe('Portfolio', () => {
  beforeEach(() => {
    portfolioResult = pendingResult('portfolio');
    projectsResult = okResult('projects', []);
  });

  it('shows loading', () => {
    portfolioResult = pendingResult('portfolio');
    render(<Portfolio />);
    expect(screen.getByText(/Loading Portfolio/)).toBeInTheDocument();
  });

  it('shows error', () => {
    portfolioResult = errorResult('portfolio', 'boom');
    render(<Portfolio />);
    expect(screen.getByText(/Error Loading Portfolio: boom/)).toBeInTheDocument();
  });

  it('shows empty when no header', () => {
    portfolioResult = okResult('portfolio', {});
    render(<Portfolio />);
    expect(screen.getByText(/No Portfolio Data Found/)).toBeInTheDocument();
  });

  it('renders header and sections with data', () => {
    portfolioResult = okResult('portfolio', {
      header: { title: 'My Portfolio', subtitle: 'Sub' },
      stats: [{}, {}],
      projects: [{ category: 'Web', subCategories: [] }],
      technologies: [{ name: 'React', category: 'Web' }]
    });
    render(<Portfolio />);
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('My Portfolio');
    expect(screen.getByText('Sub')).toBeInTheDocument();
    expect(screen.getByTestId('Stats').textContent).toBe('2');
    expect(screen.getByTestId('Categories').textContent).toBe('1');
    // Recent stub receives projects from useProjects; without wiring, it will be 0; we assert presence only
    expect(screen.getByTestId('Recent')).toBeInTheDocument();
    expect(screen.getByTestId('Tech').textContent).toBe('1');
  });
});
