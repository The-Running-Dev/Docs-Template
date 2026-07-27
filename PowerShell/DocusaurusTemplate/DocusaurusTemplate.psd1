@{
    RootModule        = 'DocusaurusTemplate.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b3e6b3a0-6d2e-4f5b-9e8a-6f7c9d2e1a4b'
    Author            = 'The Running Dev'
    CompanyName       = 'The Running Dev'
    Description       = 'In-container commands for the docs-template image: install the ' +
                         'documentation system into a mounted project, and build a ' +
                         'Docusaurus site from it. Hand-authored -- unrelated to ' +
                         'PSModule/PSModule.psd1, which is generator input for ' +
                         'SubZeroDev.ContainerPSGenerator and is not itself importable.'
    PowerShellVersion = '7.4'

    FunctionsToExport = @('Invoke-SetupDocs', 'Invoke-DocsBuild')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            ProjectUri = 'https://github.com/The-Running-Dev/Docusaurus-Template'
            LicenseUri = 'https://github.com/The-Running-Dev/Docusaurus-Template/blob/main/LICENSE'
            Tags       = @('Docusaurus', 'Documentation', 'Docker')
        }
    }
}
