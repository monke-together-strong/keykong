import { ExpiredError } from "./errors";

export class Deadline {
  private readonly expiresAt: number;

  constructor(timeoutSeconds: number) {
    this.expiresAt = performance.now() + timeoutSeconds * 1_000;
  }

  get remainingMilliseconds() {
    return Math.max(0, this.expiresAt - performance.now());
  }

  check() {
    if (this.remainingMilliseconds === 0) throw new ExpiredError();
  }

  async race<T>(operation: Promise<T>, onExpire?: () => void): Promise<T> {
    this.check();
    let timer: ReturnType<typeof setTimeout> | undefined;
    const expired = new Promise<never>((_, reject) => {
      timer = setTimeout(() => {
        onExpire?.();
        reject(new ExpiredError());
      }, this.remainingMilliseconds);
    });
    try {
      return await Promise.race([operation, expired]);
    } finally {
      clearTimeout(timer);
    }
  }
}
