function Get-CurrentDirectory
{
  $thisName = $MyInvocation.MyCommand.Name
  [IO.Path]::GetDirectoryName((Get-Content function:$thisName).File)
}

Import-Module (Join-Path (Get-CurrentDirectory) 'general.psm1') -DisableNameChecking



 Describe "Strip-Non-AlphaNumeric-Chars"  {

        Context "Valid Input"  {             
            It "Should Only strip invalid characters" {
                Strip-Non-AlphaNumeric-Chars '' | Should Be ''
                Strip-Non-AlphaNumeric-Chars 'a^%-/b' | Should Be 'ab'
                Strip-Non-AlphaNumeric-Chars 'abcd123' | Should Be 'abcd123'
            }   
        }
    }