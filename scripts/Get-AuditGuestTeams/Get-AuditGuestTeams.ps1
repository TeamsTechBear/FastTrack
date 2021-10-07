﻿<#
.Description
This Script function will create a report that will help IT PROs to Monitor and Audit Guest users. The report generated by the script will show the following details:
1. How many Microsoft 365 Groups contains Guest accounts added as member and to list those Guest accounts and corresponding Group;
2. Sign-in logs in Azure Active Directory - Audits if the Guest accounts already Sign-in in the tenant, if the Guest user accepted the invite and also the last time they Signd-In in the tenant;
3. List what is the current Azure B2B Collaboration restrictions configured;

Once you run the script, you will get an report in the Shell/screen or you can choose to be exported to an TXT file;

Important Detail: The script will require AzureADPreview module, and it will remove the old modules and install the needed modules;

.Requirements
- This Script function needs AzureADPreview module version "2.0.2.138" or higher installed - the script will install/update it for you;
- If you have AzureAD Module installed, this module must be uninstalled first - the script will uninstall it for you;
- Administrator rights to Install/Uninstall Modules;
- Administrator rights in the tenant to list  Microsoft 365 Groups/Users and Azure Sign-In logs;
- You must set ExecutionPolicy to allow running the script. Example: Set-ExecutionPolicy -ExecutionPolicy Unrestricted

.PARAMETER: "ExportMethod"
- This parameter will define the way the outcome will be displayed: On Screen or saved into the Desktop of the user profile;

.EXAMPLE:
- ".\Get-AuditGuestTeams -ExportMethod onScreen"
- ".\Get-AuditGuestTeams -ExportMethod Report"

.Version: V1.0

.Author: Tiago Roxo

#> 

#FUNCTION PARAMS
param(
	[Parameter(Position=0,ParameterSetName='ExportMethod')]
	[validateset("onScreen","Report")]
	[string] $ExportMethod = "onScreen"
	)

cls

#VARs
$details = @()
$number = 0
$InactiveDays = "30"
$startDate = (Get-Date).AddDays("-$InactiveDays").ToString('yyyy-MM-dd')
$endDate = (Get-Date).ToString('yyyy-MM-dd') 

#Auto Checking/Install/Uninstall/Update Azure AD Modules
Write-Host "Checking if Azure AD Preview Module is installed on the System..." -BackgroundColor White -ForegroundColor Black
try{
    Import-Module AzureAdPreview -ErrorAction Stop
    $moduleVersion = Get-module -Name AzureAdPreview
    if($moduleVersion.Version.ToString() -ge "2.0.2.138"){
    }else{
        Write-Host "Azure AD Preview Module Module not updated. Current Version: " $moduleVersion.Version.ToString() -BackgroundColor Yellow -ForegroundColor Black
        Write-Host "Updating..." -BackgroundColor Yellow -ForegroundColor Black
        Update-Module AzureAdPreview
        $moduleVersion = Get-module -Name AzureAdPreview
    }
    Write-Host "Azure AD Preview Module Module is Installed/Updated. Current Version: "$moduleVersion.Version.ToString() -BackgroundColor Green -ForegroundColor Black
    Write-Host "Connecting now to O365 services..." -BackgroundColor Green -ForegroundColor Black
    try{Connect-AzureAD -Confirm:$False}catch{break}

}catch{
    if(Get-InstalledModule -name "Azuread" -ErrorAction SilentlyContinue){
        Write-Host "We found AzureAD module installed on the system. To install AzureAdPreview Module, we need to uninstall AzureAD Module first." -BackgroundColor Yellow -ForegroundColor Black
        Read-Host "`nPress any key to Uninstall now AzureAd Module or stop the execution of the script now!"
        Get-Package -Name AzureAd -AllVersions | Uninstall-Package | Out-Null
    }
    Write-Host "Azure AD Preview Module Module not Installed on the system. Install the Module before proceed!" -BackgroundColor Red -ForegroundColor Black
    Read-Host "`nPress any key to Install AzureAdPreview Module or stop the execution of the script now!"
    Install-Module AzureADPreview -Confirm:$False -Force
    Import-Module AzureADPreview
    Write-Host "Connecting now to O365 services..." -BackgroundColor Green -ForegroundColor Black
    try{Connect-AzureAD -Confirm:$False}catch{break}
}

#Scan starts here
Write-Host "Loading now Azure Sign-In Logs and O365 Groups/Guests..." -BackgroundColor white -ForegroundColor Black
#Creating a list of Guest Users
$guestUsers = @()
$guestUsers = Get-AzureADUser | Where-Object { $_.UserType -eq 'Guest'}

#Auditing SignIn Log's for the Guest Accounts
$loggedOnUsers = @()
foreach($m in $guestUsers){
    $MAIL = $m.Mail
    $loggedOnUsers += Get-AzureADAuditSignInLogs -top 1000 -Filter "UserPrincipalName eq '$MAIL'"
}

#Creating a list of Microsoft 365 Groups
$M365Groups = @()
$M365Groups = Get-AzureADGroup

#Getting Tenant Details
$tenantName = @()
$tenantName = Get-AzureADTenantDetail

#Creating an List of existing Guest users in the tenant
$CSVGuestUsersAudit = @()
$CSVGuestUsersInGroups = @()

#Getting Tenant Azure B2B Policy
$B2BManagementPolicy =  Get-AzureADPolicy | ? {$_.DisplayName -eq "B2BManagementPolicy" } | Select -ExpandProperty Definition
$BlockedDomains = @()
$AlloweddDomains = @()
try {$BlockedDomains = ($B2BManagementPolicy | ConvertFrom-Json).B2BManagementPolicy.InvitationsAllowedAndBlockedDomainsPolicy.BlockedDomains}catch{}
try {$AlloweddDomains = ($B2BManagementPolicy | ConvertFrom-Json).B2BManagementPolicy.InvitationsAllowedAndBlockedDomainsPolicy.AllowedDomains}catch{}

#List the tenant Details
$details += "`n____________________________________________" 
$details += "`nTenant Details:"
$details += "`nName:     " + $tenantName.DisplayName
$details += "`nTenantId: " + $tenantName.ObjectId
$details += "`n____________________________________________"

#Scan all the Microsoft 365 Groups and the list the guest that are part of the Groups
$details += "`n" + "Microsoft 365 Groups Details:"
$details += "`n" + ($M365Groups).Count + " Microsoft 365 Groups Found in the tenant."

foreach($i in $M365Groups)
{
    $guestuser = @()
    $guestuser = Get-AzureADGroupMember -ObjectId $i.ObjectId -All $true | Where-Object { $_.UserType -eq 'Guest'}
    if ($guestuser)
    {
        $number = $number + 1
    }
}
$details += "`n" + $number + " Microsoft 365 Groups Found in the tenant with Guests invited."
#$details += "`n____________________________________________"
foreach($i in $M365Groups)
{
    $guestUser = Get-AzureADGroupMember -ObjectId $i.ObjectId -All $true | Where-Object { $_.UserType -eq 'Guest'}
    if ($guestUser)
    {
        $details += "`n----------------"
        $details += "`nGroup Name: " + $i.DisplayName
        $details += "`n" + "Group Guest Details: " + ($guestUser).count + " Guest Users Found in the M365 Group"
        foreach($o in $guestUser){
            $auditUser = $loggedOnUsers | where UserPrincipalName -eq $o.mail | select * -First 1
            try {
                $details += "`n-> " + $auditUser.UserDisplayName + " | " + $auditUser.UserPrincipalName + " | " + "Last SignIn Time: " + $auditUser.CreatedDateTime.SubString(0,10)
                $CSVGuestUsersInGroups += New-Object -TypeName psobject -Property @{GroupName=$i.DisplayName; DisplayName=$o.DisplayName; Mail=$o.mail; LastSignInTime=$auditUser.CreatedDateTime.SubString(0,10)}
            }catch{
                $details += "`n-> " + $o.DisplayName + " | " + $o.mail + " | " + "Last SignIn Time: No records found"
                $CSVGuestUsersInGroups += New-Object -TypeName psobject -Property @{GroupName=$i.DisplayName; DisplayName=$o.DisplayName; Mail=$o.mail; LastSignInTime="No records found"}
            }
        }
        #$details += "`n----------------"
    }else{
        #$details += "`n----------------"
        #$details += "`nGroup Name: " + $i.DisplayName 
        #$details += "`n0 Guest users found in the M365 Group" 
    }
}

#Scan/Audit All Guest Users that's never Sign-In and/or that haven't Sign-In for more than $InactiveDays days
$details += "`n____________________________________________"
$details += "`nTotal Guest Users configured in the Tenant: " + ($guestUsers).Count
$details += "`nTenant Guest Users details:"
$details += "`n----------------"
foreach($t in $guestUsers){
    try{
    $newtest = $loggedOnUsers | where UserPrincipalName -eq $t.mail | select createdDateTime -First 1
        
    $newdate =@()
    $newdate = $newtest.CreatedDateTime.SubString(0,10)
    $newdate.ToString("yyyy-MM-dd")
    }catch{}

    if($newtest -eq $null){
        $details += "`n-> [!WARNING]`t " + $t.Displayname + " | " + $t.mail + " | Invite Status: " + $t.UserState + " | Last SignIn Time: No records found | [Possible Stale user]"
        $CSVGuestUsersAudit += New-Object -TypeName psobject -Property @{DisplayName=$t.Displayname; Mail=$t.mail; InviteStatus=$t.UserState ; LastSignInTime="No records found" ; obs= "[Possible Stale user]"}
    }elseif($newdate -le $startDate){
        $details += "`n-> [!WARNING]`t " + $t.Displayname + " | " + $t.mail + " | Invite Status: " + $t.UserState + " | Last SignIn Time: $newdate | [no Sign-In details for more than $InactiveDays days!][Possible Stale user]"
        $CSVGuestUsersAudit += New-Object -TypeName psobject -Property @{DisplayName=$t.Displayname; Mail=$t.mail; State=$t.InviteStatus ; LastSignInTime=$newdate; Obs="[no Sign-In details for more than $InactiveDays days!][Possible Stale user]"}
    }elseif($newtest){
        $details += "`n-> " + $t.Displayname + " | " + $t.mail + " | Invite Status: " + $t.UserState + " | Last SignIn Time: " + $newdate
        $CSVGuestUsersAudit += New-Object -TypeName psobject -Property @{DisplayName=$t.Displayname; Mail=$t.mail; State=$t.InviteStatus ; LastSignInTime=$newdate; Obs=""}
    }
}

#List Azure B2B Collaboration restrictions
$details += "`n----------------"
$details += "`nAzure B2B Collaboration restrictions:"
if ($BlockedDomains -ne $null){
    $details += "`nAzure B2B Policy is configured to 'Deny invitations to the specified domains'."
    $details += "`nAzure B2B Blocked Domains: " + $BlockedDomains

}elseif($AlloweddDomains -ne $null){
    $details += "`nAzure B2B Policy is configured to 'Allow invitations only to the specified domains (most restrictive)'."
    $details += "`nAzure B2B Allowed Domains: " + $AlloweddDomains
}else{
    $details += "`nAzure B2B Policy is configured to 'Allow invitations to be sent to any domain (most inclusive)'."
}
$details += "`n____________________________________________"
$details += "`nReport Generated on: " + (Get-Date)
$details += "`n____________________________________________"

#Export information to the screen or file
if($ExportMethod -eq "onScreen"){
        Write-Host $details 
        Write-Host "If you wish to save the outcome to a file, run the following cmdlet: .\Get-AuditGuestTeams -ExportMethod Report"
}elseif($ExportMethod -eq "Report"){
    $filePath = "$($env:USERPROFILE)\Downloads\"
    $fileName = "ReportAuditGuestTeams_"+ (Get-Date).ToString('yyyy-MM-dd') +".txt"
    $file = $filePath+$fileName
    $details | Out-File -FilePath $file -Force

	
    $filePath = "$($env:USERPROFILE)\Downloads\"
    $fileName = "CSVGuestUsersInGroups_"+ (Get-Date).ToString('yyyy-MM-dd') +".csv"
    $fileCSV1 = $filePath+$fileName
    $CSVGuestUsersInGroups | Select-Object -Property GroupName,DisplayName,Mail,LastSignInTime | Export-Csv -Path $fileCSV1 -NoTypeInformation

    
    $filePath = "$($env:USERPROFILE)\Downloads\"
    $fileName = "CSVGuestUsersAudit_"+ (Get-Date).ToString('yyyy-MM-dd') +".csv"
    $fileCSV2 = $filePath+$fileName
    $CSVGuestUsersAudit | Select-Object -Property DisplayName,Mail,InviteStatus,LastSignInTime,obs | Export-Csv -Path $fileCSV2 -NoTypeInformation

    Write-Host "`nAll 3 files will be stored in the following location:" $filePath -BackgroundColor Green -ForegroundColor Black
    Write-Host "`Opening the files..." -BackgroundColor Green -ForegroundColor Black
    
    start notepad $file
    start excel $fileCSV1
    start excel $fileCSV2

}
Read-Host "Press Enter Exit"
