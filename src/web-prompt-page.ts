import { randomBytes } from "node:crypto";
import emblem from "../assets/keykong-prompt-emblem.png" with { type: "file" };
import type { Delivery, Request } from "./types";

const emblemURL = `data:image/png;base64,${Buffer.from(
  await Bun.file(emblem).arrayBuffer(),
).toString("base64")}`;
const escape = Bun.escapeHTML;

// Bootstrap Icons "shield-lock-fill", MIT licensed; also used by the native prompt.
// https://icons.getbootstrap.com/icons/shield-lock-fill/
const shield = `<svg viewBox="-2.2857 -2.2857 20.5714 20.5714" aria-hidden="true"><path fill="currentColor" fill-rule="evenodd" d="M8 0c-.69 0-1.843.265-2.928.56-1.11.3-2.229.655-2.887.87a1.54 1.54 0 0 0-1.044 1.262c-.596 4.477.787 7.795 2.465 9.99a11.8 11.8 0 0 0 2.517 2.453c.386.273.744.482 1.048.625.28.132.581.24.829.24s.548-.108.829-.24a7 7 0 0 0 1.048-.625 11.8 11.8 0 0 0 2.517-2.453c1.678-2.195 3.061-5.513 2.465-9.99a1.54 1.54 0 0 0-1.044-1.263 63 63 0 0 0-2.887-.87C9.843.266 8.69 0 8 0m0 5a1.5 1.5 0 0 1 .5 2.915l.385 1.99a.5.5 0 0 1-.491.595h-.788a.5.5 0 0 1-.49-.595l.384-1.99A1.5 1.5 0 0 1 8 5"/></svg>`;
const unlocked = `<svg viewBox="0 0 18 18" aria-hidden="true"><path fill="currentColor" d="M5 7V5a4 4 0 0 1 7.7-1.5l-1.8.7A2 2 0 0 0 7 5v2h5a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2Zm3.5 3a1 1 0 0 0-.5 1.87V13h1v-1.13A1 1 0 0 0 8.5 10Z"/></svg>`;
const chevron = `<svg viewBox="0 0 16 16" aria-hidden="true"><path d="m6 4 4 4-4 4"/></svg>`;

export function form(request: Request, error?: string): string {
  const fields = request.fields.map((field, index) => {
    const name = escape(field.id);
    // DOM IDs are independent of caller-chosen field IDs and form properties.
    const id = `field-${index}`;
    const label = escape(field.label);
    if (field.type === "multi_select") {
      return `<fieldset><legend>${label}</legend><div class="options">${
        field.options!.map((option) =>
          `<label class="option"><input type="checkbox" name="${name}" value="${escape(option.value)}"><span>${escape(option.label)}</span></label>`
        ).join("")
      }</div></fieldset>`;
    }
    const attributes = `id="${id}" required aria-describedby="${id}-error"`;
    let input: string;
    if (field.type === "select") {
      input = `<div class="select"><select name="${name}" ${attributes}>` +
        `<option value="" disabled selected hidden>Select…</option>${
          field.options!.map((option) =>
            `<option value="${escape(option.value)}">${escape(option.label)}</option>`
          ).join("")
        }</select><svg viewBox="0 0 16 16" aria-hidden="true"><path d="m5 6 3-3 3 3M5 10l3 3 3-3"/></svg></div>`;
    } else {
      const secret = field.type === "secret";
      input = `<div class="input"><input type="${secret ? "password" : "text"}" name="${name}" ${attributes} autocomplete="${secret ? "new-password" : "off"}" spellcheck="false" autocapitalize="off">${
        secret ? `<button class="reveal" type="button" aria-label="Reveal secret" aria-controls="${id}" aria-pressed="false" title="Reveal secret" hidden><span class="locked">${shield}</span><span class="unlocked">${unlocked}</span></button>` : ""
      }</div>`;
    }
    return `<div class="field"><label for="${id}">${label}</label>${input}<p class="validation" id="${id}-error" hidden>This field is required.</p></div>`;
  });
  const deliveries = request.deliveries.length === 0 ? "" :
    `<details><summary>${chevron}Details</summary><div class="deliveries">${
      request.deliveries.map((delivery) => describe(delivery, request)).join("")
    }</div></details>`;
  return `<form method="post">${header(request.title)}<div class="form-body">${
    error ? `<p class="error" role="alert">${escape(error)}</p>` : ""
  }<div class="fields">${fields.join("")}</div>${deliveries}</div><footer>` +
    `<button class="send" name="_action" value="submit">Send</button>` +
    `<button class="cancel" name="_action" value="cancel" formnovalidate>Cancel</button></footer></form>`;
}

function header(title: string): string {
  return `<header><img class="emblem" src="${emblemURL}" width="88" height="88" alt=""><div class="heading"><h1>${escape(title)}</h1><p>Values are sent directly to Key Kong on the requesting computer through your Tailscale connection.</p></div></header>`;
}

function describe(delivery: Delivery, request: Request): string {
  const action = delivery.operation === "set_env"
    ? `Set ${delivery.key} from ${request.fields.find((field) => field.id === delivery.field)?.label ?? delivery.field}`
    : delivery.operation === "insert_line"
    ? `Insert before line ${delivery.line}`
    : "Append to file";
  const template = delivery.operation === "set_env" ? "" :
    `<pre>${escape(delivery.template.replace(/\r?\n$/, ""))}</pre>`;
  return `<section class="delivery"><h2>${escape(action)}</h2><code>${escape(delivery.path)}</code>${template}</section>`;
}

export function page(status: number, body: string): Response {
  const nonce = randomBytes(16).toString("base64");
  const content = body.startsWith("<form") ? body :
    `<div class="message">${header("Key Kong")}<div role="status">${body}</div></div>`;
  return new Response(
    `<!doctype html><html lang="en"><head><meta charset="utf-8">` +
      `<meta name="viewport" content="width=device-width, initial-scale=1">` +
      `<title>Key Kong</title><style>${style}</style></head><body><main>${content}</main>` +
      `<script nonce="${nonce}">${script}</script></body></html>`,
    {
      status,
      headers: {
        "Cache-Control": "no-store",
        "Content-Security-Policy":
          `default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'nonce-${nonce}'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'`,
        "Content-Type": "text/html; charset=utf-8",
        // Browsers send `Origin: null` with form posts under `no-referrer`.
        "Referrer-Policy": "same-origin",
      },
    },
  );
}

const script = `
const form = document.querySelector('form');
if (form) {
  const send = form.querySelector('.send');
  const cancel = form.querySelector('.cancel');
  for (const button of form.querySelectorAll('.reveal')) {
    button.hidden = false;
    button.addEventListener('click', () => {
      const input = document.getElementById(button.getAttribute('aria-controls'));
      const reveal = input.type === 'password';
      input.type = reveal ? 'text' : 'password';
      button.setAttribute('aria-pressed', String(reveal));
      button.setAttribute('aria-label', reveal ? 'Hide secret' : 'Reveal secret');
      button.title = button.getAttribute('aria-label');
      input.focus();
    });
  }
  const markInvalid = (input) => {
    input.setAttribute('aria-invalid', 'true');
    document.getElementById(input.getAttribute('aria-describedby')).hidden = false;
  };
  form.addEventListener('invalid', (event) => {
    event.preventDefault();
    markInvalid(event.target);
    form.querySelector('[aria-invalid="true"]').focus();
  }, true);
  form.addEventListener('input', (event) => {
    const input = event.target;
    if (input.hasAttribute('aria-invalid')) {
      input.removeAttribute('aria-invalid');
      document.getElementById(input.getAttribute('aria-describedby')).hidden = true;
    }
  });
  form.addEventListener('submit', (event) => {
    if (event.submitter === cancel) return;
    for (const input of form.querySelectorAll('input[required]')) {
      if (!input.value.trim()) markInvalid(input);
    }
    const invalid = form.querySelector('[aria-invalid="true"]');
    if (invalid) {
      event.preventDefault();
      invalid.focus();
    }
  });
  document.addEventListener('keydown', (event) => {
    if (event.isComposing || event.altKey || event.ctrlKey || event.metaKey) return;
    if (event.key === 'Escape') {
      event.preventDefault();
      cancel.click();
    } else if (event.key === 'Enter' && event.shiftKey) {
      event.preventDefault();
      send.click();
    }
  });
  // Autofocus on desktop; leave the keyboard closed when opening on a phone.
  if (matchMedia('(min-width: 601px)').matches) {
    form.querySelector('input, select')?.focus();
  }
}
`;

// Keep these dimensions and colors aligned with KeyKongTheme and MacOSInputFormController.
const style = `
:root {
  color-scheme: dark;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  color: #fff;
  background: #17191d;
  --graphite: #252932;
  --slate: #343b47;
  --cobalt: #5376a6;
  --brass: #c99646;
  --silver: #aeb4bd;
}
* { box-sizing: border-box; }
body { margin: 0; min-height: 100svh; display: grid; place-items: center; padding: 24px; }
main {
  width: min(640px, 100%);
  border-radius: 16px;
  background: linear-gradient(180deg, var(--graphite), #17191d 72%, #1c1f25);
  box-shadow: 0 18px 60px #0006;
  position: relative;
  overflow: hidden;
}
main::before { content: ""; position: absolute; top: 31px; left: 0; right: 0; height: 1px; background: #343b47cc; }
form, .message { padding: 54px 48px 30px; display: flex; flex-direction: column; gap: 20px; }
header { display: flex; align-items: center; gap: 24px; min-height: 88px; }
.emblem { border-radius: 50%; flex: 0 0 88px; }
.heading { min-width: 0; }
h1 { margin: 0; font-size: 26px; font-weight: 600; line-height: 31px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
header p { margin: 8px 0 0; color: var(--silver); font-size: 14px; line-height: 17px; }
.form-body { min-height: 180px; max-height: 274px; overflow-y: auto; scrollbar-gutter: stable; padding: 0 6px 2px; }
.form-body:has(details[open]) { max-height: max(180px, calc(100svh - 294px)); }
.fields { display: flex; flex-direction: column; gap: 18px; }
.field > label, legend { display: block; padding: 0; margin-bottom: 7px; font-size: 13px; line-height: 16px; font-weight: 600; overflow-wrap: anywhere; }
.input, .select { position: relative; }
input:not([type=checkbox]), select {
  width: 100%; height: 36px; padding: 0 8px;
  border: 1px solid #343b47; border-radius: 6px;
  background: #19191b; color: #fff; font: inherit; font-size: 14px;
  caret-color: #fff;
}
.input:has(.reveal) input { padding-right: 42px; }
select { appearance: none; background: var(--graphite); padding-right: 28px; }
select:has(option:checked[value=""]) { color: var(--silver); }
.select > svg { position: absolute; right: 8px; top: 10px; width: 16px; height: 16px; fill: none; stroke: var(--silver); stroke-width: 1.7; pointer-events: none; }
button, summary, input[type=checkbox], select { cursor: pointer; }
button { font-family: inherit; }
button:focus-visible, summary:focus-visible, input:focus-visible, select:focus-visible { outline: 3px solid var(--cobalt); outline-offset: 1px; }
input:not([type=checkbox]):focus-visible { outline-color: #287aa8; }
.reveal { position: absolute; right: 8px; top: 4px; width: 28px; height: 28px; border: 0; border-radius: 4px; background: transparent; color: var(--brass); padding: 5px; }
.reveal svg { display: block; width: 18px; height: 18px; }
.reveal .unlocked, .reveal[aria-pressed=true] .locked { display: none; }
.reveal[aria-pressed=true] .unlocked { display: block; }
.reveal:hover { background: #c996461a; }
fieldset { border: 0; margin: 0; padding: 0; min-width: 0; }
.options { display: flex; flex-direction: column; gap: 6px; }
.option { display: flex; align-items: start; gap: 6px; color: var(--silver); font-size: 13px; line-height: 16px; cursor: pointer; overflow-wrap: anywhere; }
input[type=checkbox] { appearance: none; flex: 0 0 16px; width: 16px; height: 16px; margin: 0; border-radius: 5px; background: #383b40; position: relative; }
input[type=checkbox]:checked { background: var(--brass); }
input[type=checkbox]:checked::after { content: ""; position: absolute; left: 5px; top: 2px; width: 4px; height: 8px; border: solid #17191d; border-width: 0 2px 2px 0; transform: rotate(45deg); }
details { margin-top: 18px; }
summary { display: flex; align-items: center; gap: 4px; width: fit-content; list-style: none; color: var(--silver); font-size: 14px; font-weight: 500; line-height: 20px; border-radius: 3px; }
summary::-webkit-details-marker { display: none; }
summary > svg { width: 14px; height: 14px; fill: none; stroke: currentColor; stroke-width: 1.7; }
details[open] summary > svg { transform: rotate(90deg); }
summary:hover { color: #fff; }
.deliveries { display: flex; flex-direction: column; gap: 14px; margin-top: 18px; }
.delivery h2 { margin: 0 0 6px; font-size: 12px; line-height: 15px; font-weight: 600; overflow-wrap: anywhere; }
code, pre { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 11px; line-height: 15px; overflow-wrap: anywhere; white-space: pre-wrap; }
code { display: block; color: var(--silver); }
pre { margin: 6px 0 0; padding: 8px 10px; border: 1px solid var(--slate); border-radius: 6px; background: var(--graphite); }
footer { display: flex; flex-direction: row-reverse; gap: 12px; }
footer button { height: 34px; border-radius: 7px; font-size: 13px; color: #fff; }
.cancel { width: 104px; background: var(--slate); border: 1px solid #aeb4bd38; }
.send { width: 116px; background: var(--brass); border: 1.5px solid var(--cobalt); color: #17191d; font-weight: 500; }
.cancel:hover { background: #414957; }
.send:hover { background: #d4a258; }
footer button:active { filter: brightness(.9); }
.validation, .error { margin: 7px 0 0; color: #ff9494; font-size: 11px; line-height: 15px; }
.error { margin: 0 0 18px; font-size: 13px; }
.message [role=status] { min-height: 80px; padding: 0 6px; color: var(--silver); font-size: 14px; line-height: 21px; }
.message [role=status] p { margin: 0; }
::selection { color: #fff; background: #5376a680; }
::-webkit-scrollbar { width: 14px; }
::-webkit-scrollbar-track { background: #25293288; border-radius: 8px; }
::-webkit-scrollbar-thumb { background: #aeb4bd80; border-radius: 8px; border: 2px solid transparent; background-clip: padding-box; }
[hidden] { display: none !important; }
@media (max-width: 600px) {
  body { padding: 16px; }
  form, .message { padding: 38px 24px 24px; gap: 24px; }
  main::before { top: 20px; }
  header { gap: 16px; min-height: 72px; }
  .emblem { width: 64px; height: 64px; flex-basis: 64px; }
  h1 { font-size: 22px; line-height: 27px; white-space: normal; overflow-wrap: anywhere; }
  header p { font-size: 13px; line-height: 17px; }
  .form-body { max-height: none; min-height: 0; overflow: visible; padding: 0; scrollbar-gutter: auto; }
  .form-body:has(details[open]) { max-height: none; }
  input:not([type=checkbox]), select { height: 40px; font-size: 16px; }
  .reveal { top: 0; right: 0; width: 40px; height: 40px; padding: 11px; }
  .select > svg { top: 12px; }
  .option { min-height: 28px; align-items: center; }
  summary { min-height: 36px; }
  footer button { height: 40px; }
}
@media (max-height: 580px) and (min-width: 601px) {
  body { align-items: start; }
}
`;
