# Microsoft Graph Subscription Analyzer

A Python tool to identify which applications are creating Microsoft Graph subscriptions in your tenant. This tool helps resolve subscription quota issues and provides visibility into subscription ownership across all resources.

## Problem Statement

When managing Microsoft Graph subscriptions (webhooks), you may encounter:
- **Quota limits** on resources like Teams callTranscript
- **"Tenant has reached its maximum number of subscriptions"** errors
- **Difficulty identifying** which applications own which subscriptions

The Microsoft Graph subscriptions API has limitations:
- Only returns paginated results
- Doesn't support OData query parameters for filtering
- Doesn't directly show app ownership details
-  **Delegated Authentication**: Uses interactive browser login with Global Admin account
-  **Full Pagination Support**: Automatically retrieves all subscription pages
-  **Application Mapping**: Resolves `applicationId` to app display names
-  **Complete Coverage**: Lists all Graph subscriptions across all resources
-  **Transcript Tracking**: Separately identifies callTranscript subscriptions
-  **Detailed Reporting**: Outputs both console and JSON reports
-  **Token Caching**: Reuses cached tokens for efficiency login with Global Admin account
-  **Full Pagination Support**: Automatically retrieves all subscription pages
-  **Application Mapping**: Resolves `applicationId` to app display names
-  **Transcript Filtering**: Identifies subscriptions for callTranscript resources
-  **Detailed Reporting**: Outputs both console and JSON reports
-  **Token Caching**: Reuses cached tokens for efficiency

## Prerequisites

1. **Azure AD App Registration**:
   - Create an app registration in Azure Portal
   - Set as **Public client** (for delegated auth)
   - Add **Redirect URI**: `http://localhost` (Mobile and desktop applications)
   - Grant **API Permissions**:
     - `Subscription.Read.All` (Delegated)
     - `Application.Read.All` (Delegated) - for app name resolution
   - Have a **Global Admin** account to sign in with

2. **Python 3.8+** installed
## Setup

1. **Clone this repository**:
   ```bash
   git clone https://github.com/dylanstetts/listGraphWebhooks.git
   cd listGraphWebhooks
   ```

2. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

3. **Configure environment variables**:
3. **Configure environment variables**:
   - Copy `.env.example` to `.env`
   - Edit `.env` and fill in your values:
   ```
   CLIENT_ID=your-app-registration-client-id
   TENANT_ID=your-tenant-id
   ```

## Azure AD App Registration Setup

### Step-by-Step Instructions:

1. Go to [Azure Portal](https://portal.azure.com) → **Azure Active Directory** → **App registrations** → **New registration**

2. Configure the app:
   - **Name**: Graph Subscription Analyzer
   - **Supported account types**: Accounts in this organizational directory only
   - **Redirect URI**: Select "Public client/native (mobile & desktop)" and enter `http://localhost`

3. After creation, note the:
   - **Application (client) ID** → use for `CLIENT_ID`
   - **Directory (tenant) ID** → use for `TENANT_ID`

4. Configure **Authentication**:
   - Go to **Authentication** blade
   - Under "Advanced settings" → "Allow public client flows" → **Yes**

5. Grant **API Permissions**:
   - Go to **API permissions** blade
   - Click **Add a permission** → **Microsoft Graph** → **Delegated permissions**
   - Add:
     - `Subscription.Read.All`
     - `Application.Read.All`
   - Click **Grant admin consent** for your organization

## Usage

Run the analyzer:

```bash
python subscription_analyzer.py
```

### What Happens:

1. **Authentication**: Browser window opens for you to sign in with Global Admin account
2. **Fetching**: Tool retrieves all subscription pages across your tenant
3. **Analysis**: Identifies all subscriptions and separately tracks callTranscript resources
4. **Mapping**: Resolves application IDs to display names
5. **Reporting**: Outputs to console and JSON file

### Sample Output:

```
================================================================================
MICROSOFT GRAPH SUBSCRIPTION REPORT
================================================================================
Generated: 2025-12-10T16:26:00Z
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
        Expires: 2025-12-11T16:26:00Z
        Notification URL: https://example.com/webhook
      ...
```

## Output Files

The tool generates a timestamped JSON report:
- **Filename**: `subscription_report_YYYYMMDD_HHMMSS.json`
- **Contains**:
  - Complete subscription details
  - Application mappings
  - Resource information
  - Expiration dates
  - Notification URLs

## Troubleshooting

### Authentication Errors

**Error**: "AADSTS65001: The user or administrator has not consented"
- **Solution**: Ensure admin consent is granted in the app registration

**Error**: "AADSTS7000218: The request body must contain the following parameter: 'client_assertion'"
- **Solution**: Enable "Allow public client flows" in app authentication settings

### Permission Errors

**Error**: "Insufficient privileges to complete the operation"
- **Solution**: 
  - Verify `Subscription.Read.All` is granted
  - Ensure you're signing in with a Global Admin account
  - Grant admin consent for the permissions

### No Subscriptions Found

- Verify you have subscriptions in your tenant: Check manually in Graph Explorer
- Ensure the token has the correct scopes

## Understanding the Results

### Key Information for Each App:

1. **Display Name**: Human-readable app name
2. **Application ID**: Unique identifier for the app registration
3. **Service Principal ID**: Instance of the app in your tenant
4. **Subscription Count**: How many subscriptions this app created
5. **Resource**: The Graph resource being monitored (look for `transcript`)
### Cleaning Up Subscriptions:

Once you've identified the problematic apps:

1. **Contact app owners**: Ask them to delete unnecessary subscriptions
2. **Delete via Graph API**: Use `DELETE /subscriptions/{id}` with `Subscription.ReadWrite.All` permission
3. **Disable apps**: If apps are no longer needed, disable them in Azure AD

## API Reference

- **Subscriptions**: [Microsoft Graph Subscriptions API](https://learn.microsoft.com/en-us/graph/api/subscription-list)
- **Service Principals**: [Microsoft Graph Service Principals API](https://learn.microsoft.com/en-us/graph/api/serviceprincipal-list)

## Repository

GitHub: [https://github.com/dylanstetts/listGraphWebhooks](https://github.com/dylanstetts/listGraphWebhooks)

## License

MIT License - see LICENSE file for details.

## Contributing

Contributions are welcome! Feel free to submit issues or pull requests for:
- Export to CSV format
- Filter by resource type or expiration date
- Automatic cleanup functionality
- Support for application permissions (unattended scenarios)
- Additional reporting formats

## Author

Created by Dylan Stetts to help Microsoft 365 administrators manage Graph subscription quotas.
- Support for application permissions (unattended scenarios)
