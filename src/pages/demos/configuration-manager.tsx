import React, { useEffect, useState } from 'react';
import Layout from '@theme/Layout';

import {
  ConfigurationManager,
  ConfigurationPanel,
  ConfigurationProvider,
  FeatureFlagManager,
  useConfiguration,
  useFeatureFlag,
  useGlobalConfiguration
} from '../../components/ConfigurationManager';

function ConfigurationManagerDemoBody(): React.JSX.Element {
  const { configManager, featureFlagManager } = useGlobalConfiguration();
  const [ready, setReady] = useState(false);

  useEffect(() => {
    let cancelled = false;

    Promise.all([
      configManager.registerSchema({
        key: 'ui.max-items',
        defaultValue: 10,
        type: 'number',
        description: 'Maximum number of items shown in a list'
      }),
      configManager.registerSchema({
        key: 'ui.theme',
        defaultValue: 'blue',
        type: 'string',
        description: 'Accent color for demo UI',
        validator: (value) => ({
          isValid: ['blue', 'red', 'green'].includes(value as string),
          errors: ['blue', 'red', 'green'].includes(value as string)
            ? []
            : ["Must be one of 'blue', 'red', 'green'."]
        })
      }),
      featureFlagManager.defineFlag('beta-feature', false, {
        description: 'Gradually-rolled-out beta feature',
        rolloutPercentage: 50
      })
    ]).then(() => {
      if (!cancelled) {
        setReady(true);
      }
    });

    return () => {
      cancelled = true;
    };
  }, [configManager, featureFlagManager]);

  if (!ready) {
    return <p>Loading configuration…</p>;
  }

  return <ConfigurationManagerDemo />;
}

function ConfigurationManagerDemo(): React.JSX.Element {
  const { configManager, featureFlagManager } = useGlobalConfiguration();
  const [maxItems, setMaxItems] = useConfiguration<number>(configManager, 'ui.max-items', 10);
  const [theme, setTheme] = useConfiguration<string>(configManager, 'ui.theme', 'blue');
  const [isBetaEnabled] = useFeatureFlag(featureFlagManager, 'beta-feature');

  return (
    <div className="card shadow--md">
      <div className="card__header">
        <h3>Live configuration</h3>
      </div>
      <div className="card__body">
        <div className="margin-bottom--md">
          <label htmlFor="max-items">
            <strong>ui.max-items:</strong> {maxItems}
          </label>
          <div>
            <button
              type="button"
              className="button button--sm button--secondary margin-right--sm"
              onClick={() => setMaxItems(Math.max(0, maxItems - 1))}
            >
              -
            </button>
            <button
              type="button"
              className="button button--sm button--secondary"
              onClick={() => setMaxItems(maxItems + 1)}
            >
              +
            </button>
          </div>
        </div>

        <div className="margin-bottom--md">
          <label htmlFor="theme-select">
            <strong>ui.theme:</strong>
          </label>
          <select
            id="theme-select"
            value={theme}
            onChange={(event) => setTheme(event.target.value)}
            style={{ marginLeft: '0.5rem' }}
          >
            <option value="blue">blue</option>
            <option value="red">red</option>
            <option value="green">green</option>
          </select>
        </div>

        <div
          className={`alert ${isBetaEnabled ? 'alert--success' : 'alert--secondary'}`}
        >
          beta-feature is currently{' '}
          <strong>{isBetaEnabled ? 'ENABLED' : 'disabled'}</strong> for this
          session (50% rollout — toggle it below to override).
        </div>

        <p className="margin-top--md">
          <small style={{ color: 'var(--ifm-color-emphasis-600)' }}>
            Open the <strong>Configuration</strong> panel in the bottom-right
            corner to edit these values and flags directly.
          </small>
        </p>
      </div>
    </div>
  );
}

/**
 * Configuration Manager Demo
 *
 * Demonstrates the runtime ConfigurationManager and FeatureFlagManager: typed
 * configuration values with validation, a rollout-gated feature flag, and the
 * live admin ConfigurationPanel.
 */
export default function ConfigurationManagerDemoPage(): React.JSX.Element {
  return (
    <Layout
      title="Configuration Manager Demo"
      description="Interactive demonstration of the runtime ConfigurationManager and feature flags"
    >
      <div className="container margin-top--md margin-bottom--lg">
        <div className="row">
          <div className="col col--12">
            <header className="margin-bottom--lg">
              <div className="text--center">
                <h1 className="margin-bottom--sm">Configuration Manager</h1>
                <p className="margin-bottom--none text--secondary">
                  Runtime configuration and feature flags, with persistence and
                  a live admin panel
                </p>
              </div>
            </header>

            <main>
              <ConfigurationProvider>
                <ConfigurationManagerDemoBody />

                <div
                  style={{
                    position: 'fixed',
                    bottom: '1rem',
                    right: '1rem',
                    zIndex: 100
                  }}
                >
                  <ConfigurationPanel />
                </div>
              </ConfigurationProvider>
            </main>
          </div>
        </div>
      </div>
    </Layout>
  );
}
