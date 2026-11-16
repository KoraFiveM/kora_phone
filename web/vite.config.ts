import { defineConfig } from 'vite';
import type { Plugin } from 'vite';
import react from '@vitejs/plugin-react';

// kora_theme owns the colours, fonts and shape. Its Vite plugin is imported from the real resource, which sits
// next to this one in the server tree ([standalone]/kora_theme), so there is no vendored copy to keep in sync.
const themePlugin = new URL('../../../[standalone]/kora_theme/vite-plugin.mjs', import.meta.url).href;
const { default: kora_theme } = await import(/* @vite-ignore */ themePlugin) as { default: () => Plugin };

export default defineConfig({ plugins: [kora_theme(), react()], base: './', build: { sourcemap: false } });
