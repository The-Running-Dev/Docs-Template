# LLMs Discoverable PowerShell Interface Specification

> **Not published documentation.** This is a planning brief describing changes to
> a *different* directory, `The-Running-Dev/LLMs`. It lives outside `docs/` so it
> does not appear on the PSGenerator documentation site, where a reader
> would reasonably mistake another project's `setup/` layout for this one's.

## Purpose

Use this document as an implementation prompt for
`The-Running-Dev/LLMs`. It describes the smallest directory change needed to
give `SubZeroDev.PSGenerator` an unambiguous PowerShell interface to
discover.

This specification is based on the complete documentation set in the pinned
LLMs checkout, including the root documentation, `setup/docs`, directory
instructions and roadmap, and its documentation-site sources.

The work must preserve the existing setup architecture. It is not a rewrite of
the provisioning or project-generation implementation.

## Documented product boundary

The root `README.md` is the canonical documentation source. It identifies two
primary PowerShell workflows:

1. `setup/setup.ps1` performs one-time, cross-platform workstation setup.
2. `setup/setup-project.ps1` scaffolds a new AI-assisted project.

The container exposes three entrypoint modes:

- `docs` serves the generated documentation on port 8080.
- `setup` forwards arguments to `setup/setup.ps1`.
- `pwsh` starts PowerShell for inspection or explicit script execution.

The generated PowerShell interface should represent the two documented
workflows. It must not treat every implementation script or exported helper
function as an end-user command.

## Existing implementation boundary

The current implementation is intentionally layered:

- `setup/setup.ps1` detects the operating system and dispatches workstation
  setup.
- `setup/setup-windows.ps1`, `setup/setup-macos.ps1`, and
  `setup/setup-ubuntu.ps1` install platform prerequisites.
- `setup/setup-workstation.ps1` coordinates shared integrations.
- `setup/scripts/workstation/install-*.ps1` are focused implementation
  components called by the workstation orchestrator.
- `setup/setup-project.ps1` is the documented project-creation orchestrator.
- `setup/modules/ProjectSetup.psm1` contains project-generation implementation
  functions called by `setup/setup-project.ps1`.
- `setup/modules/Common.ps1` contains private shared helpers.
- `setup/scripts/starters/setup-starter-*.ps1` are language-extension
  components called by `ProjectSetup.psm1`.
- `setup/setup-docs.ps1`, `setup/docs-local.ps1`, and
  `setup/docs-workflow-local.ps1` support the documentation pipeline.
- `container-entrypoint.ps1` is container infrastructure.

These files must retain their current roles and paths unless a compatibility
wrapper is added.

## Files that must not become discovered public commands

Do not expose these implementation categories:

- `container-entrypoint.ps1`
- platform scripts such as `setup-windows.ps1`
- `setup-workstation.ps1`
- `install-*.ps1` component scripts
- `setup-starter-*.ps1` language extensions
- documentation build scripts
- functions from `Common.ps1`
- the 14 implementation functions exported by `ProjectSetup.psm1`
- any PowerShell file used only by documentation infrastructure

`ProjectSetup.psm1` uses `Export-ModuleMember` so its orchestrator can call a
defined implementation API. That technical export list is not the documented
end-user interface and must not be promoted automatically into the generated
container module.

## Required discoverable structure

Add a small facade module at the directory:

```text
PowerShell/
├── LLMs.psd1
├── LLMs.psm1
├── Public/
│   ├── Initialize-LlmWorkspace.ps1
│   └── New-LlmProject.ps1
└── Private/
    └── (optional facade-only helpers)
```

Do not move the existing `setup` implementation into this directory. The facade
must delegate to the existing scripts so there remains one implementation of
each workflow.

## Public command 1: `Initialize-LlmWorkspace`

This command represents the documented `setup/setup.ps1` workflow.

It must expose the current setup parameters:

- `Client` with `Codex`, `ClaudeCode`, and `Both`
- `SkipClaudeMem`
- `SkipGitHub`
- `SkipPlaywright`
- `SkipGraphify`
- `IncludeFilesystem`
- `FilesystemPath`
- `IncludeDatabase`
- `DatabaseName`
- `DatabaseCommand`
- `DatabaseArgument`

Requirements:

- Use `[CmdletBinding(SupportsShouldProcess)]`.
- Preserve the existing defaults and validation.
- Include complete comment-based help based on the canonical README and setup
  specification.
- Delegate to `setup/setup.ps1`; do not duplicate platform detection or
  installer logic.
- Preserve the current `-WhatIf` behavior.
- Explain in help that container execution changes the container environment
  unless configuration paths are persisted.
- Document the Docker-socket security boundary for Docker-based integrations.

## Public command 2: `New-LlmProject`

This command represents the documented `setup/setup-project.ps1` workflow.

It must expose the current project parameters:

- `ProjectPath`
- `ProjectName`
- `Language`
- `Client`
- `GitUserName`
- `GitUserEmail`
- `SkipGit`
- `SkipLanguageStarter`
- `SkipValidation`
- `AutoCommit`

Requirements:

- Use `[CmdletBinding(SupportsShouldProcess)]`.
- Preserve mandatory fields, defaults, and `ValidateSet` values.
- Include complete comment-based help based on the quick start, new-project
  guide, setup specification, modular architecture, and language-starter
  reference.
- Delegate to `setup/setup-project.ps1`.
- Preserve the current project layout and generated files.
- Preserve `-WhatIf`.
- Do not claim validation or auto-commit behavior that the implementation does
  not actually guarantee. The current roadmap records correctness issues in
  build/test exit handling and auto-commit gating; either fix those issues first
  or document the actual behavior accurately.

## Facade module manifest

Create `PowerShell/LLMs.psd1` with:

- `RootModule = 'LLMs.psm1'`
- a valid semantic `ModuleVersion`
- a stable `GUID`
- non-empty `Author`, `CompanyName`, `Description`, and `PowerShellVersion`
- `FunctionsToExport` containing exactly:
  - `Initialize-LlmWorkspace`
  - `New-LlmProject`
- `CmdletsToExport = @()`
- `VariablesToExport = @()`
- `AliasesToExport = @()`
- directory URL, project URL, license URL, and useful tags under
  `PrivateData.PSData` when known

Do not use wildcard exports.

`PowerShell/LLMs.psm1` should dot-source only files under `PowerShell/Public` and
facade-specific helpers under `PowerShell/Private`. It must not recursively
dot-source all files beneath `setup`.

## Existing `ProjectSetup` module

The existing module may receive a sibling
`setup/modules/ProjectSetup.psd1` for correctness and direct development use,
but it is not the container module facade.

If that manifest is added:

- its `FunctionsToExport` must exactly match the existing literal
  `Export-ModuleMember` list;
- `Common.ps1` helpers must remain private;
- existing imports from `setup/setup-project.ps1` must continue to work;
- discovery metadata must identify it as an internal implementation module.

Adding this internal manifest is optional for the facade task.

## Documentation ownership

- The root `README.md` remains canonical.
- `setup/docs` remains the authored detailed documentation set.
- `setup/docs/index.md` remains a placeholder replaced from the root README.
- If the facade is documented, update the canonical README and an appropriate
  authored page under `setup/docs`; let the documentation build generate its
  rendered output.

## Discovery contract for PSGenerator

PSGenerator should be able to:

1. Locate `PowerShell/LLMs.psd1`.
2. Read `RootModule` and the literal `FunctionsToExport` list without importing
   the module.
3. Parse the two files under `PowerShell/Public`.
4. Extract command names, parameter metadata, validation, help, examples, and
   `SupportsShouldProcess` from PowerShell AST.
5. Ignore `PowerShell/Private`.
6. Ignore the separate implementation tree under `setup`.
7. Ignore documentation infrastructure outside the public PowerShell facade.
8. Perform discovery without running setup, installers, project generation,
   Docker, package managers, or documentation synchronization.

The manifest is the authoritative public boundary. File presence elsewhere in
the directory is not sufficient to make a command public.

## Compatibility and security constraints

- Preserve documented Windows, macOS, and Ubuntu/Debian behavior.
- Preserve Windows PowerShell 5.1 compatibility where the existing setup
  workflow claims it, unless the project intentionally changes that support
  policy.
- Preserve all existing script paths used by orchestrators.
- Do not duplicate setup logic in the facade.
- Do not initialize Git repositories, install packages, register MCP servers,
  modify user configuration, or start containers during discovery or tests.
- Do not add tokens, `.env` contents, credentials, or machine-specific paths.
- Keep Filesystem MCP disabled by default.
- Preserve GitHub MCP's read-only default and explicit toolset allow-list.
- Treat Docker-socket access as privileged host access and document it.

## Validation

Add non-invasive tests that:

1. Run `Test-ModuleManifest PowerShell/LLMs.psd1`.
2. Parse every facade `.ps1` file with the PowerShell parser and require zero
   parse errors.
3. Compare `FunctionsToExport` with the two public facade filenames.
4. Import the facade module without invoking either command.
5. Confirm exactly `Initialize-LlmWorkspace` and `New-LlmProject` are exported.
6. Confirm `Common.ps1`, `ProjectSetup.psm1` functions, platform scripts,
   installers, starters, documentation scripts, and `container-entrypoint.ps1`
   are not exported.
7. Exercise command binding and `-WhatIf` only with mocks or a non-invasive
   delegation seam.
8. Confirm no generated documentation output changed.

## Acceptance criteria

- `PowerShell/LLMs.psd1` and `PowerShell/LLMs.psm1` exist.
- Exactly two documented workflow commands are public.
- Both commands have complete help and preserve source parameter contracts.
- Both commands delegate to the existing orchestrators.
- Existing setup and project-generation behavior remains intact.
- Implementation components remain private.
- Discovery requires no code execution.
- Tests perform no installation, registration, project creation, container
  start, or documentation synchronization.
- Canonical documentation is updated through authored sources rather than rendered
  documentation output.

## Instruction to the implementing LLM

Read the root README, Roadmap, every authored document under `setup/docs`, the
current setup scripts, `ProjectSetup.psm1`, `Common.ps1`, the Dockerfile, and
`container-entrypoint.ps1` before editing. Treat the root README as canonical
and rendered documentation output as generated.

Implement the smallest facade described here. Do not expose implementation
components merely because they are scripts or technically exported from an
internal module. Preserve existing behavior and paths, add non-invasive tests,
and report exact files changed, commands run, and validation results.
