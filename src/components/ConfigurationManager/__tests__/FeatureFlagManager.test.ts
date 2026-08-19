import { describe, expect, it } from 'vitest';

import { FeatureFlagManager } from '../FeatureFlagManager';
import { MemoryConfigurationStorage } from '../storage';

describe('FeatureFlagManager', () => {
  it('evaluates an undefined flag as disabled', async () => {
    const manager = new FeatureFlagManager({ enablePersistence: false });
    expect(await manager.isFeatureEnabled('never-defined')).toBe(false);
  });

  it('evaluates a defined, enabled flag with no conditions as enabled', async () => {
    const manager = new FeatureFlagManager({ enablePersistence: false });
    await manager.defineFlag('simple-flag', true);

    expect(await manager.isFeatureEnabled('simple-flag')).toBe(true);
  });

  it('evaluates a defined but disabled flag as disabled', async () => {
    const manager = new FeatureFlagManager({ enablePersistence: false });
    await manager.defineFlag('off-flag', false);

    expect(await manager.isFeatureEnabled('off-flag')).toBe(false);
  });

  it('requires every declared condition to match the evaluation context', async () => {
    const manager = new FeatureFlagManager({ enablePersistence: false });
    await manager.defineFlag('beta-feature', true, {
      conditions: { userTier: 'premium' }
    });

    expect(await manager.isFeatureEnabled('beta-feature')).toBe(false);

    manager.setEvaluationContext('userTier', 'premium');
    expect(await manager.isFeatureEnabled('beta-feature')).toBe(true);

    manager.setEvaluationContext('userTier', 'free');
    expect(await manager.isFeatureEnabled('beta-feature')).toBe(false);
  });

  it('gates a rollout-percentage flag deterministically for the same subject', async () => {
    const manager = new FeatureFlagManager({ enablePersistence: false });
    await manager.defineFlag('rollout-flag', true, { rolloutPercentage: 100 });
    await manager.defineFlag('never-rolled-out', true, { rolloutPercentage: 0 });

    manager.setEvaluationContext('userId', 'user-123');

    expect(await manager.isFeatureEnabled('rollout-flag')).toBe(true);
    expect(await manager.isFeatureEnabled('never-rolled-out')).toBe(false);

    // Same subject, evaluated twice, must land in the same bucket both times.
    const first = await manager.isFeatureEnabled('rollout-flag');
    const second = await manager.isFeatureEnabled('rollout-flag');
    expect(first).toBe(second);
  });

  it('persists a runtime toggle and a later defineFlag call honors it over its own default', async () => {
    const storage = new MemoryConfigurationStorage();
    const manager = new FeatureFlagManager({ storage, namespace: 'flags' });
    await manager.defineFlag('toggle-me', false);
    await manager.setFlagEnabled('toggle-me', true);

    const reloaded = new FeatureFlagManager({ storage, namespace: 'flags' });
    await reloaded.defineFlag('toggle-me', false);

    expect(await reloaded.isFeatureEnabled('toggle-me')).toBe(true);
  });

  it('notifies subscribers on defineFlag and setFlagEnabled', async () => {
    const manager = new FeatureFlagManager({ enablePersistence: false });
    const seen: boolean[] = [];
    manager.subscribe('watched', (flag) => seen.push(flag.enabled));

    await manager.defineFlag('watched', false);
    await manager.setFlagEnabled('watched', true);

    expect(seen).toEqual([false, true]);
  });

  it('lists defined flags', async () => {
    const manager = new FeatureFlagManager({ enablePersistence: false });
    await manager.defineFlag('a', true);
    await manager.defineFlag('b', false);

    expect(manager.getFlags().map((f) => f.key).sort()).toEqual(['a', 'b']);
  });
});
