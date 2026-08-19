import { Mutex } from './Mutex';
import { MemoryConfigurationStorage } from './storage';
import type { ConfigValue, ConfigurationStorage, FeatureFlag } from '../../types/configuration';

export interface FeatureFlagManagerOptions {
  storage?: ConfigurationStorage;
  enablePersistence?: boolean;
  namespace?: string;
}

export interface FeatureFlagDefinitionOptions {
  description?: string;
  rolloutPercentage?: number;
  conditions?: Record<string, ConfigValue>;
}

type FeatureFlagSubscription = (flag: FeatureFlag) => void;

/**
 * Deterministic 0-99 bucket for a string. Used for rollout percentage so the
 * same evaluation subject always lands in the same bucket for a given flag,
 * rather than flapping between enabled/disabled on every call.
 */
function hashToBucket(input: string): number {
  let hash = 0;
  for (let i = 0; i < input.length; i++) {
    hash = (hash << 5) - hash + input.charCodeAt(i);
    hash |= 0;
  }
  return Math.abs(hash) % 100;
}

/**
 * Runtime feature-flag manager: rollout percentages, evaluation-context
 * conditions, persistence, and change subscriptions. Distinct from the
 * static, build-time `FeaturesConfig` system (`src/config/FeaturesConfig`) --
 * this one is for flags that can be toggled or gradually rolled out while
 * the app is running, without a rebuild.
 */
export class FeatureFlagManager {
  private flags = new Map<string, FeatureFlag>();
  private evaluationContext: Record<string, ConfigValue> = {};
  private subscriptions = new Map<string, Set<FeatureFlagSubscription>>();
  private readonly mutex = new Mutex();
  private readonly storage: ConfigurationStorage;
  private readonly enablePersistence: boolean;
  private readonly namespace: string;

  constructor(options: FeatureFlagManagerOptions = {}) {
    this.storage = options.storage ?? new MemoryConfigurationStorage();
    this.enablePersistence = options.enablePersistence ?? true;
    this.namespace = options.namespace ?? 'feature-flags';
  }

  private storageKey(key: string): string {
    return `${this.namespace}:${key}`;
  }

  /**
   * Defines a flag with its default enabled state. A persisted override (a
   * prior `setFlagEnabled` call) takes precedence over `enabled` so a user's
   * runtime toggle survives a reload even though the code still defines the
   * same default.
   */
  async defineFlag(
    key: string,
    enabled: boolean,
    options: FeatureFlagDefinitionOptions = {}
  ): Promise<void> {
    return this.mutex.runExclusive(async () => {
      let resolvedEnabled = enabled;

      if (this.enablePersistence) {
        const stored = await this.storage.getItem(this.storageKey(key));
        if (stored !== null) {
          try {
            resolvedEnabled = JSON.parse(stored);
          } catch {
            // Unparsable stored value: fall back to the caller's default.
          }
        }
      }

      const flag: FeatureFlag = {
        key,
        enabled: resolvedEnabled,
        description: options.description,
        rolloutPercentage: options.rolloutPercentage,
        conditions: options.conditions
      };

      this.flags.set(key, flag);
      this.notify(key, flag);
    });
  }

  setEvaluationContext(key: string, value: ConfigValue): void {
    this.evaluationContext = { ...this.evaluationContext, [key]: value };
  }

  getEvaluationContext(): Record<string, ConfigValue> {
    return { ...this.evaluationContext };
  }

  /**
   * Evaluates a flag: undefined or disabled flags are false; every declared
   * condition must match the current evaluation context; and a rollout
   * percentage, when set, gates the remainder by a deterministic hash of the
   * evaluation subject (userId, falling back to userTier).
   */
  async isFeatureEnabled(key: string): Promise<boolean> {
    const flag = this.flags.get(key);
    if (!flag || !flag.enabled) {
      return false;
    }

    if (flag.conditions) {
      for (const [conditionKey, expected] of Object.entries(flag.conditions)) {
        if (this.evaluationContext[conditionKey] !== expected) {
          return false;
        }
      }
    }

    if (typeof flag.rolloutPercentage === 'number') {
      const subject = String(this.evaluationContext.userId ?? this.evaluationContext.userTier ?? '');
      return hashToBucket(`${key}:${subject}`) < flag.rolloutPercentage;
    }

    return true;
  }

  async setFlagEnabled(key: string, enabled: boolean): Promise<void> {
    return this.mutex.runExclusive(async () => {
      const existing = this.flags.get(key);
      const flag: FeatureFlag = existing ? { ...existing, enabled } : { key, enabled };
      this.flags.set(key, flag);

      if (this.enablePersistence) {
        await this.storage.setItem(this.storageKey(key), JSON.stringify(enabled));
      }

      this.notify(key, flag);
    });
  }

  getFlag(key: string): FeatureFlag | undefined {
    return this.flags.get(key);
  }

  getFlags(): FeatureFlag[] {
    return Array.from(this.flags.values());
  }

  subscribe(key: string, callback: FeatureFlagSubscription): () => void {
    if (!this.subscriptions.has(key)) {
      this.subscriptions.set(key, new Set());
    }
    this.subscriptions.get(key)!.add(callback);

    return () => {
      this.subscriptions.get(key)?.delete(callback);
    };
  }

  private notify(key: string, flag: FeatureFlag): void {
    this.subscriptions.get(key)?.forEach((callback) => callback(flag));
  }
}

export default FeatureFlagManager;
