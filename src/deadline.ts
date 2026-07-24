export class DeadlineExpired extends Error {}

export class Deadline {
  readonly expiresAt: number;

  constructor(timeoutMS: number) {
    this.expiresAt = performance.now() + timeoutMS;
  }

  remaining(): number {
    return Math.max(0, this.expiresAt - performance.now());
  }

  assertActive() {
    if (this.remaining() === 0) throw new DeadlineExpired();
  }

  async run<T>(work: Promise<T>, onExpire?: () => void): Promise<T> {
    const remaining = this.remaining();
    if (remaining === 0) {
      onExpire?.();
      throw new DeadlineExpired();
    }

    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      return await Promise.race([
        work,
        new Promise<never>((_, reject) => {
          timer = setTimeout(() => {
            onExpire?.();
            reject(new DeadlineExpired());
          }, remaining);
        }),
      ]);
    } finally {
      if (timer) clearTimeout(timer);
    }
  }
}
