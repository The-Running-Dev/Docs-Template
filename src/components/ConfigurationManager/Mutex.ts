/**
 * Minimal async mutex.
 *
 * JavaScript is single-threaded, but an async get/persist/notify sequence can
 * still interleave with another call to the same key across an `await`. This
 * serializes runExclusive calls into a queue so a manager's read-modify-write
 * (validate, apply, persist, notify) is never split by a concurrent call.
 */
export class Mutex {
  private queue: Promise<void> = Promise.resolve();

  async runExclusive<T>(fn: () => Promise<T> | T): Promise<T> {
    const previous = this.queue;
    let release: () => void = () => {};
    this.queue = new Promise<void>((resolve) => {
      release = resolve;
    });

    await previous;
    try {
      return await fn();
    } finally {
      release();
    }
  }
}

export default Mutex;
