import { defineConfig } from 'vite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export default defineConfig({
  base: './',
  worker: { format: 'es' },
  server: {
    fs: {
      // The locally linked library owns Monaco's prebuilt editor worker.
      allow: [
        fileURLToPath(new URL('.', import.meta.url)),
        fileURLToPath(new URL('../playground-core/dist/', import.meta.url)),
      ],
    },
  },
  // A static host needs no cross-origin isolation or special response headers.
  build: {
    target: 'es2022', assetsInlineLimit: 0,
    rolldownOptions: {
      onwarn(warning, warn) {
        // This application is entirely a client. Mantine's React Server
        // Components boundaries have no meaning in this static bundle.
        if (warning.code === 'MODULE_LEVEL_DIRECTIVE' && warning.message.includes('use client')) return;
        warn(warning);
      },
    },
  },
  resolve: { dedupe: ['react', 'react-dom'] },
  plugins: [{
    name: 'runtime-notices',
    generateBundle() {
      this.emitFile({
        type: 'asset', fileName: 'THIRD-PARTY-NOTICES.txt',
        source: readFileSync(new URL('./generated/THIRD-PARTY-NOTICES.txt', import.meta.url), 'utf8'),
      });
    },
  }],
});
