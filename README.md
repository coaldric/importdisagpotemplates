Import-STIGasGPOs

The script provided here is not supported under any Microsoft standard support program or service. All scripts are provided
AS IS without warranty of any kind. Microsoft further disclaims all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose. The entire risk arising out of the use or performance of the sample scripts and documentation remains with you. In no event shall Microsoft, its authors, or anyone else involved in the creation, production, or delivery of the scripts be liable for any damages whatsoever (including, without limitation, damages for loss of business profits,  business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability to use the sample scripts or documentation, even if Microsoft has been advised of the possibility of such damages.

This script is intended to be run into a green field environment. If you already have a well established environment, use with extreme caution. 

This script will take the zip file downloaded from cyber.mil/stigs/gpo and import the GPOs and WMI Filters into your environment. It will also copy the ADMX/ADML files from the extracted files to your SYSVOL Policy Definitions folder as well as copy the local Policy Definitions folder to SYSVOL (C:\Windows\PolicyDefinitions). 

Simply run the script and select the zip file. 
