import React from 'react';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, fireEvent, act } from '@testing-library/react';

import Custom404Component from '../Custom404';

describe('Custom404Component', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('renders main 404 heading and message', () => {
    render(<Custom404Component />);

    expect(screen.getByText('404')).toBeInTheDocument();
    expect(
      screen.getByText(/OOPS! PAGE WENT TO WONDERLAND!/)
    ).toBeInTheDocument();
    expect(
      screen.getByText(/The page you're looking for has mysteriously vanished/)
    ).toBeInTheDocument();
  });

  it('shows excuse generator that rotates excuses', () => {
    render(<Custom404Component />);

    expect(
      screen.getByText('🎭 Official Excuse Generator™')
    ).toBeInTheDocument();

    // Get initial excuse (first one in the array)
    expect(screen.getByText(/🐕 A dog ate the page/)).toBeInTheDocument();
  });

  it('shows cat facts section with spin button', () => {
    render(<Custom404Component />);

    expect(screen.getByText('🎰 Spin for Cat Facts!')).toBeInTheDocument();
    expect(
      screen.getByRole('button', { name: /SPIN FOR WISDOM/ })
    ).toBeInTheDocument();

    // The cat fact paragraph element should exist
    const catFactElements = screen.getAllByText(/70%|clowder|taste|toes|purr/);
    expect(catFactElements.length).toBeGreaterThan(0);
  });

  it('handles spin button click', async () => {
    render(<Custom404Component />);

    const spinButton = screen.getByRole('button', { name: /SPIN FOR WISDOM/ });

    await act(async () => {
      fireEvent.click(spinButton);
    });

    // Button should have spinning transform initially
    expect(spinButton).toHaveStyle('transform: rotate(360deg)');

    // Fast forward animation
    act(() => {
      vi.advanceTimersByTime(1000);
    });

    // Verify button returns to normal after animation
    expect(spinButton).toHaveStyle('transform: none');
  });

  it('offers only the site root when no links are supplied', () => {
    render(<Custom404Component />);

    expect(screen.getByText('🚀 Emergency Navigation')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /Go Home/ })).toHaveAttribute(
      'href',
      '/'
    );

    // Nothing beyond "/" is guaranteed to resolve on a consumer's site, so the
    // default must not emit any other route.
    expect(screen.getAllByRole('link')).toHaveLength(1);
  });

  it('shows supplied emergency navigation links', () => {
    render(
      <Custom404Component
        links={[
          { to: '/docs', label: '📚 Read Docs' },
          { to: '/demos', label: '🎮 Try Demos' }
        ]}
      />
    );

    expect(screen.getByRole('link', { name: /Go Home/ })).toHaveAttribute(
      'href',
      '/'
    );
    expect(screen.getByRole('link', { name: /Read Docs/ })).toHaveAttribute(
      'href',
      '/docs'
    );
    expect(screen.getByRole('link', { name: /Try Demos/ })).toHaveAttribute(
      'href',
      '/demos'
    );
  });

  it('renders repeated routes without duplicate-key warnings', () => {
    const consoleError = vi
      .spyOn(console, 'error')
      .mockImplementation(() => {});

    render(
      <Custom404Component
        links={[
          { to: '/docs', label: '📚 Read Docs', description: 'the docs' },
          { to: '/docs', label: '📖 Browse Guides', description: 'the guides' }
        ]}
      />
    );

    expect(screen.getByRole('link', { name: /Read Docs/ })).toBeInTheDocument();
    expect(
      screen.getByRole('link', { name: /Browse Guides/ })
    ).toBeInTheDocument();
    expect(consoleError).not.toHaveBeenCalled();

    consoleError.mockRestore();
  });

  it('shows troubleshooting sections', () => {
    render(<Custom404Component />);

    expect(
      screen.getByText('🛠️ Troubleshooting Steps (Not Guaranteed to Work)')
    ).toBeInTheDocument();
    expect(screen.getByText('🔧 Technical Solutions:')).toBeInTheDocument();
    expect(screen.getByText('🎪 Creative Solutions:')).toBeInTheDocument();

    // Check for some of the funny troubleshooting steps
    expect(screen.getByText(/Turn it off and on again/)).toBeInTheDocument();
    expect(screen.getByText(/Draw the page on paper/)).toBeInTheDocument();
  });

  it('shows statistics with random numbers', () => {
    render(<Custom404Component />);

    expect(screen.getByText('Pages Found Today')).toBeInTheDocument();
    expect(screen.getByText('Robots Consulted')).toBeInTheDocument();
    expect(screen.getByText('Coffee Consumed')).toBeInTheDocument();

    // Check that statistics show numbers (they're random but should be present)
    expect(screen.getByText(/This one wasn't one of them/)).toBeInTheDocument();
    expect(
      screen.getByText(/They're as confused as you are/)
    ).toBeInTheDocument();
    expect(
      screen.getByText(/By our developers while fixing this/)
    ).toBeInTheDocument();
  });

  it('shows call to action without prose links by default', () => {
    render(<Custom404Component />);

    expect(
      screen.getByText('🎨 Did you enjoy this 404 page?')
    ).toBeInTheDocument();
    expect(
      screen.getByText(/imagine how amazing our actual content is/)
    ).toBeInTheDocument();
    expect(screen.queryByText(/why not check out/)).not.toBeInTheDocument();

    // Check for the fun fact with random number
    expect(screen.getByText(/Fun Fact/)).toBeInTheDocument();
    expect(
      screen.getByText(/This number is completely made up/)
    ).toBeInTheDocument();
  });

  it('names described links in the call to action', () => {
    render(
      <Custom404Component
        links={[
          {
            to: '/demos',
            label: '🎮 Try Demos',
            description: 'component demos'
          },
          {
            to: '/docs',
            label: '📚 Read Docs',
            description: 'documentation'
          }
        ]}
      />
    );

    expect(
      screen.getByRole('link', { name: 'component demos' })
    ).toHaveAttribute('href', '/demos');
    expect(screen.getByRole('link', { name: 'documentation' })).toHaveAttribute(
      'href',
      '/docs'
    );
    expect(screen.getByText(/why not check out/)).toBeInTheDocument();
  });

  it('omits undescribed links from the call to action', () => {
    render(
      <Custom404Component links={[{ to: '/docs', label: 'Read Docs' }]} />
    );

    // The button is still offered, but a link with no description contributes
    // no prose, so the sentence stays off.
    expect(screen.getByRole('link', { name: 'Read Docs' })).toHaveAttribute(
      'href',
      '/docs'
    );
    expect(screen.queryByText(/why not check out/)).not.toBeInTheDocument();
  });
});
