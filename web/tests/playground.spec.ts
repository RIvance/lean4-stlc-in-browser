import { expect, test, type Page } from '@playwright/test';

async function replaceSource(page: Page, text: string) {
  const editor = page.getByRole('textbox', { name: /Source code editor/ });
  await editor.focus();
  await page.keyboard.press('Control+a');
  // Pasting preserves braces verbatim; simulated typing invokes Monaco's auto-closing rules.
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.evaluate((source) => navigator.clipboard.writeText(source), text);
  await page.keyboard.press('Control+v');
}

test('runs the Lean WebAssembly interpreter using only static assets', async ({ page }) => {
  const errors: string[] = [];
  const requests: { method: string; url: string; body: string | null }[] = [];
  const workers: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  page.on('request', (request) => requests.push({ method: request.method(), url: request.url(), body: request.postData() }));
  page.on('worker', (worker) => workers.push(worker.url()));
  await page.goto('/');
  await expect(page.getByTestId('source-editor')).toBeVisible();
  await page.getByRole('button', { name: /^Run/ }).click();
  await expect(page.getByTestId('execution-value')).toContainText('42 : Nat');
  expect(await page.evaluate(() => crossOriginIsolated)).toBe(false);
  expect(workers.some((url) => url.includes('runtime.worker'))).toBe(true);
  expect(requests.some((request) => request.url.endsWith('.wasm'))).toBe(true);
  expect(requests.every((request) => request.method === 'GET' && request.body === null)).toBe(true);
  expect(requests.every((request) => new URL(request.url).origin === 'http://127.0.0.1:4178')).toBe(true);
  expect(errors).toEqual([]);
  await page.screenshot({ path: 'test-results/playground.png', fullPage: true });
});

test('checks edits, displays type errors, and runs again after correction', async ({ page }) => {
  await page.goto('/');
  await replaceSource(page, 'let add = (x: Nat, y: Nat) ⇒ x + y in\nadd(20, false)');
  await expect(page.locator('.squiggly-error').first()).toBeVisible();
  await page.getByRole('button', { name: /^Run/ }).click();
  await expect(page.locator('.stderr')).toContainText('Expected Nat, found Bool.');
  await replaceSource(page, 'let x = 10 in let f = (y: Nat, z: Nat) ⇒ x + y + z in let x = 99 in f 1 1');
  await page.getByRole('button', { name: /^Run/ }).click();
  await expect(page.getByTestId('execution-value')).toContainText('12 : Nat');
  await page.reload();
  await expect(page.locator('.view-lines')).toContainText('let x = 10');
});

test('can stop worker startup and start a new run', async ({ page }) => {
  await page.route('**/*.wasm', async (route) => {
    await new Promise((resolve) => setTimeout(resolve, 1500));
    await route.continue().catch(() => {});
  });
  await page.goto('/');
  await page.getByRole('button', { name: /^Run/ }).click();
  await page.getByRole('button', { name: 'Stop', exact: true }).click();
  await expect(page.getByRole('button', { name: /^Run/ })).toBeVisible();
  await page.unroute('**/*.wasm');
  await page.getByRole('button', { name: /^Run/ }).click();
  await expect(page.getByTestId('execution-value')).toContainText('42 : Nat');
});

test('runs recursion and blocks, and requires an expression after explicit in', async ({ page }) => {
  await page.goto('/');
  await replaceSource(page, 'def factorial (n: Nat) =\n  if n == 0 then 1 else n * factorial (n - 1)\nfactorial 5');
  await page.getByRole('button', { name: /^Run/ }).click();
  await expect(page.getByTestId('execution-value')).toContainText('120 : Nat');
  await replaceSource(page, '{\n  42\n  let x = 1\n}');
  await page.getByRole('button', { name: /^Run/ }).click();
  await expect(page.getByTestId('execution-value')).toContainText('() : Unit');
  await replaceSource(page, 'let x = 1 in\n');
  await expect(page.locator('.squiggly-error').first()).toBeVisible();
  await page.getByRole('button', { name: /^Run/ }).click();
  await expect(page.locator('.stderr')).toContainText('Parse error');
});
