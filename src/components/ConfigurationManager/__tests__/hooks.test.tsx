import React from 'react';
import { act, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';

import { ConfigurationManager } from '../ConfigurationManager';
import { FeatureFlagManager } from '../FeatureFlagManager';
import { useConfiguration, useFeatureFlag } from '../hooks';

function ConfigurationProbe({ manager }: { manager: ConfigurationManager }) {
  const [maxItems, setMaxItems] = useConfiguration<number>(manager, 'ui.maxItems', 10);
  return (
    <div>
      <span data-testid="value">{maxItems}</span>
      <button type="button" onClick={() => setMaxItems(maxItems + 1)}>
        increment
      </button>
    </div>
  );
}

function FeatureFlagProbe({ manager }: { manager: FeatureFlagManager }) {
  const [enabled, loading] = useFeatureFlag(manager, 'beta-feature');
  return <span data-testid="state">{loading ? 'loading' : enabled ? 'enabled' : 'disabled'}</span>;
}

describe('useConfiguration', () => {
  it('reads the manager value and re-renders after setValue', async () => {
    const manager = new ConfigurationManager({ enablePersistence: false });
    await manager.registerSchema({ key: 'ui.maxItems', defaultValue: 10, type: 'number' });

    render(<ConfigurationProbe manager={manager} />);
    expect(screen.getByTestId('value').textContent).toBe('10');

    await userEvent.click(screen.getByText('increment'));

    expect(screen.getByTestId('value').textContent).toBe('11');
  });

  it('re-renders when the value changes from outside the component', async () => {
    const manager = new ConfigurationManager({ enablePersistence: false });
    await manager.registerSchema({ key: 'ui.maxItems', defaultValue: 10, type: 'number' });

    render(<ConfigurationProbe manager={manager} />);

    await act(async () => {
      await manager.set('ui.maxItems', 99);
    });

    expect(screen.getByTestId('value').textContent).toBe('99');
  });
});

describe('useFeatureFlag', () => {
  it('resolves from loading to the evaluated flag state', async () => {
    const manager = new FeatureFlagManager({ enablePersistence: false });
    await manager.defineFlag('beta-feature', true);

    render(<FeatureFlagProbe manager={manager} />);

    expect(await screen.findByText('enabled')).toBeInTheDocument();
  });

  it('re-evaluates when the flag is toggled', async () => {
    const manager = new FeatureFlagManager({ enablePersistence: false });
    await manager.defineFlag('beta-feature', false);

    render(<FeatureFlagProbe manager={manager} />);
    expect(await screen.findByText('disabled')).toBeInTheDocument();

    await act(async () => {
      await manager.setFlagEnabled('beta-feature', true);
    });

    expect(await screen.findByText('enabled')).toBeInTheDocument();
  });
});
