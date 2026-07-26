@{
    Id = 'repository.docusaurustemplate'
    GeneratedBy = 'SubZeroDev.ContainerPSGenerator'
    ModuleName = 'DocusaurusTemplate'
    ModuleVersion = '0.1.0'
    ContainerImage = 'DocusaurusTemplate'
    Commands = @(
@{
            Id = 'script.scripts.preview-docs'
            Name = 'Invoke-PreviewDocs'
            Synopsis = 'Runs the discovered PowerShell script ''scripts/preview-docs.ps1''.'
            Description = 'Scaffolded from ''scripts/preview-docs.ps1''. Review its container invocation mappings before publishing.'
            SourcePath = 'scripts/preview-docs.ps1'
            SourceKind = 'Script'
            Parameters = @(
@{
                    Name = 'Live'
                    Type = 'switch'
                    Mandatory = $false
                    Description = 'Discovered from Live.'
                }
@{
                    Name = 'BuildOnly'
                    Type = 'switch'
                    Mandatory = $false
                    Description = 'Discovered from BuildOnly.'
                }
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
                    Name = 'BaseImage'
                    Type = 'String'
                    Mandatory = $false
                    Description = 'Discovered from BaseImage.'
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
                    Name = 'TargetFileName'
                    Type = 'String'
                    Mandatory = $false
                    Description = 'Discovered from TargetFileName.'
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
            Id = 'script.scripts.invoke-setupdocs'
            Name = 'Invoke-SetupDocs'
            Synopsis = 'Runs the discovered PowerShell script ''scripts/Invoke-SetupDocs.ps1''.'
            Description = 'Scaffolded from ''scripts/Invoke-SetupDocs.ps1''. Review its container invocation mappings before publishing.'
            SourcePath = 'scripts/Invoke-SetupDocs.ps1'
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
                    Name = 'Overwrite'
                    Type = 'switch'
                    Mandatory = $false
                    Description = 'Discovered from Overwrite.'
                }
            )
        }
    )
}
