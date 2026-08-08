/**
 * # Pre-Build Script for Docusaurus Site
 *
 * This script performs essential setup tasks before the main Docusaurus build process.
 * It handles configuration conversion, theme management, navigation generation, and
 * markdown file processing to prepare the site for deployment.
 *
 * ## Core Functionality:
 *
 * ### 1. Configuration Management
 * - Converts YAML configuration files to JSON format for runtime consumption
 * - Creates a TypeScript index file for seamless data imports
 * - Manages global configuration loading and validation
 *
 * ### 2. Theme System
 * - Scans CSS theme files and extracts metadata from header comments
 * - Generates theme configuration with fallbacks for missing metadata
 * - Creates a centralized theme registry for the theme switcher component
 *
 * ### 3. Navigation Generation
 * - Auto-generates navigation bar links from markdown pages
 * - Creates demo page links from TypeScript component files
 * - Handles label formatting and URL generation
 *
 * ### 4. Content Processing
 * - Copies markdown files from project root to pages directory
 * - Handles README.md -> index.md conversion for homepage
 * - Supports conditional overwriting of existing files
 *
 * ## Directory Structure:
 * - `/config/` - Source YAML configuration files
 * - `/data/` - Generated JSON data files and TypeScript index
 * - `/static/themes/` - CSS theme files with metadata headers
 * - `/src/pages/` - Destination for copied markdown files
 * - `/src/pages/demos/` - TypeScript demo components
 *
 * ## Usage:
 * - Run directly: `tsx pre-build.ts`
 * - Import as module: `import { PreBuild } from './pre-build'`
 * - Package.json scripts: `npm run prebuild`
 *
 * ## Dependencies:
 * - js-yaml: YAML parsing and conversion
 * - Node.js fs/path: File system operations
 * - Custom entities: GlobalConfig type definitions
 *
 * ## Architecture Notes:
 * - Comprehensive error handling with fallback systems
 * - Standardized logging throughout all operations
 * - Graceful handling of missing directories and files
 * - TypeScript-compatible data export generation
 * - Configurable processing with safe defaults
 *
 * ## Future Improvements:
 * - Convert to async/await pattern for better performance
 * - Add configuration schema validation with joi or zod
 * - Add comprehensive unit tests
 * - Consider file watching for development mode
 *
 * @author Template Build System
 * @version 1.0.0
 */

import * as fs from 'fs';
import * as path from 'path';
import * as yaml from 'js-yaml';

import { GlobalConfig } from '../src/entities';
import type { Theme } from '../src/components/ThemeSwitcher/models';
import type { CustomNavBarLink } from '../src/components/NavBarLinks/models';

const THEMES_DIR = path.join(__dirname, '../static/themes');
const PAGES_DIR = path.join(__dirname, '../src/pages');
const CONFIG_DIR = path.join(__dirname, '../config');
const DATA_DIR = path.join(__dirname, '../data');
const THEMES_CONFIG: string = path.join(__dirname, '../data/themes.json');
const NAVBAR_CONFIG: string = path.join(__dirname, '../data/navBarLinks.json');

/**
 * PreBuild class handles all pre-build operations for the Docusaurus portfolio site.
 *
 * This class orchestrates the conversion of YAML configurations to JSON, manages theme
 * metadata extraction, generates navigation configurations, and processes markdown files
 * to prepare the site for the main Docusaurus build process.
 *
 * ## Processing Order:
 * 1. Global configuration setup from YAML
 * 2. Configuration loading with defaults
 * 3. YAML to JSON conversion for all config files
 * 4. Data index generation for TypeScript imports
 * 5. Markdown file copying from project root
 * 6. Navigation bar generation from pages
 * 7. Theme configuration extraction and generation
 *
 * ## Key Features:
 * - Handles missing directories gracefully with automatic creation
 * - Provides detailed logging for all operations
 * - Supports conditional file overwriting based on configuration
 * - Extracts theme metadata from CSS file headers
 * - Generates TypeScript-compatible data index files
 * - Comprehensive error handling with fallback mechanisms
 * - Process continuation despite individual operation failures
 */
export class PreBuild {
  private config: GlobalConfig;

  constructor() {
    // Setup config first, then load it
    this.setupConfig();
    this.config = this.loadConfig();
  }

  /**
   * Creates or updates the TypeScript index file for the data directory.
   *
   * This method scans the data directory for JSON files and generates export
   * statements for each one, enabling clean imports throughout the application.
   *
   * ## Process:
   * 1. Ensures data directory exists (creates if missing)
   * 2. Scans for *.json files
   * 3. Generates TypeScript export statements
   * 4. Writes data/index.ts file
   *
   * @private
   */
  private createDataIndex(): void {
    const indexPath = path.join(DATA_DIR, 'index.ts');

    try {
      // Ensure data directory exists
      if (!fs.existsSync(DATA_DIR)) {
        console.log(`[INFO] Creating Data Directory: ${DATA_DIR}`);

        fs.mkdirSync(DATA_DIR, { recursive: true });
      }

      // Get all JSON files from the data directory
      const jsonFiles = fs.existsSync(DATA_DIR)
        ? fs
            .readdirSync(DATA_DIR)
            .filter((f: string) => f.endsWith('.json'))
            .sort() // Sort alphabetically for consistent output
        : [];

      if (jsonFiles.length === 0) {
        // Create empty placeholder index file if no JSON files exist
        const emptyIndexContent =
          '// Empty index - will be populated after YAML conversion\n';

        fs.writeFileSync(indexPath, emptyIndexContent, 'utf-8');

        console.log(`[INFO] Created Placeholder data/index.ts`);
      } else {
        // Generate export statements for each JSON file
        const exportStatements = jsonFiles.map((file: string) => {
          const baseName = path.parse(file).name;

          return `export { default as ${baseName} } from './${file}';`;
        });

        const indexContent = exportStatements.join('\n') + '\n';

        fs.writeFileSync(indexPath, indexContent, 'utf-8');

        console.log(
          `[INFO] Created data/index.ts with ${jsonFiles.length} JSON export(s)`
        );
      }
    } catch (error) {
      console.error(
        `[ERROR] Failed to Create Data Index: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }

  /**
   * Sets up the global configuration by converting globalConfig.yml to JSON.
   *
   * This method handles the initial conversion of the main configuration file
   * from YAML to JSON format, making it available for the loadConfig() method.
   *
   * ## Process:
   * 1. Checks for globalConfig.yml existence
   * 2. Creates data directory if missing
   * 3. Reads and parses YAML content
   * 4. Writes JSON equivalent to data/globalConfig.json
   * 5. Creates default configuration if YAML is missing
   * 6. Provides fallback minimal config on errors
   *
   * @private
   */
  private setupConfig(): void {
    try {
      const yamlConfigPath = path.join(CONFIG_DIR, 'globalConfig.yml');
      const jsonConfigPath = path.join(DATA_DIR, 'globalConfig.json');

      if (!fs.existsSync(yamlConfigPath)) {
        console.warn(`[WARN] globalConfig.yml Not Found at ${yamlConfigPath}`);

        // Create a default config if YAML doesn't exist
        const defaultConfig = {
          preBuild: {
            copyMarkdownFromProjectRoot: false,
            generateNavBarForPages: false,
            overwriteExistingFiles: false,
            projectRoot: '',
            defaultTheme: 'default'
          }
        };

        // Ensure data directory exists
        if (!fs.existsSync(DATA_DIR)) {
          console.log(`[INFO] Creating Data Directory: ${DATA_DIR}`);

          fs.mkdirSync(DATA_DIR, { recursive: true });
        }

        fs.writeFileSync(
          jsonConfigPath,
          JSON.stringify(defaultConfig, null, 2),
          'utf-8'
        );

        console.log(`[INFO] Created Default globalConfig.json`);

        return;
      }

      // Ensure data directory exists
      if (!fs.existsSync(DATA_DIR)) {
        console.log(`[INFO] Creating Data Directory: ${DATA_DIR}`);

        fs.mkdirSync(DATA_DIR, { recursive: true });
      }

      // Read and convert YAML to JSON
      const yamlContent = fs.readFileSync(yamlConfigPath, 'utf-8');
      const configData = yaml.load(yamlContent) as any;

      // Write JSON file
      fs.writeFileSync(
        jsonConfigPath,
        JSON.stringify(configData, null, 2),
        'utf-8'
      );

      console.log(`[INFO] Converted globalConfig.yml to globalConfig.json`);
    } catch (error) {
      console.error(
        `[ERROR] Failed to Convert globalConfig.yml: ${error instanceof Error ? error.message : String(error)}`
      );

      // Instead of throwing, create a minimal config and continue
      console.warn(
        '[WARN] Creating minimal configuration to continue build...'
      );

      try {
        const minimalConfig = { preBuild: {} };
        const jsonConfigPath = path.join(DATA_DIR, 'globalConfig.json');

        if (!fs.existsSync(DATA_DIR)) {
          fs.mkdirSync(DATA_DIR, { recursive: true });
        }

        fs.writeFileSync(
          jsonConfigPath,
          JSON.stringify(minimalConfig, null, 2),
          'utf-8'
        );

        console.log(`[INFO] Created Minimal globalConfig.json for Fallback`);
      } catch (fallbackError) {
        console.error(
          `[ERROR] Could Not Create Fallback Config: ${fallbackError instanceof Error ? fallbackError.message : String(fallbackError)}`
        );

        throw fallbackError; // Only throw if we can't create any config at all
      }
    }
  }

  /**
   * Extracts theme metadata from CSS file header comments.
   *
   * Parses CSS files for @theme-id and @theme-name directives in header comments
   * and creates Theme objects with fallbacks for missing metadata.
   *
   * ## Supported CSS Header Format:
   * ```css
   * /*
   *  @theme-id: dark-modern
   *  @theme-name: Dark Modern Theme
   * *\/
   * ```
   *
   * ## Process:
   * 1. Reads CSS file content
   * 2. Uses regex to extract @theme-id and @theme-name
   * 3. Validates extracted values
   * 4. Falls back to filename-based values if extraction fails
   *
   * @private
   * @param file - CSS filename to process
   * @returns Theme object with name, displayName, and cssFile path
   */
  private getThemeMetadata(file: string): Theme {
    const filePath = path.join(THEMES_DIR, file);
    const name = file.replace(/\.css$/, '');

    try {
      const content = fs.readFileSync(filePath, 'utf-8');

      // Extract theme-id and theme-name from CSS header comments with improved regex
      // Handle both single-line and multi-line comments, with better whitespace handling
      const themeIdMatch = content.match(
        /@theme-id\s*:\s*([^\s\r\n*/]{1,50})/i
      );
      const themeNameMatch = content.match(
        /@theme-name\s*:\s*([^\r\n*]{1,100})/i
      );

      // Extract and validate theme ID
      let themeId = name; // Default fallback

      if (themeIdMatch) {
        const extractedId = themeIdMatch[1].trim();

        if (/^[a-zA-Z0-9-]+$/.test(extractedId)) {
          themeId = extractedId;
        } else {
          console.warn(
            `[WARN] Invalid theme-id "${extractedId}" in ${file}, using filename`
          );
        }
      }

      // Extract and clean theme name
      let themeName = name.charAt(0).toUpperCase() + name.slice(1); // Default fallback

      if (themeNameMatch) {
        const extractedName = themeNameMatch[1].trim();

        if (extractedName.length > 0) {
          themeName = extractedName;
        }
      }

      return {
        name: themeId,
        displayName: themeName,
        cssFile: `themes/${file}` // Use relative path instead of absolute
      };
    } catch (error) {
      console.warn(
        `[WARN] Could Not Read Theme File ${file}, Using Fallback. Error: ${error instanceof Error ? `${error.message}\nStack Trace: ${error.stack}` : String(error)}`
      );

      // Use filename-based fallback (no counter needed)
      return {
        name: name,
        displayName: name.charAt(0).toUpperCase() + name.slice(1),
        cssFile: `themes/${file}` // Use relative path
      };
    }
  }

  /**
   * Generates the complete theme configuration file from CSS theme files.
   *
   * Scans the static/themes directory for CSS files, extracts metadata from each,
   * and creates a comprehensive theme configuration with default theme selection.
   *
   * ## Output Format:
   * ```json
   * {
   *   "themes": [
   *     { "name": "theme-id", "displayName": "Theme Name", "cssFile": "themes/file.css" }
   *   ],
   *   "defaultTheme": "theme-id"
   * }
   * ```
   *
   * ## Process:
   * 1. Scans static/themes directory for *.css files
   * 2. Extracts metadata from each using getThemeMetadata()
   * 3. Identifies default theme from config or uses first theme
   * 4. Writes themes.json configuration
   *
   * @public
   */
  public generateThemeConfig(): void {
    if (!fs.existsSync(THEMES_DIR)) {
      console.warn(`[WARN] Themes Directory Not Found: ${THEMES_DIR}`);

      return;
    }

    const cssFiles = fs
      .readdirSync(THEMES_DIR)
      .filter((f) => f.endsWith('.css'));
    const themes: Theme[] = cssFiles.map((f) => this.getThemeMetadata(f));

    // Find the default theme
    const defaultTheme =
      themes.find((t) => t.name === this.config.preBuild?.defaultTheme) ||
      themes.find((t) => t.name === 'default') ||
      (themes.length > 0
        ? themes[0]
        : {
            name: 'default',
            displayName: 'Default',
            cssFile: 'themes/default.css'
          });

    // Create the JSON data structure
    const themeData = {
      themes: themes,
      defaultTheme: defaultTheme?.name || this.config.preBuild?.defaultTheme
    };

    // Write the JSON file
    fs.writeFileSync(
      THEMES_CONFIG,
      JSON.stringify(themeData, null, 2),
      'utf-8'
    );

    console.log(`[INFO] Theme Config Created with ${themes.length} Theme(s)`);
  }

  /**
   * Copies markdown files from project root to src/pages directory.
   *
   * Handles the transfer of documentation files from the main project directory
   * to the Docusaurus pages directory, with special handling for README.md files.
   *
   * ## Process:
   * 1. Checks if copyMarkdownFromProjectRoot is enabled in config
   * 2. Validates project root path exists
   * 3. Ensures pages directory exists
   * 4. Scans project root for *.md files
   * 5. Copies files with README.md → index.md conversion
   * 6. Respects overwriteExistingFiles configuration
   *
   * @private
   */
  private copyMarkdown(): void {
    if (!this.config.preBuild?.copyMarkdownFromProjectRoot) {
      console.log('[INFO] Markdown Copying Disabled or Not Configured');

      return;
    }

    if (!this.config.preBuild?.projectRoot) {
      console.warn(
        '[WARN] Project Root Path Not Configured, Skipping Markdown Copy'
      );

      return;
    }

    // Ensure the pages directory exists first
    if (!fs.existsSync(PAGES_DIR)) {
      fs.mkdirSync(PAGES_DIR, { recursive: true });
    }

    // Check if project root exists
    if (!fs.existsSync(this.config.preBuild.projectRoot)) {
      console.warn(
        `[WARN] Project Root Directory Not Found: ${this.config.preBuild.projectRoot}`
      );

      return;
    }

    const mdFiles = fs
      .readdirSync(this.config.preBuild.projectRoot)
      .filter((f) => f.endsWith('.md'));

    mdFiles.forEach((file) => {
      const srcPath = path.join(this.config.preBuild.projectRoot, file);
      // Rename README.md to index.md in destination directory
      const destFile = file.toLowerCase() === 'readme.md' ? 'index.md' : file;
      const dstPath = path.join(PAGES_DIR, destFile);

      const fileExists = fs.existsSync(dstPath);

      if (!fileExists || this.config.preBuild?.overwriteExistingFiles) {
        fs.copyFileSync(srcPath, dstPath);

        const action = fileExists ? 'Overwrote' : 'Copied';

        console.log(`[INFO] ${action} ${file} --> src/pages/${destFile}`);
      } else {
        console.log(`[INFO] Skipped ${file} --> src/pages/${destFile}`);
      }
    });
  }

  /**
   * Generates navigation bar configuration from markdown pages.
   *
   * Creates navigation links for all markdown files in the pages directory,
   * excluding index.md (homepage), and formats labels appropriately.
   *
   * ## Output Format:
   * ```json
   * {
   *   "links": [
   *     { "label": "About", "to": "/about", "href": "/about", "position": "left" }
   *   ]
   * }
   * ```
   *
   * ## Process:
   * 1. Checks if generateNavBarForPages is enabled
   * 2. Validates pages directory exists
   * 3. Scans pages directory for *.md files
   * 4. Filters out index.md
   * 5. Formats labels (title case, replaces hyphens/underscores)
   * 6. Writes navBarLinks.json configuration
   *
   * @private
   */
  private generateNavbar(): void {
    if (!this.config.preBuild?.generateNavBarForPages) {
      console.log('[INFO] Navbar Generation Disabled or Not Configured');

      return;
    }

    // Check if pages directory exists
    if (!fs.existsSync(PAGES_DIR)) {
      console.warn(`[WARN] Pages Directory Not Found: ${PAGES_DIR}`);

      return;
    }

    const mdFiles = fs.readdirSync(PAGES_DIR).filter((f) => f.endsWith('.md'));
    let numberOfLinks = 0;

    // Exclude index.md (homepage) from navbar links
    const links: CustomNavBarLink[] = mdFiles
      .filter((file) => path.parse(file).name.toLowerCase() !== 'index')
      .map((file) => {
        const name = path.parse(file).name;
        const toPath = `/${name}`;

        numberOfLinks++;

        return {
          label: file
            .replace(/\.(md|mdx)$/, '')
            .replace(/[-_]/g, ' ')
            .replace(/\b\w/g, (c) => c.toUpperCase()),
          to: toPath,
          href: toPath,
          position: 'left' as const
        };
      });

    // Create the JSON data structure
    const navbarData = {
      links: links
    };

    // Write the JSON file
    fs.writeFileSync(
      NAVBAR_CONFIG,
      JSON.stringify(navbarData, null, 2),
      'utf-8'
    );

    console.log(`[INFO] Navbar Config Created with ${numberOfLinks} Entry(s)`);
  }

  /**
   * Processes all YAML configuration files and converts them to JSON.
   *
   * Batch converts all *.yml and *.yaml files from the config directory
   * to corresponding *.json files in the data directory.
   *
   * ## Process:
   * 1. Ensures data directory exists
   * 2. Scans config directory for YAML files
   * 3. Parses each YAML file using js-yaml
   * 4. Writes JSON equivalent to data directory
   * 5. Regenerates data/index.ts after conversion
   * 6. Continues processing even if individual files fail
   *
   * @private
   */
  private processYamlToJson(): void {
    // Ensure the data directory exists
    if (!fs.existsSync(DATA_DIR)) {
      fs.mkdirSync(DATA_DIR, { recursive: true });
    }

    if (!fs.existsSync(CONFIG_DIR)) {
      console.warn(`[WARN] Config Directory Not Found: ${CONFIG_DIR}`);

      return;
    }

    const yamlFiles = fs
      .readdirSync(CONFIG_DIR)
      .filter((f) => f.endsWith('.yml') || f.endsWith('.yaml'))
      // sources.public.yml is converted separately, through the package's own
      // validating reader (processSourceMap), not this naive yaml.load() pass.
      .filter((f) => f !== 'sources.public.yml');

    let processedCount = 0;

    yamlFiles.forEach((file) => {
      try {
        const yamlPath = path.join(CONFIG_DIR, file);
        const yamlContent = fs.readFileSync(yamlPath, 'utf-8');

        // Parse YAML to JavaScript object
        const jsonData = yaml.load(yamlContent);

        // Generate JSON filename (replace .yml/.yaml with .json)
        const jsonFileName = file.replace(/\.(yml|yaml)$/, '.json');
        const jsonPath = path.join(DATA_DIR, jsonFileName);

        // Write JSON file (overwrite if exists)
        fs.writeFileSync(jsonPath, JSON.stringify(jsonData, null, 2), 'utf-8');

        console.log(`[INFO] Converted ${file} --> data/${jsonFileName}`);
        processedCount++;
      } catch (error) {
        console.error(
          `[ERROR] Failed to Process ${file}: ${error instanceof Error ? error.message : String(error)}`
        );
      }
    });

    console.log(
      `[INFO] YAML to JSON Conversion Completed: ${processedCount} File(s) Processed`
    );
  }

  /**
   * Validates config/sources.public.yml against subzerodev-data-json's own SourceMap
   * rules (via readSourceMap) and writes the result to data/sources.public.json.
   *
   * Uses the package's reader rather than the naive yaml.load() pass every other
   * config file goes through, so a malformed entry (missing `cache`, more than one
   * of url/path/inline, etc.) is caught here instead of reaching the browser as an
   * unvalidated map (J6.9).
   *
   * @private
   */
  private async processSourceMap(): Promise<void> {
    const configPath = path.join(CONFIG_DIR, 'sources.public.yml');

    if (!fs.existsSync(configPath)) {
      console.warn(
        `[WARN] sources.public.yml Not Found, Skipping Source Map Validation`
      );

      return;
    }

    if (!fs.existsSync(DATA_DIR)) {
      fs.mkdirSync(DATA_DIR, { recursive: true });
    }

    // Dynamic import: this script compiles to CommonJS (scripts/tsconfig.json),
    // and subzerodev-data-json is ESM-only with no `require` export condition —
    // a static import fails resolution under the CJS loader.
    const { readSourceMap } = await import('subzerodev-data-json/node');
    const sourceMap = await readSourceMap(configPath);
    // Not `sources.public.json`: createDataIndex() re-exports each data/*.json
    // file under its basename as a TS identifier, and `sources.public` isn't
    // one (the dot breaks `export { default as sources.public } from ...`).
    const outputPath = path.join(DATA_DIR, 'sourcesPublic.json');

    fs.writeFileSync(outputPath, JSON.stringify(sourceMap, null, 2), 'utf-8');

    console.log(`[INFO] Validated sources.public.yml --> data/sourcesPublic.json`);
  }

  /**
   * Loads the global configuration from the generated JSON file.
   *
   * Reads and parses the globalConfig.json file created by setupConfig()
   * and returns it as a typed GlobalConfig object with comprehensive fallbacks.
   *
   * ## Process:
   * 1. Checks for globalConfig.json existence
   * 2. Reads and parses JSON content
   * 3. Validates configuration data
   * 4. Adds default values for missing properties
   * 5. Returns default config if all else fails
   *
   * @private
   * @returns Parsed GlobalConfig object with guaranteed defaults
   */
  private loadConfig(): GlobalConfig {
    try {
      // Read the fresh GlobalConfig.json file directly
      const globalConfigPath = path.join(DATA_DIR, 'globalConfig.json');

      if (!fs.existsSync(globalConfigPath)) {
        console.warn(
          '[WARN] globalConfig.json Not Found, Using Default Configuration'
        );

        return this.getDefaultConfig();
      }

      const globalConfigContent = fs.readFileSync(globalConfigPath, 'utf-8');
      const configData = JSON.parse(globalConfigContent);

      // Validate that required configuration exists
      if (!configData) {
        console.warn(
          '[WARN] globalConfig Data is Null or Undefined, Using Defaults'
        );
        return this.getDefaultConfig();
      }

      // Add default values for missing PreBuild properties
      if (!configData.preBuild) {
        console.warn('[WARN] PreBuild Configuration Missing, Using Defaults');

        configData.preBuild = this.getDefaultConfig().preBuild;
      }

      // Add default values for missing Projects properties
      if (!configData.projects) {
        console.warn('[WARN] Projects Configuration Missing, Using Defaults');

        // Note: projects is not part of GlobalConfig interface - this line should be removed or handled differently
      }

      return configData as GlobalConfig;
    } catch (error) {
      console.error(
        `[ERROR] Failed to Load Config: ${error instanceof Error ? error.message : String(error)}`
      );
      console.warn('[WARN] Using Default Configuration as Fallback');

      return this.getDefaultConfig();
    }
  }

  /**
   * Returns the default configuration object.
   *
   * @private
   * @returns Default GlobalConfig object
   */
  private getDefaultConfig(): GlobalConfig {
    return {
      preBuild: {
        copyMarkdownFromProjectRoot: false,
        generateNavBarForPages: false,
        overwriteExistingFiles: false,
        projectRoot: '',
        defaultTheme: 'default'
      },
      site: {
        title: 'Default Site',
        tagline: 'Default Tagline',
        url: 'https://localhost:3000',
        baseUrl: '/',
        organizationName: 'default',
        projectName: 'default'
      }
    };
  }

  /**
   * Main processing method that orchestrates all pre-build operations.
   *
   * Executes all pre-build tasks in the correct order to prepare the site
   * for the main Docusaurus build process.
   *
   * ## Processing Order:
   * 1. Convert all YAML files to JSON (processYamlToJson)
   * 2. Copy markdown files from project root (copyMarkdown)
   * 3. Generate navigation configuration (generateNavbar)
   * 4. Generate theme configuration (generateThemeConfig)
   * 5. Create data index file for TypeScript imports (createDataIndex)
   *
   * ## Features:
   * - Comprehensive error handling for the entire process
   * - Detailed logging with progress indicators
   * - Continues build even if individual steps fail
   * - Graceful degradation with fallback mechanisms
   *
   * @public
   */
  public async process(): Promise<void> {
    try {
      console.log('[INFO] Starting Pre Build Process...');

      this.processYamlToJson();
      await this.processSourceMap();
      this.copyMarkdown();
      this.generateNavbar();
      this.generateThemeConfig();
      this.createDataIndex();

      console.log('[INFO] Pre Build Process Completed Successfully');
    } catch (error) {
      console.error(
        `[ERROR] Pre Build Process Failed: ${error instanceof Error ? error.message : String(error)}`
      );

      // Don't throw the error, just log it so the build can continue
      console.warn('[WARN] Continuing with Build Despite Pre-Build Errors');
    }
  }
}

// Only run if invoked directly, not imported
if (process.argv[1] && process.argv[1].endsWith('pre-build.ts')) {
  new PreBuild().process();
}

/**
 * ## Script Summary:
 *
 * This pre-build script provides essential preparation for the Docusaurus build process
 * with robust error handling, comprehensive fallback systems, and detailed logging.
 *
 * ### Key Capabilities:
 * - **Configuration Management**: YAML to JSON conversion with intelligent defaults
 * - **Theme System**: Automatic theme detection and metadata extraction
 * - **Navigation Generation**: Dynamic navbar creation from page structure
 * - **Content Processing**: Markdown file copying and transformation
 * - **Data Management**: TypeScript-compatible index generation
 *
 * ### Reliability Features:
 * - Graceful handling of missing files and directories
 * - Comprehensive fallback mechanisms
 * - Detailed logging for debugging and monitoring
 * - Build process continuation despite individual failures
 * - Standardized error handling throughout
 *
 * ### Future Enhancements:
 * - Async/await pattern implementation
 * - Configuration schema validation
 * - Comprehensive unit test coverage
 * - Development mode with file watching
 *
 * ## Status: [READY] Production Ready
 * All core functionality implemented with robust error handling and comprehensive documentation.
 */
