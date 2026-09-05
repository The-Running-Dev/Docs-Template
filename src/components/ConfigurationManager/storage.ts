import type { ConfigurationStorage } from '../../types/configuration';

/**
 * In-memory configuration storage.
 *
 * The default backend: nothing persists across a reload, which is exactly
 * right for tests and for a manager that only needs runtime overrides for
 * the lifetime of the page.
 */
export class MemoryConfigurationStorage implements ConfigurationStorage {
  private store = new Map<string, string>();

  async getItem(key: string): Promise<string | null> {
    return this.store.has(key) ? (this.store.get(key) as string) : null;
  }

  async setItem(key: string, value: string): Promise<void> {
    this.store.set(key, value);
  }

  async removeItem(key: string): Promise<void> {
    this.store.delete(key);
  }

  async clear(): Promise<void> {
    this.store.clear();
  }
}

/**
 * Browser localStorage-backed configuration storage.
 *
 * Guards every call on `window.localStorage` being available so importing
 * this module never breaks a server-side render; it just behaves as if
 * nothing were ever persisted until it runs in a browser.
 */
export class LocalStorageConfigurationStorage implements ConfigurationStorage {
  private readonly namespace: string;

  constructor(namespace: string = 'app-config') {
    this.namespace = namespace;
  }

  private key(key: string): string {
    return `${this.namespace}:${key}`;
  }

  private get available(): boolean {
    return typeof window !== 'undefined' && !!window.localStorage;
  }

  async getItem(key: string): Promise<string | null> {
    if (!this.available) {
      return null;
    }
    return window.localStorage.getItem(this.key(key));
  }

  async setItem(key: string, value: string): Promise<void> {
    if (!this.available) {
      return;
    }
    window.localStorage.setItem(this.key(key), value);
  }

  async removeItem(key: string): Promise<void> {
    if (!this.available) {
      return;
    }
    window.localStorage.removeItem(this.key(key));
  }

  async clear(): Promise<void> {
    if (!this.available) {
      return;
    }
    const prefix = `${this.namespace}:`;
    const keysToRemove: string[] = [];
    for (let i = 0; i < window.localStorage.length; i++) {
      const storedKey = window.localStorage.key(i);
      if (storedKey && storedKey.startsWith(prefix)) {
        keysToRemove.push(storedKey);
      }
    }
    keysToRemove.forEach((storedKey) => window.localStorage.removeItem(storedKey));
  }
}
