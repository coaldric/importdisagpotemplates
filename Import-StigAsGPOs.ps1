<#
.SYNOPSIS
    Import GPOs from DISA for STIG compliance. 
.DESCRIPTION
    Import GPOs, WMI Filters, and Administrative Templates from DISA for STIG compliance. 
.PARAMETER CompressedZip
    This is the file path of the compressed zip file downloaded from cyber.mil/stigs/gpo.
.PARAMETER STIGPath
    This symbolic link will target the extracted files from the zip.
.NOTES
    Author: Coaldric 2/4/2020
    Collaborators: JBear 5/24/2018 - Created the original script Import-STIGgpo (https://github.com/Average-Bear/Import-STIGgpo)
                   Joe Prox 7/15/2013 - Created the function New-SymLink (https://gallery.technet.microsoft.com/scriptcenter/New-SymLink-60d2531e)
                   Jake Dean 2/4/2020 - Assisted with troubleshooting
                   Tim Medina 2/4/2020 - Assisted with troubleshooting
                   Dan Zinger 2/4/2020 - Assisted with troubleshooting
    Change Log:    
    Removed Migration Table and Backup Support. 
    Added function to create symbolic link without calling mklink.exe (function created by Boe Prox)     
    Added function to select zip file and extract it. Then create a symbolic link to the extracted files which shortens the paths and avoids errors due to paths exceeding maximums.
    Added function to stage SYSVOL by copying Administrative Templats from the local repo (C:\Windows\PolicyDefinitions) and the Administrative Templates extracted from the zip to the SYSVOL.
    Added function to import WMI Filters from extracted files. 
    Upcoming Changes
    Would like to add more info so the user can see what's being imported in each stage and if everything was successful. 
    Would like to add try/catch for areas where failures can occur. 
    Paths could be cleaned up a bit, currently using relitave paths in a lot of locations (e.g. $path\..); It works, but it isn't ideal. 
    Could link the WMI Filters to each cooresponding GPO
    Clean up; remove symobolic link/deleted extracted folders 
    Fixed PolicyDefinitions location
    Added check for PowerShell 5.1
    Fixed $STIGPath 
#>

[Cmdletbinding(SupportsShouldProcess)]
param(
    [Parameter(ValueFromPipeline = $true, HelpMessage = "Select Compressed DISA STIGs")]
    [String[]]$compressedzip = $null,

    [Parameter(ValueFromPipeline = $true, HelpMessage = "Enter STIG Directory")]
    [String[]]$STIGPath = "C:\Import-STIGasGPO",

    [Parameter(ValueFromPipeline = $true, HelpMessage = "Enter Desired Domain")]
    [String[]]$Domain = (Get-ADDomainController).Domain
    
)
#transcript for logging purpases
Start-Transcript C:\Import-STIG-Log.txt -Verbose
If ($PSVersionTable.PSVersion.major -ge 5 ) {
    
    Write-Host -ForegroundColor Green "The current PowerShell version is supported."
    }

    Else {
        
        Write-Host -ForegroundColor Yellow "Import-STIGasGPO only supports PowerShell version 5 or higher. Please install WMF 5.1 or higher before continuing. Exiting." 
        Break
        
        }

#prompts user to select the compressed ZIP Path
if ($compressedzip -eq $null) {

    Add-Type -AssemblyName System.Windows.Forms

    $Dialog = New-Object System.Windows.Forms.OpenFileDialog -Property @{
        InitialDirectory = [Environment]::GetFolderPath('Desktop')
        Filter           = 'Compressed (zipped) Folder (*.zip)|*.zip'
        Title            = 'Select the Zip file downloaded from Cyber.Mil'
    }
    $Result = $Dialog.ShowDialog()
    
    if ($Result -eq 'OK') {

        Try {
            
            Expand-Archive -LiteralPath $dialog.FileName -DestinationPath "$STIGPath" -force
            #$STIGPath = "C:\Import-STIGasGPO"
        }
        Catch {

            $compressedzip = $null
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

    $gpoTotal = 0
    Write-Host -ForegroundColor Yellow "`n`nBeginning Group Policy Object Import."
    
    # Import Policy Definitions
    $defaultDefPath = "C:\Windows\PolicyDefinitions\"
    $domainDefPath = "C:\Windows\SYSVOL\sysvol\$domain\policies\PolicyDefinitions"

    if ((test-path $domainDefPath) -eq $false ) {
        Write-Host -ForegroundColor Green "`tCopying Policy Definitions"
        $null = copy-item -path $defaultDefPath -Destination $domainDefPath -Recurse
    
    }

    # Import STIG GPOs
    $StigTypes = Get-ChildItem -Path $STIGPath -Directory | Where-object { $_.name -notlike "ADMX Templates" }

    foreach ($STIGType in $StigTypes ) {
        $gpofiles = (Get-ChildItem -Directory -Path "$($STIGType.fullname)\GPOs\*").FullName
        $wmiFilters = (Get-ChildItem -Path "$($STIGType.fullName)\WMI*\*").FullName
        # $adminTemplates = (Get-ChildItem -Path "$($STIGType.fullName)\..\ADMX*\*\" -Recurse).FullName
        $GpoTotal += $gpofiles.count 

        Write-Host -ForegroundColor Yellow "Importing $($gpofiles.count) Group Policy objects for $($stigType.basename)" 
        
        foreach ($GPO in $gpofiles ) {
            [XML]$XML = (Get-Content $GPO\Backup.xml)
            $GPOName = $((Select-XML -XML $XML -XPath "//*").Node.DisplayName.'#cdata-section')
            #$wmiFilters = (Get-Childitem -Path $GPO\WMI*).FullName
            
            Write-Host -ForegroundColor Yellow "`tImporting $GPOName"

            # Import Group Policy Object
            Write-Host -ForegroundColor Green "`t`tImporting Group Policy Object"
            $null = Import-GPO -Domain $($Domain) -BackupGpoName $GPOName -TargetName $GPOName -Path $GPO\.. -CreateIfNeeded
        }

        foreach ($wmiFilter in $wmiFilters) {
            (Get-Content $WMIFilter) -replace "security.local", "$domain" | Set-Content $WMIFilter 
            (Get-Content $WMIFilter) -replace "gpoimport.local", "$domain" | Set-Content $WMIFilter 

            # Import WMI Filters
            Write-Host -ForegroundColor Green "`t`tImporting WMI Filters"
            $null = mofcomp -N:root\Policy $WMIFilter
           
        }
        $AdminTypes = Get-ChildItem -Path $STIGPath -Directory | Where-object { $_.name -like "ADMX Templates" }
    
        foreach ($AdminType in $AdminTypes) {
            $adminTemplates = (Get-ChildItem -Path "$($AdminType.fullName)\*\" -Recurse).FullName
            
            # Import Administrative Templates
            Write-Host -ForegroundColor Green "`t`tImporting Administrative Template Files."
        
            foreach ($adminTemplate in $adminTemplates ) {

                $null = Copy-Item -Path "$adminTemplate" -Include "*.admx" -Destination "$domainDefPath"
                $null = Copy-Item -Path "$adminTemplate"-include "*.adml" -Destination "$domainDefPath\en-us"
            }
        
        }
    }
       

    Write-Host -ForegroundColor Green "`n`nGroup Policy Import Complete!"
    Write-Host -ForegroundColor Green "Total GPOs Imported - $GpoTotal"
    Write-Host -ForegroundColor yellow "Performing Final Cleanup Actions: Removing all items stored under $STIGPath"        
}

#Calls functions; Import-STIGasGPO supports -WhatIf
Import-STIGasGPO
remove-item $STIGPath -Recurse
Stop-Transcript
Pause
clear-host
