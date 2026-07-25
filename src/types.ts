export type FieldType = "text" | "secret" | "select" | "multi_select";
export type ResponseValue = string | string[];

export interface Option {
  label: string;
  value: string;
}

export interface Field {
  id: string;
  label: string;
  type: FieldType;
  options?: Option[];
}

export interface Delivery {
  id: string;
  path: string;
  operation: "append" | "insert_line";
  line?: number;
  template: string;
}

export interface Request {
  schemaVersion: 1;
  id: string;
  title: string;
  fields: Field[];
  deliveries: Delivery[];
}

export interface PromptRequest {
  title: string;
  fields: Field[];
  deliveries: Array<Pick<Delivery, "path" | "operation" | "line">>;
}

export interface DeliveryWorkerRequest {
  deliveries: Delivery[];
  values: Record<string, ResponseValue>;
  targets: Array<[string, { dev: string; ino: string }]>;
}

export type PromptResponse =
  | { status: "submitted"; values: Record<string, ResponseValue> }
  | { status: "cancelled" };

export type ErrorCode =
  | "CLI_USAGE"
  | "INVALID_REQUEST"
  | "PROMPT_FAILED"
  | "DELIVERY_FAILED"
  | "INTERNAL_FAILURE";

export interface Result {
  status: "completed" | "partial" | "failed" | "cancelled" | "expired";
  values: Record<string, ResponseValue>;
  failedDeliveries?: string[];
  error?: { code: ErrorCode; message: string };
}
