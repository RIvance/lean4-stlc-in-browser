import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  testMatch: '*.spec.ts',
  workers: 1,
  use: {
    baseURL: 'http://127.0.0.1:4178',
    viewport: { width: 1440, height: 950 },
    launchOptions: { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH },
    screenshot: 'only-on-failure',
  },
  webServer: {
    command: 'npm run preview -- --port 4178 --strictPort',
    url: 'http://127.0.0.1:4178',
  },
});
