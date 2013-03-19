cd %~dp0

.nuget\nuget.exe install .nuget\packages.config -OutputDirectory "packages"

powershell import-module '%~dp0packages\Pester.2.0.1\tools\Pester.psm1'; get-module; invoke-pester scripts -OutputXml TestResults.xml
