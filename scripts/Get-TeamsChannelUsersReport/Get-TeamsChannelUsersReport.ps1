<#

Get-TeamsChannelUsersReport.ps1 PowerShell script | Version 0.9

by David.Whitney@microsoft.com

THIS CODE AND ANY ASSOCIATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR
PURPOSE. THE ENTIRE RISK OF USE, INABILITY TO USE, OR RESULTS FROM THE USE OF THIS CODE REMAINS WITH THE USER.

#>

<#
.SYNOPSIS
    Generate a report of channel user roles across teams
.DESCRIPTION
    Create a CSV file output that contains a row for each user that has a role in each channel of each or specified teams
.EXAMPLE
    .\Get-TeamsChannelUsersReport.ps1 -ExportCSVFilePath "C:\path\to\export.csv"

    Report on all teams
.EXAMPLE
    .\Get-TeamsChannelUsersReport.ps1 -GroupId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -ExportCSVFilePath C:\path\to\export.csv

    Report on a specific team by its group ID
.EXAMPLE
    .\Get-TeamsChannelUsersReport.ps1 -UserId "user@domain.com" -ExportCSVFilePath C:\path\to\export.csv

    Report on teams that the specified user is a member or owner of
.OUTPUTS
    Writes out a CSV file report with columns:
    - Team Name
    - Group ID
    - Team Description
    - Team Privacy
    - Team Is Archived
    - Team Classification
    - Team Sensitivity Label
    - Channel Name
    - Channel Membership Type
    - Channel Description
    - Channel Member Name
    - Channel Member Role
    - Channel Member User ID
    - Channel Member Email
#>
[CmdletBinding()]
param (
    # Path to where to save the report export CSV file
    [Parameter(
        Mandatory = $true,
        Position = 0)]
    [System.IO.FileInfo]
    $ExportCSVFilePath,

    # Provide specific group ID to only report on that team
    [Parameter(Mandatory = $false)]
    [Alias("TeamID")]
    [string]
    $GroupID,

    # Provide specific user ID to only report on the teams that user is a member or owner of
    [Parameter(Mandatory = $false)]
    [string]
    $UserID
)

if ($GroupID -and $UserID) {
    Write-Warning "Group ID and User ID both provided - ignoring User ID"
}

$MgModuleAuth  = Get-Module -Name "Microsoft.Graph.Authentication" -ListAvailable
$MgModuleGroup = Get-Module -Name "Microsoft.Graph.Groups"         -ListAvailable
$MgModuleUsers = Get-Module -Name "Microsoft.Graph.Users"          -ListAvailable
$MgModuleTeams = Get-Module -Name "Microsoft.Graph.Teams"          -ListAvailable
if (-not ($MgModuleGroup -and $MgModuleUsers -and $MgModuleTeams -and $MgModuleAuth)) {
    throw "This script requires the Microsoft.Graph (PowerShell SDK for Graph) module - use 'Install-Module Microsoft.Graph' from an elevated PowerShell session, restart this PowerShell session, then try again."
}
Import-Module Microsoft.Graph.Authentication -WarningAction SilentlyContinue -ErrorAction Stop
Import-Module Microsoft.Graph.Groups         -WarningAction SilentlyContinue -ErrorAction Stop
Import-Module Microsoft.Graph.Users          -WarningAction SilentlyContinue -ErrorAction Stop
Import-Module Microsoft.Graph.Teams          -WarningAction SilentlyContinue -ErrorAction Stop

# Connect to Graph interactively (delegated permissions) with minimum required Read permission scopes
Connect-Graph -Scopes "Group.Read.All", "User.Read.All", "TeamMember.Read.All", "Channel.ReadBasic.All", "ChannelMember.Read.All"

Write-Output "Gathering Teams data..."

if ($GroupID) {
    Write-Progress -Id 1 -Activity "Gathering Teams Data" -Status "Getting group ID $GroupID"
    #ask for assignedLabels in this call for the requested group since we can't ask for it when calling for the team
    $M365GroupIdWithProvisioning = Get-MgGroup -GroupId $GroupID -Property Id, DisplayName, Mail, resourceProvisioningOptions, assignedLabels -ErrorAction Stop
    if ($M365GroupIdWithProvisioning) {
        $M365GroupThatIsTeam = $M365GroupIdWithProvisioning | Where-Object {$_.AdditionalProperties.resourceProvisioningOptions -contains "Team"}
        if ($M365GroupThatIsTeam) {
            Write-Output "Found team $($M365GroupThatIsTeam.DisplayName) ($GroupID)"
            $M365GroupsThatAreTeams = @($M365GroupThatIsTeam)
        } else {
            throw "Group $($M365GroupIdWithProvisioning.DisplayName) ($GroupID) is not a Teams-enabled group"
        }
    }
} elseif ($UserID) {
    Write-Progress -Id 1 -Activity "Gathering Teams Data" -Status "Getting groups for user ID $UserID"
    $User = Get-MgUser -UserId $UserID -ErrorAction Stop
    Write-Output "Found user $($User.DisplayName) ($UserID)"
    Write-Progress -Id 1 -Activity "Gathering Teams Data" -Status "Getting groups for user ID $UserID - $($User.DisplayName)"
    if ($User) {
        $UserMemberOfIdsWithProvisioning = Get-MgUserMemberOf -UserId $UserID -Property displayName, Id, resourceProvisioningOptions, assignedLabels
        # MemberOf call returns directory roles as well (e.g. Teams Administrator), need to filter to just groups
        $UserGroupIdsWithProvisioning = $UserMemberOfIdsWithProvisioning | Where-Object {$_.AdditionalProperties."@odata.type" -eq "#microsoft.graph.group"}
        $M365GroupsThatAreTeams = @($UserGroupIdsWithProvisioning | Where-Object {$_.AdditionalProperties.resourceProvisioningOptions -contains "Team"})
        # Add displayname to root of object as return from member of sticks displayName into the AdditionalProperties, where normal Get-MgGroup has it at root of return object
        $M365GroupsThatAreTeams | ForEach-Object {$_ | Add-Member -NotePropertyName "DisplayName" -NotePropertyValue $_.AdditionalProperties.displayName}
        if (!$M365GroupsThatAreTeams) {
            Write-Warning "User $($User.DisplayName) ($UserID) is not a member of any teams"
            Write-Progress -Id 1 -Activity "Gathering Teams Data" -Completed
            exit
        }
        Write-Output "Found $($M365GroupsThatAreTeams.count) teams user is a member of"
    }
} else {
    Write-Progress -Id 1 -Activity "Gathering Teams Data" -Status "Getting list of M365 Groups"
    #ask for assignedLabels in this call for groups since we can't ask for it when calling for the team
    $M365GroupIdsWithProvisioning = Get-MgGroup -Filter "groupTypes/any(c:c eq 'Unified')" -Property Id, DisplayName, Mail, resourceProvisioningOptions, assignedLabels
    $M365GroupsThatAreTeams = $M365GroupIdsWithProvisioning | Where-Object {$_.AdditionalProperties.resourceProvisioningOptions -contains "Team"}
    Write-Output "Found $($M365GroupsThatAreTeams.count) teams"
}

Write-Progress -Id 1 -Activity "Gathering Teams Data" -Status "Getting Teams properties"
$n = 1
$total = $M365GroupsThatAreTeams.count
$ReportOutput = foreach ($group in $M365GroupsThatAreTeams) {
    Write-Progress -Id 1 -Activity "Gathering Teams Data" -Status "Getting team properties" -CurrentOperation "$n of $total - $($group.DisplayName)" -PercentComplete (100 * $n / $total)
    $team = Get-MgTeam -TeamId $group.Id -Property Id, DisplayName, Description, Visibility, IsArchived, Classification
    # strip out unneeded fields in Get-MgTeam return so that we can add our own Channels and Members properties, since the return doesn't include that data
    $team = $team | Select-Object Id, DisplayName, Description, Visibility, IsArchived, Classification
    # add sensitivity label that we got from first call to get M365 Groups, since asking for assignedLabels is not supported for getting the team
    if ($group.AssignedLabels) {
        $team | Add-Member -NotePropertyName "AssignedLabel" -NotePropertyValue $group.AssignedLabels[0].DisplayName
    } else {
        $team | Add-Member -NotePropertyName "AssignedLabel" -NotePropertyValue ""
    }

    $teamMembers = Get-MgTeamMember -TeamId $team.Id
    [PSCustomObject[]]$teamMembersReturn = foreach ($member in $teamMembers) {
        [PSCustomObject]@{
            "Role" = if ($member.Roles) {$member.Roles -join ","} else {"member"};
            "DisplayName" = $member.DisplayName;
            "Mail" = $member.AdditionalProperties.email;
            "Id" = $member.AdditionalProperties.userId;
        }
    }
    $team | Add-Member -NotePropertyName "Members" -NotePropertyValue $teamMembersReturn

    $channelsList = Get-MgTeamChannel -TeamId $team.Id -Property Id, DisplayName, Description, MembershipType
    # strip out unneeded fields in Get-MgTeamChannel return so that we can add our own Members property, since the return doesn't include that data
    $channelsList = $channelsList | Select-Object Id, DisplayName, Description, MembershipType
    [PSCustomObject[]]$channelsReturn = foreach ($channel in $channelsList) {
        if ($channel.MembershipType -ne "standard") {
            $nonStandardChannelMembers = Get-MgTeamChannelMember -TeamId $team.Id -ChannelId $channel.Id
            $nonStandardChannelMembersObject = foreach ($member in $nonStandardChannelMembers) {
                [PSCustomObject]@{
                    "Role" = if ($member.Roles) {$member.Roles -join ","} else {"member"};
                    "DisplayName" = $member.DisplayName;
                    "Mail" = $member.AdditionalProperties.email;
                    "Id" = $member.AdditionalProperties.userId;
                }
            }
            $channel | Add-Member -NotePropertyName "Members" -NotePropertyValue $nonStandardChannelMembersObject
        } else {
            # standard channels do not have specific membership, would be same as parent team membership so not saving members here
            $channel | Add-Member -NotePropertyName "Members" -NotePropertyValue $null
        }
        $channel
    }
    $team | Add-Member -NotePropertyName "Channels" -NotePropertyValue $channelsReturn

    # Build and return object of results, one object per channel per member of channel (team membership for standard channels)
    $teamName = $team.DisplayName
    $groupID = $team.Id
    $teamDescription = $team.Description
    $teamPrivacy = $team.Visibility
    $teamIsArchived = $team.IsArchived
    $teamClassification = $team.Classification
    $teamSensitivityLabel = $team.AssignedLabel
    foreach ($channel in $team.Channels) {
        $channelName = $channel.DisplayName
        $channelMembershipType = $channel.MembershipType
        $channelDescription = $channel.Description

        if ($channel.MembershipType -ne "standard") {
            $channelMembersList = $channel.Members
        } else {
            $channelMembersList = $team.Members
        }
        foreach ($channelMember in $channelMembersList) {
            $channelMemberName = $channelMember.DisplayName
            $channelMemberRole = $channelMember.Role
            $channelMemberUserId = $channelMember.Id
            $channelMemberMail = $channelMember.Mail

            $teamChannelUsersReturn = [PSCustomObject]@{
                "Team Name" = $teamName;
                "Group ID" = $groupID;
                "Team Description" = $teamDescription;
                "Team Privacy" = $teamPrivacy;
                "Team Is Archived" = $teamIsArchived;
                "Team Classification" = $teamClassification;
                "Team Sensitivity Label" = $teamSensitivityLabel;
                "Channel Name" = $channelName;
                "Channel Membership Type" = $channelMembershipType;
                "Channel Description" = $channelDescription;
                "Channel Member Name" = $channelMemberName;
                "Channel Member Role" = $channelMemberRole;
                "Channel Member User ID" = $channelMemberUserId;
                "Channel Member Email" = $channelMemberMail;
            }

            $teamChannelUsersReturn
        }
    }

    $n++
}

Write-Progress -Id 1 -Activity "Gathering Teams Data" -Status "Saving report: $ExportCSVFilePath"
$ReportOutput | Export-Csv -Path $ExportCSVFilePath -NoTypeInformation -ErrorAction Stop
$outputfile = Get-ChildItem $ExportCSVFilePath
Write-Output "Report saved to: $($outputfile.FullName)"
Write-Progress -Id 1 -Activity "Gathering Teams Data" -Completed
