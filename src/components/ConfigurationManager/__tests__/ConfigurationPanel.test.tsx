import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';

import { ConfigurationManager } from '../ConfigurationManager';
import { ConfigurationPanel } from '../ConfigurationPanel';
import { ConfigurationProvider } from '../ConfigurationContext';
import { FeatureFlagManager } from '../FeatureFlagManager';

async function renderPanel() {
  const configManager = new ConfigurationManager({ enablePersistence: false });
  await configManager.registerSchema({ key: 'ui.maxItems', defaultValue: 10, type: 'number' });

  const featureFlagManager = new FeatureFlagManager({ enablePersistence: false });
  await featureFlagManager.defineFlag('beta-feature', false, { description: 'Beta feature' });

  render(
    <ConfigurationProvider configManager={configManager} featureFlagManager={featureFlagManager}>
      <ConfigurationPanel />
    </ConfigurationProvider>
  );

  return { configManager, featureFlagManager };
}

describe('ConfigurationPanel', () => {
  it('renders collapsed as a toggle button', async () => {
    await renderPanel();
    expect(screen.getByText('Configuration')).toBeInTheDocument();
    expect(screen.queryByText('Runtime configuration')).not.toBeInTheDocument();
  });

  it('opens to show registered configuration values and feature flags', async () => {
    await renderPanel();
    await userEvent.click(screen.getByText('Configuration'));

    expect(screen.getByText('Runtime configuration')).toBeInTheDocument();
    expect(screen.getByLabelText('ui.maxItems')).toHaveValue(10);
    expect(screen.getByLabelText('beta-feature')).not.toBeChecked();
  });

  it('editing a value writes through the configuration manager', async () => {
    const { configManager } = await renderPanel();
    await userEvent.click(screen.getByText('Configuration'));

    const input = screen.getByLabelText('ui.maxItems');
    fireEvent.change(input, { target: { value: '42' } });

    await waitFor(() => expect(configManager.get('ui.maxItems')).toBe(42));
  });

  it('toggling a flag checkbox writes through the feature flag manager', async () => {
    const { featureFlagManager } = await renderPanel();
    await userEvent.click(screen.getByText('Configuration'));

    await userEvent.click(screen.getByLabelText('beta-feature'));

    expect(featureFlagManager.getFlag('beta-feature')?.enabled).toBe(true);
  });

  it('closes when the close button is clicked', async () => {
    await renderPanel();
    await userEvent.click(screen.getByText('Configuration'));
    await userEvent.click(screen.getByLabelText('Close configuration panel'));

    expect(screen.getByText('Configuration')).toBeInTheDocument();
    expect(screen.queryByText('Runtime configuration')).not.toBeInTheDocument();
  });
});
