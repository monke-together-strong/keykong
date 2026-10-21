import { expect, test } from "bun:test";
import { form, page } from "../src/web-prompt-page";

test("request metadata stays text and only the nonce-authorized script can run", async () => {
  const hostile = `"><script>alert('injected')</script><img src=x onerror=alert(1)>`;
  const response = page(200, form({
    id: "escaping",
    title: hostile,
    fields: [
      { id: "submit", label: hostile, type: "secret" },
      { id: "region", label: hostile, type: "select", options: [{ label: hostile, value: hostile }] },
      { id: "features", label: hostile, type: "multi_select", options: [{ label: hostile, value: hostile }] },
    ],
    deliveries: [{ id: "delivery", path: hostile, operation: "append", template: hostile }],
  }));
  const scripts: string[] = [];
  const imageSources: string[] = [];
  const options: string[] = [];
  const html = await new HTMLRewriter()
    .on("script", { element: (element) => { scripts.push(element.getAttribute("nonce") ?? ""); } })
    .on("img", { element: (element) => { imageSources.push(element.getAttribute("src") ?? ""); } })
    .on("option[value]:not([disabled])", { element: (element) => { options.push(element.getAttribute("value") ?? ""); } })
    .transform(await response.clone().text());

  expect(scripts).toHaveLength(1);
  expect(scripts[0]).toMatch(/^[\w+/]{22}==$/);
  expect(response.headers.get("Content-Security-Policy")).toContain(`script-src 'nonce-${scripts[0]}'`);
  expect(response.headers.get("Cache-Control")).toBe("no-store");
  expect(imageSources).toHaveLength(1);
  const image = Buffer.from(imageSources[0]!.split(",")[1]!, "base64");
  expect(image.subarray(1, 4).toString()).toBe("PNG");
  expect(image.readUInt32BE(16)).toBe(176);
  expect(options).toEqual([Bun.escapeHTML(hostile)]);
  expect(html).toContain(Bun.escapeHTML(hostile));
  expect(html).not.toContain(hostile);
});
