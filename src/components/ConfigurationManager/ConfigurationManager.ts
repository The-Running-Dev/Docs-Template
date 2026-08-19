import { Mutex } from './Mutex';
import { MemoryConfigurationStorage } from './storage';
import type {
  ConfigValue,
  ConfigurationChangeEvent,
  ConfigurationManagerOptions,
  ConfigurationSchema,
  ConfigurationState,
  ConfigurationStorage,
  ConfigurationSubscription,
  ValidationResult
} from '../../types/configuration';

/**
 * Runtime configuration manager.
 *
 * Complements the build-time `FeaturesConfig` system (`src/config/FeaturesConfig`)
 * -- that system bakes boolean flags into the site at build time; this one
 * manages typed, validated configuration values that change while the app is
 * running, with optional persistence and change notifications.
 *
 * Every mutating operation runs inside a mutex so a schema registration and a
 * concurrent `set` for the same key can never interleave and leave a stale
 * read, an unpersisted write, or a missed notification.
 */
export class ConfigurationManager {
  private schemas = new Map<string, ConfigurationSchema<any>>();
  private values = new Map<string, ConfigValue>();
  private subscriptions = new Map<string, Set<ConfigurationSubscription<any>>>();
  private readonly mutex = new Mutex();
  private readonly storage: ConfigurationStorage;
  private readonly enablePersistence: boolean;
  private readonly enableLogging: boolean;
  private readonly validationMode: 'strict' | 'lenient';
  private readonly namespace: string;

  constructor(options: ConfigurationManagerOptions = {}) {
    this.storage = options.storage ?? new MemoryConfigurationStorage();
    this.enablePersistence = options.enablePersistence ?? true;
    this.enableLogging = options.enableLogging ?? false;
    this.validationMode = options.validationMode ?? 'strict';
    this.namespace = options.namespace ?? 'default';
  }

  private storageKey(key: string): string {
    return `${this.namespace}:${key}`;
  }

  private log(...args: unknown[]): void {
    if (this.enableLogging) {
      console.log('[ConfigurationManager]', ...args);
    }
  }

  /**
   * Registers a schema and seeds its value: from persisted storage if present,
   * otherwise the schema's default. A key that already has a value (a `set`
   * that ran before its schema was registered) is left alone.
   */
  async registerSchema<T extends ConfigValue = ConfigValue>(
    schema: ConfigurationSchema<T>
  ): Promise<void> {
    return this.mutex.runExclusive(async () => {
      this.schemas.set(schema.key, schema);

      if (this.values.has(schema.key)) {
        return;
      }

      let initial: ConfigValue = schema.defaultValue;

      if (this.enablePersistence) {
        const stored = await this.storage.getItem(this.storageKey(schema.key));
        if (stored !== null) {
          try {
            initial = JSON.parse(stored);
          } catch {
            this.log(`Failed to parse stored value for '${schema.key}'; using default.`);
          }
        }
      }

      this.values.set(schema.key, initial);
    });
  }

  private validate(
    schema: ConfigurationSchema<any> | undefined,
    value: ConfigValue
  ): ValidationResult {
    if (!schema) {
      return { isValid: true, errors: [] };
    }

    if (schema.required && (value === null || value === undefined)) {
      return { isValid: false, errors: [`'${schema.key}' is required.`] };
    }

    if (
      value !== null &&
      value !== undefined &&
      schema.type !== 'object' &&
      typeof value !== schema.type
    ) {
      return {
        isValid: false,
        errors: [`'${schema.key}' must be of type '${schema.type}', got '${typeof value}'.`]
      };
    }

    if (schema.validator) {
      return schema.validator(value);
    }

    return { isValid: true, errors: [] };
  }

  /** Reads a value synchronously: the registered/default value, or `fallback` for an unknown key. */
  get<T extends ConfigValue = ConfigValue>(key: string, fallback?: T): T {
    if (this.values.has(key)) {
      return this.values.get(key) as T;
    }

    const schema = this.schemas.get(key);
    if (schema) {
      return schema.defaultValue as T;
    }

    return fallback as T;
  }

  /**
   * Validates, applies, persists, and notifies subscribers of a new value.
   * Under -validationMode 'strict' (the default) an invalid value is rejected
   * -- the returned ValidationResult reports why, and nothing changes.
   */
  async set<T extends ConfigValue = ConfigValue>(
    key: string,
    value: T,
    source: ConfigurationChangeEvent['source'] = 'user'
  ): Promise<ValidationResult> {
    return this.mutex.runExclusive(async () => {
      const schema = this.schemas.get(key);
      const validation = this.validate(schema, value);

      if (!validation.isValid && this.validationMode === 'strict') {
        return validation;
      }

      const oldValue = this.values.has(key)
        ? (this.values.get(key) as ConfigValue)
        : (schema?.defaultValue ?? null);

      this.values.set(key, value);

      if (this.enablePersistence) {
        await this.storage.setItem(this.storageKey(key), JSON.stringify(value));
      }

      this.notify(key, {
        key,
        oldValue,
        newValue: value,
        timestamp: new Date(),
        source
      });

      return validation;
    });
  }

  /** Reverts a key to its schema default (or `null` for an unregistered key) and removes its persisted value. */
  async reset(key: string): Promise<void> {
    return this.mutex.runExclusive(async () => {
      const schema = this.schemas.get(key);
      const oldValue = this.values.has(key) ? (this.values.get(key) as ConfigValue) : null;
      const value = schema ? schema.defaultValue : null;

      this.values.set(key, value);

      if (this.enablePersistence) {
        await this.storage.removeItem(this.storageKey(key));
      }

      this.notify(key, {
        key,
        oldValue,
        newValue: value,
        timestamp: new Date(),
        source: 'system'
      });
    });
  }

  subscribe<T extends ConfigValue = ConfigValue>(
    key: string,
    callback: ConfigurationSubscription<T>
  ): () => void {
    if (!this.subscriptions.has(key)) {
      this.subscriptions.set(key, new Set());
    }
    this.subscriptions.get(key)!.add(callback as ConfigurationSubscription<any>);

    return () => {
      this.subscriptions.get(key)?.delete(callback as ConfigurationSubscription<any>);
    };
  }

  private notify(key: string, event: ConfigurationChangeEvent): void {
    this.subscriptions.get(key)?.forEach((callback) => callback(event));
  }

  getSchemas(): ConfigurationSchema<any>[] {
    return Array.from(this.schemas.values());
  }

  getState(): ConfigurationState {
    return {
      values: Object.fromEntries(this.values),
      schemas: Object.fromEntries(this.schemas),
      lastModified: new Date(),
      version: '1.0.0'
    };
  }
}

export default ConfigurationManager;
