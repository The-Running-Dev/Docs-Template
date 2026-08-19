import { describe, expect, it } from 'vitest';

import { ConfigurationManager } from '../ConfigurationManager';
import { MemoryConfigurationStorage } from '../storage';

describe('ConfigurationManager', () => {
  it('returns a schema default before any value is set', async () => {
    const manager = new ConfigurationManager({ enablePersistence: false });
    await manager.registerSchema({ key: 'ui.maxItems', defaultValue: 10, type: 'number' });

    expect(manager.get('ui.maxItems')).toBe(10);
  });

  it('falls back to the caller-supplied default for an unregistered key', () => {
    const manager = new ConfigurationManager({ enablePersistence: false });
    expect(manager.get('unknown.key', 'fallback')).toBe('fallback');
  });

  it('applies a valid set and notifies subscribers', async () => {
    const manager = new ConfigurationManager({ enablePersistence: false });
    await manager.registerSchema({ key: 'ui.maxItems', defaultValue: 10, type: 'number' });

    const events: unknown[] = [];
    manager.subscribe('ui.maxItems', (event) => events.push(event));

    const result = await manager.set('ui.maxItems', 20);

    expect(result.isValid).toBe(true);
    expect(manager.get('ui.maxItems')).toBe(20);
    expect(events).toHaveLength(1);
    expect(events[0]).toMatchObject({ key: 'ui.maxItems', oldValue: 10, newValue: 20 });
  });

  it('rejects a set that fails type validation in strict mode', async () => {
    const manager = new ConfigurationManager({ enablePersistence: false, validationMode: 'strict' });
    await manager.registerSchema({ key: 'ui.theme', defaultValue: 'blue', type: 'string' });

    const result = await manager.set('ui.theme', 42 as unknown as string);

    expect(result.isValid).toBe(false);
    expect(manager.get('ui.theme')).toBe('blue');
  });

  it('applies a set that fails validation in lenient mode', async () => {
    const manager = new ConfigurationManager({ enablePersistence: false, validationMode: 'lenient' });
    await manager.registerSchema({ key: 'ui.theme', defaultValue: 'blue', type: 'string' });

    const result = await manager.set('ui.theme', 42 as unknown as string);

    expect(result.isValid).toBe(false);
    expect(manager.get('ui.theme')).toBe(42);
  });

  it('runs a custom validator and rejects on failure', async () => {
    const manager = new ConfigurationManager({ enablePersistence: false });
    await manager.registerSchema({
      key: 'ui.theme',
      defaultValue: 'blue',
      type: 'string',
      validator: (value) => ({
        isValid: ['blue', 'red', 'green'].includes(value as string),
        errors: value === 'blue' || value === 'red' || value === 'green' ? [] : ['not an allowed color']
      })
    });

    const result = await manager.set('ui.theme', 'purple');

    expect(result.isValid).toBe(false);
    expect(manager.get('ui.theme')).toBe('blue');
  });

  it('persists a set and restores it on schema registration against the same storage', async () => {
    const storage = new MemoryConfigurationStorage();
    const first = new ConfigurationManager({ storage, namespace: 'app' });
    await first.registerSchema({ key: 'ui.maxItems', defaultValue: 10, type: 'number' });
    await first.set('ui.maxItems', 25);

    const second = new ConfigurationManager({ storage, namespace: 'app' });
    await second.registerSchema({ key: 'ui.maxItems', defaultValue: 10, type: 'number' });

    expect(second.get('ui.maxItems')).toBe(25);
  });

  it('resets a key back to its schema default and clears persisted storage', async () => {
    const storage = new MemoryConfigurationStorage();
    const manager = new ConfigurationManager({ storage, namespace: 'app' });
    await manager.registerSchema({ key: 'ui.maxItems', defaultValue: 10, type: 'number' });
    await manager.set('ui.maxItems', 25);

    await manager.reset('ui.maxItems');

    expect(manager.get('ui.maxItems')).toBe(10);
    expect(await storage.getItem('app:ui.maxItems')).toBeNull();
  });

  it('serializes concurrent sets to the same key rather than interleaving', async () => {
    const manager = new ConfigurationManager({ enablePersistence: false });
    await manager.registerSchema({ key: 'counter', defaultValue: 0, type: 'number' });

    const seenOldValues: unknown[] = [];
    manager.subscribe('counter', (event) => seenOldValues.push(event.oldValue));

    await Promise.all([
      manager.set('counter', 1),
      manager.set('counter', 2),
      manager.set('counter', 3)
    ]);

    // Each write must have observed the previous write's result as its
    // oldValue -- an interleaved read-modify-write would duplicate 0.
    expect(new Set(seenOldValues).size).toBe(3);
  });

  it('unsubscribes a callback', async () => {
    const manager = new ConfigurationManager({ enablePersistence: false });
    await manager.registerSchema({ key: 'ui.maxItems', defaultValue: 10, type: 'number' });

    const events: unknown[] = [];
    const unsubscribe = manager.subscribe('ui.maxItems', (event) => events.push(event));
    unsubscribe();

    await manager.set('ui.maxItems', 30);

    expect(events).toHaveLength(0);
  });
});
