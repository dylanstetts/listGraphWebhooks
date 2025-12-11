<#
.SYNOPSIS
    Microsoft Graph Subscription Analyzer - PowerShell Edition
    
.DESCRIPTION
    Identifies which applications are creating Microsoft Graph subscriptions in your tenant.
    Helps resolve subscription quota issues and provides visibility into subscription ownership.
    
.PARAMETER ClientId
    The Azure AD App Registration Client ID
    
.PARAMETER TenantId
    The Azure AD Tenant ID
    
.PARAMETER FilterTranscripts
    If specified, only show callTranscript-related subscriptions
    
.PARAMETER OutputPath
    Path to save the JSON report (optional)
    
.EXAMPLE
    .\Get-GraphSubscriptions.ps1 -ClientId "your-client-id" -TenantId "your-tenant-id"
    
.EXAMPLE
    .\Get-GraphSubscriptions.ps1 -ClientId "your-client-id" -TenantId "your-tenant-id" -FilterTranscripts
    
.EXAMPLE
    .\Get-GraphSubscriptions.ps1 -ClientId "your-client-id" -TenantId "your-tenant-id" -OutputPath "C:\Reports"
    
.NOTES
    Author: Dylan Stetts
    Requires: MSAL.PS module (will auto-install if missing)
    Permissions Required: Subscription.Read.All, Application.Read.All (Delegated)
    
.LINK
    https://github.com/dylanstetts/listGraphWebhooks
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Azure AD App Registration Client ID")]
    [string]$ClientId,
    
    [Parameter(Mandatory = $true, HelpMessage = "Azure AD Tenant ID")]
    [string]$TenantId,
    
    [Parameter(Mandatory = $false, HelpMessage = "Only show callTranscript subscriptions")]
    [switch]$FilterTranscripts,
    
    [Parameter(Mandatory = $false, HelpMessage = "Path to save JSON report")]
    [string]$OutputPath = $PSScriptRoot
)

#Requires -Version 5.1

# Script configuration
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ============================================================================
# Module Management
# ============================================================================

function Install-RequiredModule {
    param([string]$ModuleName)
    
    if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
        Write-Host "Installing required module: $ModuleName..." -ForegroundColor Yellow
        try {
            Install-Module -Name $ModuleName -Scope CurrentUser -Force -AllowClobber
            Write-Host "✓ Module installed successfully" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to install $ModuleName. Please run: Install-Module -Name $ModuleName -Scope CurrentUser"
            exit 1
        }
    }
}

# Check and install MSAL.PS module
Install-RequiredModule -ModuleName "MSAL.PS"
Import-Module MSAL.PS -ErrorAction Stop

# ============================================================================
# Authentication Functions
# ============================================================================

function Get-GraphAccessToken {
    param(
        [string]$ClientId,
        [string]$TenantId
    )
    
    Write-Host "`n" -NoNewline
    Write-Host "="*80 -ForegroundColor Cyan
    Write-Host "AUTHENTICATION" -ForegroundColor Cyan
    Write-Host "="*80 -ForegroundColor Cyan
    Write-Host "Client ID: $ClientId"
    Write-Host "Tenant ID: $TenantId"
    Write-Host "Scopes: Subscription.Read.All, Application.Read.All"
    Write-Host "`nOpening browser for interactive login..."
    Write-Host "Please sign in with your Global Admin account.`n"
    
    try {
        $token = Get-MsalToken `
            -ClientId $ClientId `
            -TenantId $TenantId `
            -Scopes "https://graph.microsoft.com/Subscription.Read.All", "https://graph.microsoft.com/Application.Read.All" `
            -Interactive `
            -ErrorAction Stop
        
        Write-Host " Authentication successful" -ForegroundColor Green
        return $token.AccessToken
    }
    catch {
        Write-Error "Authentication failed: $_"
        exit 1
    }
}

# ============================================================================
# Graph API Functions
# ============================================================================

function Invoke-GraphRequest {
    param(
        [string]$Uri,
        [string]$AccessToken,
        [string]$Method = "GET"
    )
    
    $headers = @{
        'Authorization' = "Bearer $AccessToken"
        'Content-Type'  = 'application/json'
    }
    
    try {
        $response = Invoke-RestMethod -Uri $Uri -Headers $headers -Method $Method -ErrorAction Stop
        return $response
    }
    catch {
        Write-Error "Graph API request failed: $_"
        throw
    }
}

function Get-AllSubscriptions {
    param([string]$AccessToken)
    
    Write-Host "`n" -NoNewline
    Write-Host "="*80 -ForegroundColor Cyan
    Write-Host "FETCHING SUBSCRIPTIONS" -ForegroundColor Cyan
    Write-Host "="*80 -ForegroundColor Cyan
    
    $allSubscriptions = @()
    $url = "https://graph.microsoft.com/v1.0/subscriptions"
    $pageCount = 0
    
    while ($url) {
        $pageCount++
        Write-Host "Fetching page $pageCount... " -NoNewline
        
        $response = Invoke-GraphRequest -Uri $url -AccessToken $AccessToken
        $subscriptions = $response.value
        $allSubscriptions += $subscriptions
        
        Write-Host "Retrieved $($subscriptions.Count) subscriptions" -ForegroundColor Green
        
        $url = $response.'@odata.nextLink'
    }
    
    Write-Host "`n✓ Total subscriptions retrieved: $($allSubscriptions.Count)" -ForegroundColor Green
    return $allSubscriptions
}

function Get-ApplicationDetails {
    param(
        [string]$AppId,
        [string]$AccessToken,
        [hashtable]$Cache
    )
    
    # Check cache first
    if ($Cache.ContainsKey($AppId)) {
        return $Cache[$AppId]
    }
    
    try {
        $filterQuery = "appId eq '$AppId'"
        $encodedFilter = [System.Web.HttpUtility]::UrlEncode($filterQuery)
        $uri = "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=$encodedFilter&`$select=displayName,appId,id"
        
        $response = Invoke-GraphRequest -Uri $uri -AccessToken $AccessToken
        
        if ($response.value -and $response.value.Count -gt 0) {
            $sp = $response.value[0]
            $appInfo = @{
                displayName         = $sp.displayName
                appId               = $AppId
                servicePrincipalId  = $sp.id
            }
        }
        else {
            $appInfo = @{
                displayName         = "Unknown (Not found in tenant)"
                appId               = $AppId
                servicePrincipalId  = $null
            }
        }
        
        $Cache[$AppId] = $appInfo
        return $appInfo
    }
    catch {
        Write-Warning "Could not fetch app details for $AppId : $_"
        $appInfo = @{
            displayName         = "Error fetching details"
            appId               = $AppId
            servicePrincipalId  = $null
        }
        $Cache[$AppId] = $appInfo
        return $appInfo
    }
}

function Get-TranscriptSubscriptions {
    param([array]$Subscriptions)
    
    return $Subscriptions | Where-Object {
        $_.resource -match 'transcript|communications/onlineMeetings'
    }
}

# ============================================================================
# Report Generation Functions
# ============================================================================

function New-SubscriptionReport {
    param(
        [array]$Subscriptions,
        [string]$AccessToken,
        [bool]$FilterTranscripts
    )
    
    Write-Host "`n" -NoNewline
    Write-Host "="*80 -ForegroundColor Cyan
    Write-Host "GENERATING REPORT" -ForegroundColor Cyan
    Write-Host "="*80 -ForegroundColor Cyan
    
    # Determine which subscriptions to process
    $transcriptSubs = Get-TranscriptSubscriptions -Subscriptions $Subscriptions
    
    if ($FilterTranscripts) {
        $subsToProcess = $transcriptSubs
        Write-Host "Filtering to callTranscript subscriptions only..."
    }
    else {
        $subsToProcess = $Subscriptions
        Write-Host "Processing all subscriptions..."
    }
    
    Write-Host "✓ Found $($transcriptSubs.Count) callTranscript-related subscriptions" -ForegroundColor Green
    Write-Host "Processing $($subsToProcess.Count) subscriptions for report`n"
    
    # Group by application
    $appCache = @{}
    $appsMap = @{}
    
    Write-Host "Fetching application details..." -ForegroundColor Cyan
    $index = 0
    foreach ($sub in $subsToProcess) {
        $index++
        $appId = if ($sub.applicationId) { $sub.applicationId } else { "Unknown" }
        
        if (-not $appsMap.ContainsKey($appId)) {
            Write-Host "  [$index/$($subsToProcess.Count)] Fetching details for app: $appId"
            $appDetails = Get-ApplicationDetails -AppId $appId -AccessToken $AccessToken -Cache $appCache
            
            $appsMap[$appId] = @{
                applicationId       = $appId
                displayName         = $appDetails.displayName
                servicePrincipalId  = $appDetails.servicePrincipalId
                subscriptions       = @()
            }
        }
        
        $appsMap[$appId].subscriptions += @{
            id                  = $sub.id
            resource            = $sub.resource
            changeType          = $sub.changeType
            expirationDateTime  = $sub.expirationDateTime
            notificationUrl     = $sub.notificationUrl
            clientState         = $sub.clientState
        }
    }
    
    # Create report object
    $report = @{
        generatedAt             = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        totalSubscriptions      = $Subscriptions.Count
        transcriptSubscriptions = $transcriptSubs.Count
        reportedSubscriptions   = $subsToProcess.Count
        uniqueApplications      = $appsMap.Count
        applications            = @()
    }
    
    # Sort applications by subscription count (descending)
    $sortedApps = $appsMap.GetEnumerator() | Sort-Object { $_.Value.subscriptions.Count } -Descending
    
    foreach ($app in $sortedApps) {
        $report.applications += $app.Value
    }
    
    return $report
}

function Write-ConsoleReport {
    param([hashtable]$Report)
    
    Write-Host "`n" -NoNewline
    Write-Host "="*80 -ForegroundColor Cyan
    Write-Host "MICROSOFT GRAPH SUBSCRIPTION REPORT" -ForegroundColor Cyan
    Write-Host "="*80 -ForegroundColor Cyan
    Write-Host "Generated: $($Report.generatedAt)"
    Write-Host "Total Subscriptions: $($Report.totalSubscriptions)"
    Write-Host "CallTranscript Subscriptions: $($Report.transcriptSubscriptions)"
    Write-Host "Reported Subscriptions: $($Report.reportedSubscriptions)"
    Write-Host "Unique Applications: $($Report.uniqueApplications)"
    Write-Host "="*80 -ForegroundColor Cyan
    
    foreach ($app in $Report.applications) {
        Write-Host "`n📱 Application: $($app.displayName)" -ForegroundColor Yellow
        Write-Host "   App ID: $($app.applicationId)" -ForegroundColor Gray
        if ($app.servicePrincipalId) {
            Write-Host "   Service Principal ID: $($app.servicePrincipalId)" -ForegroundColor Gray
        }
        Write-Host "   Subscription Count: $($app.subscriptions.Count)" -ForegroundColor White
        Write-Host "   Subscriptions:" -ForegroundColor White
        
        foreach ($sub in $app.subscriptions) {
            Write-Host "      • ID: $($sub.id)" -ForegroundColor Gray
            Write-Host "        Resource: $($sub.resource)" -ForegroundColor Gray
            Write-Host "        Change Type: $($sub.changeType)" -ForegroundColor Gray
            Write-Host "        Expires: $($sub.expirationDateTime)" -ForegroundColor Gray
            if ($sub.notificationUrl) {
                Write-Host "        Notification URL: $($sub.notificationUrl)" -ForegroundColor Gray
            }
            Write-Host ""
        }
    }
    
    Write-Host "="*80 -ForegroundColor Cyan
}

function Save-JsonReport {
    param(
        [hashtable]$Report,
        [string]$OutputPath
    )
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $filename = "subscription_report_$timestamp.json"
    $filepath = Join-Path -Path $OutputPath -ChildPath $filename
    
    try {
        $Report | ConvertTo-Json -Depth 10 | Out-File -FilePath $filepath -Encoding UTF8
        Write-Host "`n✓ Report saved to: $filepath" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to save JSON report: $_"
    }
}

# ============================================================================
# Main Execution
# ============================================================================

function Main {
    Write-Host "`n" -NoNewline
    Write-Host "="*80 -ForegroundColor Cyan
    Write-Host "Microsoft Graph Subscription Analyzer - PowerShell Edition" -ForegroundColor Cyan
    Write-Host "="*80 -ForegroundColor Cyan
    Write-Host "This tool identifies which applications are creating subscriptions"
    Write-Host "for Microsoft Graph resources in your tenant."
    Write-Host "="*80 -ForegroundColor Cyan
    
    try {
        # Authenticate
        $accessToken = Get-GraphAccessToken -ClientId $ClientId -TenantId $TenantId
        
        # Get all subscriptions
        $subscriptions = Get-AllSubscriptions -AccessToken $accessToken
        
        # Generate report
        $report = New-SubscriptionReport `
            -Subscriptions $subscriptions `
            -AccessToken $accessToken `
            -FilterTranscripts $FilterTranscripts.IsPresent
        
        # Display console report
        Write-ConsoleReport -Report $report
        
        # Save JSON report
        Save-JsonReport -Report $report -OutputPath $OutputPath
        
        Write-Host "`n Analysis complete!" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Host "`n Error: $_" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor Red
        exit 1
    }
}

# Run the script
Main
