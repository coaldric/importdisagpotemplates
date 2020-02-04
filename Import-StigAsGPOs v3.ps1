<#
.SYNOPSIS
    Import GPOs from DISA for STIG compliance. 

.DESCRIPTION
    Import GPOs, WMI Filters, and Administrative Templates from DISA for STIG compliance. 

.PARAMETER STIGPath
    Parent STIG directory (e.g. C:\STIGS\January); This is the directory that hosts all of the DoD...v1r2 folders (DoD Google Chrome v1r18, DoD Internet Explorer 11 v1r18, etc)
    Important note! The extracted zip file from DISA causes issues due to the file names being to long. To avoid this, rename or move the folders to keep the paths short. 
    Instead of using the default extraction (C:\Users\Administrator\Desktop\U_STIG_GPO_Package_January_2020\January 2020 DISA STIG GPO Package 0129)
    Move and rename 'January 2020 DISA STIG GPO Package 0129' to C:\January. Then you would select C:\January as your STIGPath. 

.NOTES
    Author: JBear 5/24/2018
    Re-write: Coaldric 2/4/2020
        Removed Migration Table and Backup Support. 
        Simplifying for use of importing from DISA STIG templates in a new environment. 
         
#>

[Cmdletbinding(SupportsShouldProcess)]
param(

    [Parameter(ValueFromPipeline=$true,HelpMessage="Enter STIG Directory")]
    [String[]]$STIGPath = $null,

    [Parameter(ValueFromPipeline=$true,HelpMessage="Enter Desired Domain")]
    [String[]]$Domain = (Get-ADDomainController).Domain
    
)
#transcript for logging purpases
Start-Transcript $STIGPath\log.txt -Verbose

#prompts user to select the STIG Path
if($STIGPath -eq $null) {

    Add-Type -AssemblyName System.Windows.Forms

    $Dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $Result = $Dialog.ShowDialog((New-Object System.Windows.Forms.Form -Property @{ TopMost = $true }))

    if($Result -eq 'OK') {

        Try {
      
            $STIGPath = $Dialog.SelectedPath
        }

        Catch {

            $STIGPath = $null
	        Break
        }
    }

    else {

        #Shows upon cancellation of Save Menu
        Write-Host -ForegroundColor Yellow "Notice: No file(s) selected."
        Break
    }
}

#Imports the GPOs
function Import-STIGasGPO {
[Cmdletbinding(SupportsShouldProcess)]
Param()

    foreach($Path in $STIGPath) {

        $BaseFile = (Get-ChildItem -Path $path\DoD*\GPOs\*).FullName
                                
            }

            foreach($Base in $BaseFile) {
    
                [XML]$XML = (Get-Content $Base\Backup.xml)
                $GPOName = $((Select-XML -XML $XML -XPath "//*").Node.DisplayName.'#cdata-section')
                Import-GPO -Domain $($Domain) -BackupGpoName $GPOName -TargetName $GPOName -Path $base\..\ -CreateIfNeeded
    }
}

#imports the WMI Filters (does not link them to GPOs)
function Import-STIGWMIFilters {
[Cmdletbinding(SupportsShouldProcess)]
Param()

    foreach($Path in $STIGPath) {

        $WMIFilters = (Get-ChildItem -Path $path\DoD*\WMI*\*).FullName
                                
            }

            foreach($WMIFilter in $WMIFilters) {
                #the .mofs from DISA need to be editted before being able to import them
                (Get-Content $WMIFilter) -replace "security.local", "$domain" | Set-Content $WMIFilter 
                (Get-Content $WMIFilter) -replace "gpoimport.local", "$domain" | Set-Content $WMIFilter 
                #now all the .mofs will have the local domain info and will load properly
                mofcomp -N:root\Policy $WMIFilter
    }
}

#Stages the SYSVOL PolicyDefinitions folder with ADMXs and ADMLs from local C:\Windows and the DISA
function Copy-AdministrativeTemplates {
[Cmdletbinding(SupportsShouldProcess)]
Param()
    #copy local PolicyDefinitions to SYSVOL
    copy-item -path C:\Windows\PolicyDefinitions\ -Destination C:\Windows\SYSVOL\sysvol\contoso.com\PolicyDefinitions -Recurse

    foreach($Path in $STIGPath) {

        $adminfiles = (Get-ChildItem -Path $path\ADMX*\*\ -Recurse).FullName
                                
            }

            foreach($admin in $adminFiles) {
                #copy DISA ADMX/ADML files to SYSVOL           
                Copy-Item -Path $admin -Include "*.admx" -Destination C:\Windows\SYSVOL\sysvol\contoso.com\PolicyDefinitions 
                Copy-Item -Path $admin -include "*.adml" -Destination C:\Windows\SYSVOL\sysvol\contoso.com\PolicyDefinitions\en-us 
               
    }
}

<# Write-hosts for each GPO imported
foreach($base in $basefile) {

    $STIGImport = "Importing: $(Split-Path $base\..\..\ -Leaf)"

    if(!([String]::IsNullOrWhiteSpace($MigrationTablePath))) {
    
        $MigrationFiles = "| Using $MigrationTablePath"
    }

    Write-Host -ForegroundColor Yellow "`n$STIGImport $MigrationFiles"
}
#>

#Calls functions; Import-STIGasGPO supports -WhatIf
Import-STIGasGPO
Import-STIGWMIFilters
Copy-AdministrativeTemplates 
Stop-Transcript
