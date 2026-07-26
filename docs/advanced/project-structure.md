---
id: project-structure
title: Project Structure
sidebar_position: 1
---

```text
├── docusaurus.config.ts            # Main Docusaurus configuration
├── sidebars.ts                     # Sidebar navigation structure
├── readme-config.json              # (Optional) README processing configuration for advanced setups
├── .copy.ignore.example            # File ignore patterns for copying
├── template-build.ps1              # Development server launcher (with full docs)
├── scripts/
│   ├── Invoke-SetupDocs.ps1        # Canonical setup script for new template copies
│   └── pre-build.ts               # Pre-build tasks: markdown copy, navbar generation, versioning
├── src/
│   ├── components/
│   │   ├── ProjectBadges/         # GitHub dynamic badge component
│   │   │   ├── index.tsx          # GitHub project badges component
│   │   │   └── useConfig.ts       # Badge config hook (uses static TS config)
│   │   └── ReadmeContent/         # Auto-generated README component
│   │       └── index.tsx          # Generated from main README.md
│   ├── config/
│   │   ├── badge-config.ts        # Static badge configuration (TypeScript)
│   │   └── giscus-config.ts       # Static Giscus configuration (TypeScript)
│   ├── examples/
│   │   ├── GitHubProjectBadges-Examples.tsx    # Basic badge examples
│   │   └── GitHubProjectBadges-Advanced.tsx    # Advanced badge examples
│   ├── types/
│   │   └── json.d.ts              # TypeScript declarations for JSON imports
│   └── css/
│       ├── custom.css             # Standard styling
│       └── custom.nuke.css        # Minimal styling option
├── static/
│   ├── img/                       # Static images and favicon
│   └── CNAME                      # GitHub Pages domain config
└── package.json                   # Dependencies and scripts
```
