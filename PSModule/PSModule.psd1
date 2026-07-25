@{
    Id = 'repository.docusaurustemplate'
    GeneratedBy = 'SubZeroDev.ContainerPSGenerator'
    ModuleName = 'DocusaurusTemplate'
    ModuleVersion = '2026.07.25'
    ContainerImage = 'DocusaurusTemplate'
    Commands = @(
@{
            Id = 'script.scripts.docs'
            Name = 'Invoke-Docs'
            Synopsis = 'Runs the discovered PowerShell script ''scripts/docs.ps1''.'
            Description = 'Scaffolded from ''scripts/docs.ps1''. Review its container invocation mappings before publishing.'
            SourcePath = 'scripts/docs.ps1'
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
                    Name = 'DockerDocs'
                    Type = 'switch'
                    Mandatory = $false
                    Description = 'Discovered from DockerDocs.'
                }
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
    )
}
