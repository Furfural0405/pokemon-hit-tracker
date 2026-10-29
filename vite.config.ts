import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';

// Vite's loadEnv also reads the VITE_* variables provided by GitHub Actions.
// Avoid process.env in the TypeScript config: @types/node is not installed.
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, '.', 'VITE_');
  return {
    plugins: [react()],
    base: env.VITE_BASE_PATH || '/pokemon-hit-tracker/',
  };
});
