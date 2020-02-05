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
    Added function to create symbolic link without calling mklink.exe (function created by Boe Prox)     
#>

[Cmdletbinding(SupportsShouldProcess)]
param(
    [Parameter(ValueFromPipeline = $true, HelpMessage = "Select Compressed DISA STIGs")]
    [String[]]$compressedzip = $null,

    [Parameter(ValueFromPipeline = $true, HelpMessage = "Enter STIG Directory")]
    [String[]]$STIGPath = "C:\ExtractedSTIGs",

    [Parameter(ValueFromPipeline = $true, HelpMessage = "Enter Desired Domain")]
    [String[]]$Domain = (Get-ADDomainController).Domain
    
)
#transcript for logging purpases
#Start-Transcript C:\log.txt -Verbose

Function New-SymLink {
    <#
        .SYNOPSIS
            Creates a Symbolic link to a file or directory

        .DESCRIPTION
            Creates a Symbolic link to a file or directory as an alternative to mklink.exe

        .PARAMETER Path
            Name of the path that you will reference with a symbolic link.

        .PARAMETER SymName
            Name of the symbolic link to create. Can be a full path/unc or just the name.
            If only a name is given, the symbolic link will be created on the current directory that the
            function is being run on.

        .PARAMETER File
            Create a file symbolic link

        .PARAMETER Directory
            Create a directory symbolic link

        .NOTES
            Name: New-SymLink
            Author: Boe Prox
            Created: 15 Jul 2013


        .EXAMPLE
            New-SymLink -Path "C:\users\admin\downloads" -SymName "C:\users\admin\desktop\downloads" -Directory

            SymLink                          Target                   Type
            -------                          ------                   ----
            C:\Users\admin\Desktop\Downloads C:\Users\admin\Downloads Directory

            Description
            -----------
            Creates a symbolic link to downloads folder that resides on C:\users\admin\desktop.

        .EXAMPLE
            New-SymLink -Path "C:\users\admin\downloads\document.txt" -SymName "SomeDocument" -File

            SymLink                             Target                                Type
            -------                             ------                                ----
            C:\users\admin\desktop\SomeDocument C:\users\admin\downloads\document.txt File

            Description
            -----------
            Creates a symbolic link to document.txt file under the current directory called SomeDocument.
    #>
    [cmdletbinding(
        DefaultParameterSetName = 'Directory',
        SupportsShouldProcess = $True
    )]
    Param (
        [parameter(Position = 0, ParameterSetName = 'Directory', ValueFromPipeline = $True,
            ValueFromPipelineByPropertyName = $True, Mandatory = $True)]
        [parameter(Position = 0, ParameterSetName = 'File', ValueFromPipeline = $True,
            ValueFromPipelineByPropertyName = $True, Mandatory = $True)]
        [ValidateScript( {
                If (Test-Path $_) { $True } Else {
                    Throw "`'$_`' doesn't exist!"
                }
            })]
        [string]$Path,
        [parameter(Position = 1, ParameterSetName = 'Directory')]
        [parameter(Position = 1, ParameterSetName = 'File')]
        [string]$SymName,
        [parameter(Position = 2, ParameterSetName = 'File')]
        [switch]$File,
        [parameter(Position = 2, ParameterSetName = 'Directory')]
        [switch]$Directory
    )
    Begin {
        Try {
            $null = [mklink.symlink]
        }
        Catch {
            Add-Type @"
            using System;
            using System.Runtime.InteropServices;
 
            namespace mklink
            {
                public class symlink
                {
                    [DllImport("kernel32.dll")]
                    public static extern bool CreateSymbolicLink(string lpSymlinkFileName, string lpTargetFileName, int dwFlags);
                }
            }
"@
        }
    }
    Process {
        #Assume target Symlink is on current directory if not giving full path or UNC
        If ($SymName -notmatch "^(?:[a-z]:\\)|(?:\\\\\w+\\[a-z]\$)") {
            $SymName = "{0}\{1}" -f $pwd, $SymName
        }
        $Flag = @{
            File      = 0
            Directory = 1
        }
        If ($PScmdlet.ShouldProcess($Path, 'Create Symbolic Link')) {
            Try {
                $return = [mklink.symlink]::CreateSymbolicLink($SymName, $Path, $Flag[$PScmdlet.ParameterSetName])
                If ($return) {
                    $object = New-Object PSObject -Property @{
                        SymLink = $SymName
                        Target  = $Path
                        Type    = $PScmdlet.ParameterSetName
                    }
                    $object.pstypenames.insert(0, 'System.File.SymbolicLink')
                    $object
                }
                Else {
                    Throw "Unable to create symbolic link!"
                }
            }
            Catch {
                Write-warning ("{0}: {1}" -f $path, $_.Exception.Message)
            }
        }
    }
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
      
            Expand-Archive -LiteralPath $dialog.FileName -DestinationPath "C:\" -force
            $extractedzip = (Get-ChildItem -Path C:\*DISA*STIG*GPO*\).FullName
            New-SymLink -Path "$extractedzip" -SymName "$STIGPath" -Directory
            
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

    foreach ($STIG in $STIGPath) {

        $BaseFile = (Get-ChildItem -Directory -Path $STIG\DoD*\GPOs\*).FullName
                                
    }

    foreach ($Base in $BaseFile) {
    
        [XML]$XML = (Get-Content $Base\Backup.xml)
        $GPOName = $((Select-XML -XML $XML -XPath "//*").Node.DisplayName.'#cdata-section')
        Import-GPO -Domain $($Domain) -BackupGpoName $GPOName -TargetName $GPOName -Path $base\.. -CreateIfNeeded
    }
}

#imports the WMI Filters (does not link them to GPOs)
function Import-STIGWMIFilters {
    [Cmdletbinding(SupportsShouldProcess)]
    Param()

    foreach ($STIG in $STIGPath) {

        $WMIFilters = (Get-ChildItem -Path $STIG\DoD*\WMI*\*).FullName
                                
    }

    foreach ($WMIFilter in $WMIFilters) {
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

    foreach ($STIG in $STIGPath) {

        $adminfiles = (Get-ChildItem -Path $STIG\ADMX*\*\ -Recurse).FullName
                                
    }

    foreach ($admin in $adminFiles) {
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
#Stop-Transcript
