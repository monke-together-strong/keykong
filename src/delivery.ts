import { DeadlineExpired, type Deadline } from "./deadline";
import type { TargetIdentity } from "./target";
import type {
  Delivery,
  DeliveryWorkerRequest,
  ResponseValue,
} from "./types";

interface WorkerResponse {
  failed?: string[];
  error?: true;
}

export async function deliver(
  deliveries: Delivery[],
  values: Record<string, ResponseValue>,
  targets: Map<string, TargetIdentity>,
  deadline: Deadline,
): Promise<string[]> {
  if (deliveries.length === 0) return [];

  const worker = new Worker("./delivery-worker.ts", { ref: true });
  const closed = new Promise<void>((resolve) => {
    worker.addEventListener("close", () => resolve(), { once: true });
  });
  const response = new Promise<WorkerResponse>((resolve, reject) => {
    let received = false;
    worker.addEventListener("message", (event: MessageEvent<WorkerResponse>) => {
      received = true;
      worker.terminate();
      resolve(event.data);
    }, { once: true });
    worker.addEventListener("error", (event) => {
      worker.terminate();
      reject(event.error);
    }, { once: true });
    worker.addEventListener("close", () => {
      if (!received) reject(new Error("delivery worker closed"));
    }, { once: true });
  });
  const request: DeliveryWorkerRequest = {
    deliveries,
    values,
    targets: [...targets].map(([id, identity]) => [
      id,
      { dev: String(identity.dev), ino: String(identity.ino) },
    ]),
  };
  worker.postMessage(request);

  try {
    const [result] = await deadline.run(
      Promise.all([response, closed]),
      () => worker.terminate(),
    );
    if (
      result.error ||
      !Array.isArray(result.failed) ||
      result.failed.some((id) => typeof id !== "string") ||
      result.failed.some(
        (id) => !deliveries.some((delivery) => delivery.id === id),
      )
    ) {
      return deliveries.map(({ id }) => id);
    }
    return result.failed;
  } catch (error) {
    worker.terminate();
    await closed;
    if (error instanceof DeadlineExpired) throw error;
    return deliveries.map(({ id }) => id);
  }
}
