import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';

export default defineConfig({
  plugins: [
    react(),
    {
      name: 'mock-docusaurus-context-jsx',
      load(id) {
        // Intercept problematic Docusaurus file that contains JSX in .js
        if (id.replace(/\\/g, '/').endsWith('/@docusaurus/core/lib/client/docusaurusContext.js')) {
          return `export const Context = { Provider: ({ children }) => children };
export function DocusaurusContextProvider({ children }) { return children; }`;
        }
        return null;
      }
    }
  ],
  esbuild: {
    jsx: 'automatic'
  },
  optimizeDeps: {
    esbuildOptions: {
      loader: {
        '.js': 'jsx'
      }
    }
  },
  resolve: {
    alias: {
      '@theme/Heading': fileURLToPath(
        new URL('./src/test/mocks/Heading.tsx', import.meta.url)
      ),
      '@docusaurus/Link': fileURLToPath(
        new URL('./src/test/mocks/Link.tsx', import.meta.url)
      ),
      '@docusaurus/core/lib/client/exports/useDocusaurusContext': fileURLToPath(
        new URL('./src/test/mocks/useDocusaurusContext.ts', import.meta.url)
      ),
      '@docusaurus/core/lib/client/docusaurusContext': fileURLToPath(
        new URL('./src/test/mocks/docusaurusContext.js', import.meta.url)
      ),
      '@docusaurus/core/lib/client/docusaurusContext.js': fileURLToPath(
        new URL('./src/test/mocks/docusaurusContext.js', import.meta.url)
      )
    }
  },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./vitest.setup.ts'],
    coverage: {
      provider: 'istanbul',
      reporter: ['text', 'html', 'lcov'],
      reportsDirectory: './coverage',
      include: ['src/**/*.{ts,tsx}'],
      exclude: [
        '**/__tests__/**',
        '**/*.test.*',
        'src/test/**',
        '**/*.d.ts'
      ],
      all: false,
      thresholds: {
        lines: 55,
        functions: 55,
        branches: 45,
        statements: 55
      }
    }
  }
});
