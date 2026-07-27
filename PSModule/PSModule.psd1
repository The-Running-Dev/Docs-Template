@{
    Id = 'directory.docusaurustemplate'
    GeneratedBy = 'SubZeroDev.PSGenerator'
    ModuleName = 'DocsTemplate'
    ModuleVersion = '0.1.0'
    ContainerImage = 'DocsTemplate'
    Commands = @(
        @{
            Id = 'script.scripts.template.test-documentation'
            Name = 'Invoke-DocsTest'
            Synopsis = 'Runs the documentation gate against a project.'
            Description = 'Runs the documentation gate -- relative links, heading anchors, terminology, and drift between a generated file and its source. Exposed here so the gate can be run from the image without PowerShell installed on the host; pass -Path and -SettingsPath pointing at the mounted project.'
            SourcePath = 'scripts/template/Test-Documentation.ps1'
            SourceKind = 'Script'
            Parameters = @(
                @{
                    Name = 'Path'
                    Type = 'String[]'
                    Mandatory = $false
                    Description = 'Files or directories to check. Defaults to the whole project.'
                }
                @{
                    Name = 'SettingsPath'
                    Type = 'String'
                    Mandatory = $false
                    Description = 'Rules file. Defaults to .config/DocumentationRules.psd1 under the project root.'
                }
                @{
                    Name = 'TreatWarningsAsErrors'
                    Type = 'switch'
                    Mandatory = $false
                    Description = 'Fail the run on warnings as well as errors.'
                }
            )
        }
        @{
            Id = 'script.scripts.docs-build-image'
            Name = 'Invoke-DocsBuildImage'
            Synopsis = 'Runs the discovered PowerShell script ''scripts/docs-build-image.ps1''.'
            Description = 'Scaffolded from ''scripts/docs-build-image.ps1''. Review its container invocation mappings before publishing.'
            SourcePath = 'scripts/docs-build-image.ps1'
            SourceKind = 'Script'
            Parameters = @(
                @{
                    Name = 'Tag'
                    Type = 'String'
                    Mandatory = $false
                    Description = 'Discovered from Tag.'
                }
                @{
                    Name = 'AdditionalTags'
                    Type = 'String[]'
                    Mandatory = $false
                    Description = 'Discovered from AdditionalTags.'
                }
                @{
                    Name = 'Context'
                    Type = 'String'
                    Mandatory = $false
                    Description = 'Discovered from Context.'
                }
                @{
                    Name = 'Dockerfile'
                    Type = 'String'
                    Mandatory = $false
                    Description = 'Discovered from Dockerfile.'
                }
                @{
                    Name = 'Push'
                    Type = 'switch'
                    Mandatory = $false
                    Description = 'Discovered from Push.'
                }
                @{
                    Name = 'Registry'
                    Type = 'String'
                    Mandatory = $false
                    Description = 'Discovered from Registry.'
                }
                @{
                    Name = 'Username'
                    Type = 'String'
                    Mandatory = $false
                    Description = 'Discovered from Username.'
                }
                @{
                    Name = 'Token'
                    Type = 'String'
                    Mandatory = $false
                    Description = 'Discovered from Token.'
                }
            )
        }
        @{
            Id = 'script.scripts.docs-build'
            Name = 'Invoke-DocsBuild'
            Synopsis = 'Runs the discovered PowerShell script ''scripts/docs-build.ps1''.'
            Description = 'Scaffolded from ''scripts/docs-build.ps1''. Review its container invocation mappings before publishing.'
            SourcePath = 'scripts/docs-build.ps1'
            SourceKind = 'Script'
            Parameters = @(
                @{
                    Name = 'SourceDocs'
                    Type = 'String'
                    Mandatory = $false
                    Description = 'Discovered from SourceDocs.'
                }
                @{
                    Name = 'TemplateDir'
                    Type = 'String'
                    Mandatory = $false
                    Description = 'Discovered from TemplateDir.'
                }
                @{
                    Name = 'OutputPath'
                    Type = 'String'
                    Mandatory = $false
                    Description = 'Discovered from OutputPath.'
                }
            )
        }
        @{
            Id = 'script.scripts.preview-docs'
            Name = 'Invoke-PreviewDocs'
            Synopsis = 'Runs the discovered PowerShell script ''scripts/preview-docs.ps1''.'
            Description = 'Scaffolded from ''scripts/preview-docs.ps1''. Review its container invocation mappings before publishing.'
            SourcePath = 'scripts/preview-docs.ps1'
            SourceKind = 'Script'
            Parameters = @(
                @{
                    Name = 'Port'
                    Type = 'Int32'
                    Mandatory = $false
                    Description = 'Discovered from Port.'
                }
                @{
                    Name = 'Tag'
                    Type = 'String'
                    Mandatory = $false
                    Description = 'Discovered from Tag.'
                }
                @{
                    Name = 'ProjectDir'
                    Type = 'String'
                    Mandatory = $false
                    Description = 'Discovered from ProjectDir.'
                }
            )
        }
        @{
            Id = 'script.scripts.setup-docs-workflow'
            Name = 'Invoke-SetupDocsWorkflow'
            Synopsis = 'Runs the discovered PowerShell script ''scripts/setup-docs-workflow.ps1''.'
            Description = 'Scaffolded from ''scripts/setup-docs-workflow.ps1''. Review its container invocation mappings before publishing.'
            SourcePath = 'scripts/setup-docs-workflow.ps1'
            SourceKind = 'Script'
            Parameters = @(
                @{
                    Name = 'CallerProjectDir'
                    Type = 'String'
                    Mandatory = $false
                    Description = 'Discovered from CallerProjectDir.'
                }
                @{
                    Name = 'TargetRelativeDir'
                    Type = 'String'
                    Mandatory = $false
                    Description = 'Discovered from TargetRelativeDir.'
                }
                @{
                    Name = 'BaseImage'
                    Type = 'String'
                    Mandatory = $false
                    Description = 'Discovered from BaseImage.'
                }
                @{
                    Name = 'SkipGate'
                    Type = 'switch'
                    Mandatory = $false
                    Description = 'Discovered from SkipGate.'
                }
                @{
                    Name = 'Overwrite'
                    Type = 'switch'
                    Mandatory = $false
                    Description = 'Discovered from Overwrite.'
                }
            )
        }
        @{
            Id = 'script.scripts.setup-docs'
            Name = 'Invoke-SetupDocs'
            Synopsis = 'Runs the discovered PowerShell script ''scripts/setup-docs.ps1''.'
            Description = 'Scaffolded from ''scripts/setup-docs.ps1''. Review its container invocation mappings before publishing.'
            SourcePath = 'scripts/setup-docs.ps1'
            SourceKind = 'Script'
            Parameters = @(
                @{
                    Name = 'ProjectDir'
                    Type = 'String'
                    Mandatory = $false
                    Description = 'Discovered from ProjectDir.'
                }
                @{
                    Name = 'Title'
                    Type = 'String'
                    Mandatory = $false
                    Description = 'Discovered from Title.'
                }
                @{
                    Name = 'Description'
                    Type = 'String'
                    Mandatory = $false
                    Description = 'Discovered from Description.'
                }
                @{
                    Name = 'SiteUrl'
                    Type = 'String'
                    Mandatory = $false
                    Description = 'Discovered from SiteUrl.'
                }
                @{
                    Name = 'ScriptDir'
                    Type = 'String'
                    Mandatory = $false
                    Description = 'Discovered from ScriptDir.'
                }
                @{
                    Name = 'ConfigDir'
                    Type = 'String'
                    Mandatory = $false
                    Description = 'Discovered from ConfigDir.'
                }
                @{
                    Name = 'BaseImage'
                    Type = 'String'
                    Mandatory = $false
                    Description = 'Discovered from BaseImage.'
                }
                @{
                    Name = 'RouteBasePath'
                    Type = 'String'
                    Mandatory = $false
                    Description = 'Where documentation is served, written to routeBasePath in the installed config. Defaults to the site root.'
                }
                @{
                    Name = 'NoHomepage'
                    Type = 'switch'
                    Mandatory = $false
                    Description = 'Discovered from NoHomepage.'
                }
                @{
                    Name = 'SkipWorkflow'
                    Type = 'switch'
                    Mandatory = $false
                    Description = 'Discovered from SkipWorkflow.'
                }
                @{
                    Name = 'SkipGate'
                    Type = 'switch'
                    Mandatory = $false
                    Description = 'Discovered from SkipGate.'
                }
                @{
                    Name = 'WorkflowsOnly'
                    Type = 'switch'
                    Mandatory = $false
                    Description = 'Discovered from WorkflowsOnly.'
                }
                @{
                    Name = 'WorkflowDir'
                    Type = 'String'
                    Mandatory = $false
                    Description = 'Discovered from WorkflowDir.'
                }
                @{
                    Name = 'Overwrite'
                    Type = 'switch'
                    Mandatory = $false
                    Description = 'Discovered from Overwrite.'
                }
            )
        }
    )
}
