# PowerShell Version - Get-GraphSubscriptions.ps1

A standalone PowerShell script version of the Microsoft Graph Subscription Analyzer. This script requires only PowerShell 5.1+ and will automatically install the required MSAL.PS module.

## Features

- ✅ **Standalone Script**: Everything in a single `.ps1` file
- ✅ **Auto-Install Dependencies**: Automatically installs MSAL.PS module if missing
- ✅ **Interactive Authentication**: Browser-based login with delegated permissions
- ✅ **Full Pagination Support**: Retrieves all subscriptions across all pages
- ✅ **Application Mapping**: Resolves application IDs to display names
- ✅ **Optional Filtering**: Can filter to show only callTranscript subscriptions
- ✅ **Dual Output**: Console display and JSON file export

## Prerequisites

1. **PowerShell 5.1 or higher** (comes with Windows 10/11)
2. **Azure AD App Registration** with:
   - Type: Public client
   - Redirect URI: `http://localhost`
   - Delegated Permissions:
     - `Subscription.Read.All`
     - `Application.Read.All`
   - Admin consent granted
3. **Global Admin account** to sign in with

## Usage

### Basic Usage

Show all subscriptions:

```powershell
.\Get-GraphSubscriptions.ps1 -ClientId "your-client-id" -TenantId "your-tenant-id"
```

### Filter to CallTranscript Subscriptions Only

```powershell
.\Get-GraphSubscriptions.ps1 -ClientId "your-client-id" -TenantId "your-tenant-id" -FilterTranscripts
```

### Custom Output Path

```powershell
.\Get-GraphSubscriptions.ps1 -ClientId "your-client-id" -TenantId "your-tenant-id" -OutputPath "C:\Reports"
```

### Get Help

```powershell
Get-Help .\Get-GraphSubscriptions.ps1 -Full
```

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-ClientId` | Yes | Azure AD App Registration Client ID |
| `-TenantId` | Yes | Azure AD Tenant ID |
| `-FilterTranscripts` | No | Switch to show only callTranscript subscriptions |
| `-OutputPath` | No | Directory path to save JSON report (default: script directory) |

## First Run

On the first run, the script will:

1. Check if MSAL.PS module is installed
2. If missing, prompt to install it (requires admin or CurrentUser scope)
3. Open a browser window for interactive login
4. Cache your credentials for future runs

## Output

### Console Output

The script displays a formatted report showing:
- Total subscription counts
- Each application with its subscriptions
- Subscription details (ID, resource, expiration, etc.)

### JSON Report

A timestamped JSON file is saved with complete details:
- Filename format: `subscription_report_YYYYMMDD_HHMMSS.json`
- Contains all subscription data for further processing

## Example Output

```
================================================================================
MICROSOFT GRAPH SUBSCRIPTION REPORT
================================================================================
Generated: 2025-12-11T10:30:00Z
Total Subscriptions: 150
CallTranscript Subscriptions: 75
Reported Subscriptions: 150
Unique Applications: 5
================================================================================

📱 Application: Teams Recording Bot
   App ID: 12345678-1234-1234-1234-123456789abc
   Service Principal ID: 87654321-4321-4321-4321-cba987654321
   Subscription Count: 45
   Subscriptions:
      • ID: sub-id-1
        Resource: communications/onlineMeetings/getAllTranscripts
        Change Type: created
        Expires: 2025-12-12T10:30:00Z
        Notification URL: https://example.com/webhook
```

## Troubleshooting

### Execution Policy Error

If you get "cannot be loaded because running scripts is disabled":

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### MSAL.PS Installation Failed

Manually install the module:

```powershell
Install-Module -Name MSAL.PS -Scope CurrentUser -Force
```

### Authentication Failed

- Verify your Client ID and Tenant ID are correct
- Ensure the app registration has delegated permissions
- Check that admin consent has been granted
- Sign in with a Global Admin account

## Comparison with Python Version

| Feature | PowerShell | Python |
|---------|-----------|--------|
| Single file | ✅ Yes | ❌ No (+ requirements.txt, .env) |
| Dependencies | MSAL.PS (auto-install) | msal, requests, python-dotenv |
| Configuration | Command-line parameters | .env file |
| Platform | Windows (native) | Cross-platform |
| Module management | Automatic | Manual pip install |

## License

MIT License - see LICENSE file for details.

## Author

Created by Dylan Stetts

## Repository

- Python Version: [https://github.com/dylanstetts/listGraphWebhooks](https://github.com/dylanstetts/listGraphWebhooks)
- PowerShell Version: Included in same repository
