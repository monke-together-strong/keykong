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

export interface AppendDelivery {
  id: string;
  path: string;
  operation: "append";
  template: string;
}

export interface InsertLineDelivery {
  id: string;
  path: string;
  operation: "insert_line";
  line: number;
  template: string;
}

export interface SetEnvDelivery {
  id: string;
  path: string;
  operation: "set_env";
  key: string;
  field: string;
}

export type Delivery =
  | AppendDelivery
  | InsertLineDelivery
  | SetEnvDelivery;

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
  deliveries: Array<
    | { path: string; operation: "append" }
    | { path: string; operation: "insert_line"; line: number }
    | {
      path: string;
      operation: "set_env";
      key: string;
      field: string;
    }
  >;
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
