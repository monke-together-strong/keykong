import { expect, test } from "bun:test";
import { Deadline, DeadlineExpired } from "../src/deadline";

test("expiry wins when cancellation completes the pending work", async () => {
  let finish!: (value: string) => void;
  const work = new Promise<string>((resolve) => {
    finish = resolve;
  });

  await expect(
    new Deadline(10).run(work, () => finish("cancelled")),
  ).rejects.toBeInstanceOf(DeadlineExpired);
});
