import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen } from '@testing-library/react';

import ContentWrapper from '../index';

describe('NotFound ContentWrapper', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('renders the shared 404 component', () => {
    render(<ContentWrapper />);

    expect(screen.getByText('404')).toBeInTheDocument();
    expect(screen.getByText('🚀 Emergency Navigation')).toBeInTheDocument();
  });

  it('emits no route beyond the site root', () => {
    render(<ContentWrapper />);

    // Every site built from this template inherits this wrapper, and only "/"
    // is guaranteed to resolve everywhere: a consumer may serve docs from the
    // site root or disable the pages plugin. Passing any other route from here
    // dangles on those sites and fails their build under
    // `onBrokenLinks: 'throw'`.
    //
    // This is the assertion that keeps that promise. If you are here because
    // you added links to the wrapper, add them to your own site's override
    // instead — do not relax this test.
    const links = screen.getAllByRole('link');

    expect(links).toHaveLength(1);
    expect(links[0]).toHaveAttribute('href', '/');
  });
});
