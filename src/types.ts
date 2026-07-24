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

export type PromptResponse =
  | { status: "submitted"; values: Record<string, ResponseValue> }
  | { status: "cancelled" };

export type ErrorCode = "CLI_USAGE" | "INVALID_REQUEST" | "PROMPT_FAILED";

export interface Result {
  status: "completed" | "failed" | "cancelled";
  values: Record<string, ResponseValue>;
  error?: { code: ErrorCode; message: string };
}
