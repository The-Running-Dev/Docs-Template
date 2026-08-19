import { useCallback, useEffect, useState } from 'react';

import type { ConfigurationManager } from './ConfigurationManager';
import type { FeatureFlagManager } from './FeatureFlagManager';
import type { ConfigValue } from '../../types/configuration';

/**
 * Subscribes a component to one configuration value.
 *
 * @returns `[value, setValue]`, mirroring `useState`'s shape. `setValue`
 * writes through the manager (validating and persisting), and every
 * subscriber -- not just this component -- re-renders when the value changes.
 */
export function useConfiguration<T extends ConfigValue = ConfigValue>(
  configManager: ConfigurationManager,
  key: string,
  defaultValue?: T
): [T, (value: T) => Promise<void>] {
  const [value, setValueState] = useState<T>(() => configManager.get<T>(key, defaultValue as T));

  useEffect(() => {
    setValueState(configManager.get<T>(key, defaultValue as T));

    return configManager.subscribe<T>(key, (event) => {
      setValueState(event.newValue as T);
    });
    // defaultValue is only used for the initial read; changing it should not
    // re-subscribe or override a value already set at runtime.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [configManager, key]);

  const setValue = useCallback(
    async (next: T) => {
      await configManager.set(key, next);
    },
    [configManager, key]
  );

  return [value, setValue];
}

/**
 * Subscribes a component to one feature flag's evaluated state.
 *
 * @returns `[enabled, loading]`. `loading` is true only until the flag's
 * first evaluation resolves (`isFeatureEnabled` is async), so a caller that
 * only needs the boolean -- as in `const [isEnabled] = useRuntimeFeatureFlag(...)`
 * -- can safely ignore it and treat the initial `false` as "not enabled yet".
 */
export function useRuntimeFeatureFlag(
  featureFlagManager: FeatureFlagManager,
  key: string
): [boolean, boolean] {
  const [enabled, setEnabled] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;

    const evaluate = () => {
      featureFlagManager.isFeatureEnabled(key).then((result) => {
        if (!cancelled) {
          setEnabled(result);
          setLoading(false);
        }
      });
    };

    evaluate();
    const unsubscribe = featureFlagManager.subscribe(key, evaluate);

    return () => {
      cancelled = true;
      unsubscribe();
    };
  }, [featureFlagManager, key]);

  return [enabled, loading];
}
