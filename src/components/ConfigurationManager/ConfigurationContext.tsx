import React, { createContext, useContext, useMemo } from 'react';

import { ConfigurationManager } from './ConfigurationManager';
import { FeatureFlagManager, FeatureFlagManagerOptions } from './FeatureFlagManager';
import type { ConfigurationManagerOptions } from '../../types/configuration';

export interface GlobalConfigurationContextValue {
  configManager: ConfigurationManager;
  featureFlagManager: FeatureFlagManager;
}

const GlobalConfigurationContext = createContext<GlobalConfigurationContextValue | null>(null);

export interface ConfigurationProviderProps {
  children: React.ReactNode;
  /** Reuse an existing manager instead of letting the provider create one. */
  configManager?: ConfigurationManager;
  featureFlagManager?: FeatureFlagManager;
  /** Options for a manager the provider creates itself; ignored if the instance above is passed. */
  configOptions?: ConfigurationManagerOptions;
  featureFlagOptions?: FeatureFlagManagerOptions;
}

/**
 * Provides a `ConfigurationManager` and `FeatureFlagManager` to the component
 * tree beneath it. Managers are created once, on mount -- a caller that needs
 * a different manager later should remount the provider (e.g. with a
 * different `key`) rather than expect props to swap the instance in place,
 * since every subscription elsewhere in the tree is tied to the original.
 */
export function ConfigurationProvider({
  children,
  configManager,
  featureFlagManager,
  configOptions,
  featureFlagOptions
}: ConfigurationProviderProps): React.ReactElement {
  const value = useMemo<GlobalConfigurationContextValue>(
    () => ({
      configManager: configManager ?? new ConfigurationManager(configOptions),
      featureFlagManager: featureFlagManager ?? new FeatureFlagManager(featureFlagOptions)
    }),
    // Deliberately empty: see the doc comment above.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    []
  );

  return (
    <GlobalConfigurationContext.Provider value={value}>
      {children}
    </GlobalConfigurationContext.Provider>
  );
}

export function useGlobalConfiguration(): GlobalConfigurationContextValue {
  const context = useContext(GlobalConfigurationContext);
  if (!context) {
    throw new Error('useGlobalConfiguration must be used within a ConfigurationProvider.');
  }
  return context;
}
