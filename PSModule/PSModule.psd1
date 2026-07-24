@{
    Id = 'repository.docusaurustemplate'
    GeneratedBy = 'SubZeroDev.ContainerPSGenerator'
    ModuleName = 'DocusaurusTemplate'
    ModuleVersion = '0.1.0'
    ContainerImage = 'DocusaurusTemplate'
    Commands = @(
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
            )
        }
    )
}
