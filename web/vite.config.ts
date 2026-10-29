import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import qbtheme from './vendor/kora_theme/vite-plugin.mjs';

export default defineConfig({ plugins: [qbtheme(), react()], base: './', build: { sourcemap: false } });
