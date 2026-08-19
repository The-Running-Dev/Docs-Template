import { describe, expect, it } from 'vitest';

import { LocalStorageConfigurationStorage, MemoryConfigurationStorage } from '../storage';

describe('MemoryConfigurationStorage', () => {
  it('round-trips a value and clears it', async () => {
    const storage = new MemoryConfigurationStorage();
    await storage.setItem('a', '1');
    expect(await storage.getItem('a')).toBe('1');

    await storage.removeItem('a');
    expect(await storage.getItem('a')).toBeNull();
  });

  it('clear removes every stored key', async () => {
    const storage = new MemoryConfigurationStorage();
    await storage.setItem('a', '1');
    await storage.setItem('b', '2');
    await storage.clear();

    expect(await storage.getItem('a')).toBeNull();
    expect(await storage.getItem('b')).toBeNull();
  });
});

describe('LocalStorageConfigurationStorage', () => {
  it('namespaces keys so two instances do not collide', async () => {
    const first = new LocalStorageConfigurationStorage('app-one');
    const second = new LocalStorageConfigurationStorage('app-two');

    await first.setItem('shared-key', 'from-one');
    await second.setItem('shared-key', 'from-two');

    expect(await first.getItem('shared-key')).toBe('from-one');
    expect(await second.getItem('shared-key')).toBe('from-two');
  });

  it('clear only removes keys under its own namespace', async () => {
    const first = new LocalStorageConfigurationStorage('app-one');
    const second = new LocalStorageConfigurationStorage('app-two');

    await first.setItem('key', 'value');
    await second.setItem('key', 'value');
    await first.clear();

    expect(await first.getItem('key')).toBeNull();
    expect(await second.getItem('key')).toBe('value');
  });
});
