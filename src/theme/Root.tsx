import React from 'react';
import { JsonProvider } from 'subzerodev-data-json/react';
import { AuthProvider } from '../components/Auth/AuthProvider';
import { AuthToastContainer } from '../components/Auth/AuthToast';
import { ThemeInitializer } from '../hooks/useThemeInitialization';
import { themes, defaultTheme } from '../components/ThemeSwitcher/themes';
import { useAppInitialization } from '../hooks/useAppInitialization';
import { getJsonLoader } from '../data/jsonLoader';

//import { ConfigurationProvider } from '../components/ConfigurationManager';

// This is a Docusaurus root wrapper that provides global configuration context
export default function Root({
  children
}: {
  children: React.ReactNode;
}): React.JSX.Element {
  // Warm the projects/portfolio caches so navigating to those pages doesn't
  // wait on a fresh fetch (J6.7's replacement for the old eager DataLoader
  // preload into the zustand store).
  useAppInitialization();

  return (
    <JsonProvider loader={getJsonLoader()}>
      <AuthProvider>
        {/* Initialize theme regardless of theme switcher component visibility */}
        <ThemeInitializer themes={themes} defaultTheme={defaultTheme} />

        {/* Global toast notifications for auth and other events */}
        <AuthToastContainer />

        {/* <ConfigurationProvider> */}
        {children}
        {/* </ConfigurationProvider> */}
      </AuthProvider>
    </JsonProvider>
  );
}
