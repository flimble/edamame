function Get-CurrentDirectory
{
  $thisName = $MyInvocation.MyCommand.Name
  [IO.Path]::GetDirectoryName((Get-Content function:$thisName).File)
}

Import-Module (Join-Path (Get-CurrentDirectory) 'build.psm1') -DisableNameChecking



 Describe "Set-ConfigAppSettings"  {
       $testAppSettings = 'TestDrive:\app.config'

        Context "Valid Input"  {     
             
             $config = @"
<?xml version="1.0"?>
<configuration>
<appSettings>
<add key="aKey" value="aValue" />
</appSettings>
</configuration>
"@
        Set-Content $testAppSettings -value $config 
        Set-ConfigAppSetting $testAppSettings "aKey" "anotherValue"    
        $result = Get-Content $testAppSettings

        [string] $expected = @"
<?xml version="1.0"?>
<configuration>
<appSettings>
<add key="aKey" value="anotherValue" />
</appSettings>
</configuration>
"@
            It "Should Only strip invalid characters" {
                ($result -ieq $expected) | Should Be $true
            }   
        }

        Context "Key Not Found" {
            Set-Content $testAppSettings -value '<?xml version="1.0"?><configuration></configuration>'
            
            

            It "Should Throw Exception" {
                { Set-ConfigAppSetting $testAppSettings "aKey" "anotherValue" }  | Should Throw

            }

        }
    }