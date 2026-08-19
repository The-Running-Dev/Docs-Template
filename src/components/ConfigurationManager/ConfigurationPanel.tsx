import React, { useEffect, useState } from 'react';

import { useGlobalConfiguration } from './ConfigurationContext';
import type { ConfigValue, ConfigurationSchema, FeatureFlag } from '../../types/configuration';

import './ConfigurationPanel.css';

export interface ConfigurationPanelProps {
  className?: string;
  /** How often (ms) the panel re-reads manager state for values changed outside a subscription. Default 1000. */
  refreshIntervalMs?: number;
}

/**
 * Runtime configuration and feature-flag admin panel.
 *
 * Reads registered schemas and flags from the managers provided by
 * `ConfigurationProvider` and lets a developer or admin inspect and edit them
 * live, without a rebuild. Collapsed to a toggle button by default so it can
 * be mounted alongside the app without taking up space.
 */
export function ConfigurationPanel({
  className,
  refreshIntervalMs = 1000
}: ConfigurationPanelProps): React.ReactElement {
  const { configManager, featureFlagManager } = useGlobalConfiguration();
  const [schemas, setSchemas] = useState<ConfigurationSchema<any>[]>(() => configManager.getSchemas());
  const [flags, setFlags] = useState<FeatureFlag[]>(() => featureFlagManager.getFlags());
  const [isOpen, setIsOpen] = useState(false);

  useEffect(() => {
    if (!isOpen) {
      return undefined;
    }

    const interval = setInterval(() => {
      setSchemas(configManager.getSchemas());
      setFlags(featureFlagManager.getFlags());
    }, refreshIntervalMs);

    return () => clearInterval(interval);
  }, [configManager, featureFlagManager, isOpen, refreshIntervalMs]);

  if (!isOpen) {
    return (
      <button
        type="button"
        className={['config-panel__toggle', className].filter(Boolean).join(' ')}
        onClick={() => setIsOpen(true)}
      >
        Configuration
      </button>
    );
  }

  return (
    <div className={['config-panel', className].filter(Boolean).join(' ')}>
      <div className="config-panel__header">
        <span>Runtime configuration</span>
        <button type="button" onClick={() => setIsOpen(false)} aria-label="Close configuration panel">
          &times;
        </button>
      </div>

      <section className="config-panel__section">
        <h3>Configuration values</h3>
        {schemas.length === 0 && (
          <p className="config-panel__empty">No configuration values registered.</p>
        )}
        {schemas.map((schema) => (
          <ConfigurationValueRow
            key={schema.key}
            schema={schema}
            value={configManager.get(schema.key, schema.defaultValue)}
            onChange={(value) => {
              void configManager.set(schema.key, value);
            }}
          />
        ))}
      </section>

      <section className="config-panel__section">
        <h3>Feature flags</h3>
        {flags.length === 0 && <p className="config-panel__empty">No feature flags defined.</p>}
        {flags.map((flag) => (
          <div className="config-panel__row" key={flag.key}>
            <label htmlFor={`config-panel-flag-${flag.key}`} title={flag.description}>
              {flag.key}
            </label>
            <input
              id={`config-panel-flag-${flag.key}`}
              type="checkbox"
              checked={flag.enabled}
              onChange={(event) => {
                void featureFlagManager.setFlagEnabled(flag.key, event.target.checked);
              }}
            />
          </div>
        ))}
      </section>
    </div>
  );
}

interface ConfigurationValueRowProps {
  schema: ConfigurationSchema<any>;
  value: ConfigValue;
  onChange: (value: ConfigValue) => void;
}

function ConfigurationValueRow({
  schema,
  value,
  onChange
}: ConfigurationValueRowProps): React.ReactElement {
  return (
    <div className="config-panel__row">
      <label htmlFor={`config-panel-value-${schema.key}`} title={schema.description}>
        {schema.key}
      </label>
      {schema.type === 'boolean' ? (
        <input
          id={`config-panel-value-${schema.key}`}
          type="checkbox"
          checked={Boolean(value)}
          onChange={(event) => onChange(event.target.checked)}
        />
      ) : (
        <input
          id={`config-panel-value-${schema.key}`}
          type={schema.type === 'number' ? 'number' : 'text'}
          value={value === null || value === undefined ? '' : String(value)}
          onChange={(event) =>
            onChange(schema.type === 'number' ? Number(event.target.value) : event.target.value)
          }
        />
      )}
    </div>
  );
}

export default ConfigurationPanel;
