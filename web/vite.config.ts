import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import kora_theme from './vendor/kora_theme/vite-plugin.mjs';

export default defineConfig({ plugins: [kora_theme(), react()], base: './', build: { sourcemap: false } });
