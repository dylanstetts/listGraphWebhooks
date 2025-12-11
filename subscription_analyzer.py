"""
Microsoft Graph Subscription Analyzer
Identifies which applications are creating subscriptions for Teams callTranscript resources.
"""

import os
import json
import time
from typing import List, Dict, Optional
from pathlib import Path
from dotenv import load_dotenv
import msal
import requests
from datetime import datetime

# Load environment variables from .env file in script directory
env_path = Path(__file__).parent / '.env'
load_dotenv(dotenv_path=env_path)

class GraphSubscriptionAnalyzer:
    """Analyzes Microsoft Graph subscriptions to identify app ownership."""
    
    def __init__(self):
        """Initialize the analyzer with authentication configuration."""
        self.client_id = os.getenv('CLIENT_ID')
        self.tenant_id = os.getenv('TENANT_ID')
        
        # Debug: Show what was loaded
        if not self.client_id or not self.tenant_id:
            print(f"\nDebug: .env file location: {env_path}")
            print(f"Debug: .env file exists: {env_path.exists()}")
            print(f"Debug: CLIENT_ID loaded: {self.client_id}")
            print(f"Debug: TENANT_ID loaded: {self.tenant_id}")
            raise ValueError("CLIENT_ID and TENANT_ID must be set in .env file")
        
        self.authority = f"https://login.microsoftonline.com/{self.tenant_id}"
        self.scopes = ["https://graph.microsoft.com/Subscription.Read.All"]
        self.graph_endpoint = "https://graph.microsoft.com/v1.0"
        
        self.access_token = None
        self.subscriptions = []
        self.app_details = {}
    
    def authenticate(self) -> str:
        """
        Authenticate using delegated permissions (interactive browser login).
        Returns the access token.
        """
        print("Authenticating with Microsoft Graph...")
        print(f"Client ID: {self.client_id}")
        print(f"Tenant ID: {self.tenant_id}")
        print(f"Scopes: {', '.join(self.scopes)}")
        
        # Create a public client application for delegated auth
        app = msal.PublicClientApplication(
            client_id=self.client_id,
            authority=self.authority
        )
        
        # Try to get token from cache first
        accounts = app.get_accounts()
        if accounts:
            print(f"Found {len(accounts)} cached account(s)")
            result = app.acquire_token_silent(self.scopes, account=accounts[0])
            if result:
                print("✓ Using cached token")
                self.access_token = result['access_token']
                return self.access_token
        
        # Interactive login required
        print("\nOpening browser for interactive login...")
        print("Please sign in with your Global Admin account.")
        
        result = app.acquire_token_interactive(
            scopes=self.scopes,
            prompt="select_account"
        )
        
        if "access_token" in result:
            print("✓ Authentication successful")
            self.access_token = result['access_token']
            return self.access_token
        else:
            error = result.get("error_description", result.get("error", "Unknown error"))
            raise Exception(f"Authentication failed: {error}")
    
    def _make_graph_request_with_retry(self, url: str, headers: Dict, params: Optional[Dict] = None, max_retries: int = 8) -> requests.Response:
        """
        Make a Graph API request with exponential backoff retry logic.
        Handles 429 (Too Many Requests) and 503 (Service Unavailable) errors.
        
        Args:
            url: The URL to request
            headers: Request headers
            params: Optional query parameters
            max_retries: Maximum number of retry attempts (default: 8)
        
        Returns:
            Response object
        
        Raises:
            Exception: If all retries are exhausted
        """
        retry_count = 0
        base_delay = 1  # Start with 1 second
        
        while retry_count <= max_retries:
            try:
                response = requests.get(url, headers=headers, params=params)
                
                # Success
                if response.status_code == 200:
                    return response
                
                # Throttling or service unavailable
                if response.status_code in [429, 503]:
                    retry_count += 1
                    
                    if retry_count > max_retries:
                        raise Exception(f"Max retries ({max_retries}) exceeded for {url}")
                    
                    # Get retry-after header (in seconds)
                    retry_after = response.headers.get('Retry-After')
                    
                    if retry_after:
                        # Retry-After can be in seconds or HTTP date format
                        try:
                            wait_time = int(retry_after)
                        except ValueError:
                            # If it's a date, use exponential backoff instead
                            wait_time = base_delay * (2 ** (retry_count - 1))
                    else:
                        # Use exponential backoff: 1, 2, 4, 8, 16, 32, 64, 128 seconds
                        wait_time = base_delay * (2 ** (retry_count - 1))
                    
                    # Cap at 2 minutes
                    wait_time = min(wait_time, 120)
                    
                    print(f"\n Throttled (429/503). Retry {retry_count}/{max_retries} after {wait_time}s...", end=" ")
                    time.sleep(wait_time)
                    continue
                
                # Other errors - don't retry
                return response
                
            except requests.exceptions.RequestException as e:
                retry_count += 1
                
                if retry_count > max_retries:
                    raise Exception(f"Network error after {max_retries} retries: {e}")
                
                wait_time = base_delay * (2 ** (retry_count - 1))
                wait_time = min(wait_time, 120)
                
                print(f"\n Network error. Retry {retry_count}/{max_retries} after {wait_time}s...", end=" ")
                time.sleep(wait_time)
        
        raise Exception(f"Request failed after {max_retries} retries")
    
    def get_all_subscriptions(self) -> List[Dict]:
        """
        Retrieve all subscriptions using pagination.
        Returns a list of all subscription objects.
        """
        print("\nFetching subscriptions...")
        
        headers = {
            'Authorization': f'Bearer {self.access_token}',
            'Content-Type': 'application/json'
        }
        
        url = f"{self.graph_endpoint}/subscriptions"
        all_subscriptions = []
        page_count = 0
        
        while url:
            page_count += 1
            print(f"Fetching page {page_count}...", end=" ")
            
            response = requests.get(url, headers=headers)
            
            if response.status_code != 200:
                raise Exception(f"Failed to fetch subscriptions: {response.status_code} - {response.text}")
            
            data = response.json()
            subscriptions = data.get('value', [])
            all_subscriptions.extend(subscriptions)
            
            print(f"Retrieved {len(subscriptions)} subscriptions")
            
            # Check for next page
            url = data.get('@odata.nextLink')
        
        print(f"\n✓ Total subscriptions retrieved: {len(all_subscriptions)}")
        self.subscriptions = all_subscriptions
        return all_subscriptions
    
    def get_application_details(self, app_id: str) -> Optional[Dict]:
        """
        Get application display name and details from applicationId.
        Returns app details or None if not found.
        """
        if app_id in self.app_details:
            return self.app_details[app_id]
        
        headers = {
            'Authorization': f'Bearer {self.access_token}',
            'Content-Type': 'application/json'
        }
        
        # Try to get service principal by appId
        url = f"{self.graph_endpoint}/servicePrincipals"
        params = {'$filter': f"appId eq '{app_id}'", '$select': 'displayName,appId,id'}
        
        try:
            response = self._make_graph_request_with_retry(url, headers, params)
            
            if response.status_code == 200:
                data = response.json()
                if data.get('value') and len(data['value']) > 0:
                    sp = data['value'][0]
                    app_info = {
                        'displayName': sp.get('displayName', 'Unknown'),
                        'appId': app_id,
                        'servicePrincipalId': sp.get('id')
                    }
                    self.app_details[app_id] = app_info
                    return app_info
            
            # If not found, return basic info
            self.app_details[app_id] = {
                'displayName': 'Unknown (Not found in tenant)',
                'appId': app_id,
                'servicePrincipalId': None
            }
            return self.app_details[app_id]
            
        except Exception as e:
            print(f"Warning: Could not fetch app details for {app_id}: {e}")
            return {
                'displayName': 'Error fetching details',
                'appId': app_id,
                'servicePrincipalId': None
            }
    
    def filter_transcript_subscriptions(self) -> List[Dict]:
        """
        Filter subscriptions to only those for callTranscript resources.
        Returns list of transcript-related subscriptions.
        """
        transcript_subs = [
            sub for sub in self.subscriptions
            if 'transcript' in sub.get('resource', '').lower() or
               'communications/onlineMeetings' in sub.get('resource', '')
        ]
        
        print(f"\n✓ Found {len(transcript_subs)} callTranscript-related subscriptions")
        return transcript_subs
    
    def generate_report(self, output_format: str = 'both', filter_transcripts: bool = False) -> Dict:
        """
        Generate a detailed report of subscriptions grouped by application.
        
        Args:
            output_format: 'console', 'json', or 'both'
            filter_transcripts: If True, only include transcript subscriptions
        
        Returns:
            Dictionary containing the report data
        """
        print("\nGenerating report...")
        
        # Filter to transcript subscriptions if requested
        if filter_transcripts:
            subs_to_process = self.filter_transcript_subscriptions()
            transcript_count = len(subs_to_process)
        else:
            subs_to_process = self.subscriptions
            transcript_subs = self.filter_transcript_subscriptions()
            transcript_count = len(transcript_subs)
        
        # Group by applicationId
        apps_map = {}
        
        print("\nFetching application details...")
        for idx, sub in enumerate(subs_to_process, 1):
            app_id = sub.get('applicationId', 'Unknown')
            
            if app_id not in apps_map:
                print(f"  [{idx}/{len(subs_to_process)}] Fetching details for app: {app_id}")
                app_details = self.get_application_details(app_id)
                apps_map[app_id] = {
                    'applicationId': app_id,
                    'displayName': app_details.get('displayName', 'Unknown') if app_details else 'Unknown',
                    'servicePrincipalId': app_details.get('servicePrincipalId') if app_details else None,
                    'subscriptions': []
                }
            
            apps_map[app_id]['subscriptions'].append({
                'id': sub.get('id'),
                'resource': sub.get('resource'),
                'changeType': sub.get('changeType'),
                'expirationDateTime': sub.get('expirationDateTime'),
                'notificationUrl': sub.get('notificationUrl'),
                'clientState': sub.get('clientState')
            })
        
        # Create report
        report = {
            'generatedAt': datetime.utcnow().isoformat() + 'Z',
            'totalSubscriptions': len(self.subscriptions),
            'transcriptSubscriptions': transcript_count,
            'reportedSubscriptions': len(subs_to_process),
            'uniqueApplications': len(apps_map),
            'applications': list(apps_map.values())
        }
        
        # Sort by number of subscriptions (descending)
        report['applications'].sort(key=lambda x: len(x['subscriptions']), reverse=True)
        
        if output_format in ['console', 'both']:
            self._print_console_report(report)
        
        if output_format in ['json', 'both']:
            self._save_json_report(report)
        
        return report
    
    def _print_console_report(self, report: Dict):
        """Print formatted report to console."""
        print("\n" + "="*80)
        print("MICROSOFT GRAPH SUBSCRIPTION REPORT")
        print("="*80)
        print(f"Generated: {report['generatedAt']}")
        print(f"Total Subscriptions: {report['totalSubscriptions']}")
        print(f"CallTranscript Subscriptions: {report['transcriptSubscriptions']}")
        print(f"Reported Subscriptions: {report['reportedSubscriptions']}")
        print(f"Unique Applications: {report['uniqueApplications']}")
        print("="*80)
        
        for app in report['applications']:
            print(f"\n📱 Application: {app['displayName']}")
            print(f"   App ID: {app['applicationId']}")
            if app['servicePrincipalId']:
                print(f"   Service Principal ID: {app['servicePrincipalId']}")
            print(f"   Subscription Count: {len(app['subscriptions'])}")
            print(f"   Subscriptions:")
            
            for sub in app['subscriptions']:
                print(f"      • ID: {sub['id']}")
                print(f"        Resource: {sub['resource']}")
                print(f"        Change Type: {sub['changeType']}")
                print(f"        Expires: {sub['expirationDateTime']}")
                if sub['notificationUrl']:
                    print(f"        Notification URL: {sub['notificationUrl']}")
                print()
        
        print("="*80)
    
    def _save_json_report(self, report: Dict):
        """Save report to JSON file."""
        filename = f"subscription_report_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.json"
        filepath = os.path.join(os.path.dirname(__file__), filename)
        
        with open(filepath, 'w', encoding='utf-8') as f:
            json.dump(report, f, indent=2, ensure_ascii=False)
        
        print(f"\n✓ Report saved to: {filename}")


def main():
    """Main execution function."""
    print("Microsoft Graph Subscription Analyzer")
    print("="*80)
    print("This tool identifies which applications are creating subscriptions")
    print("for Teams callTranscript resources.")
    print("="*80)
    
    try:
        analyzer = GraphSubscriptionAnalyzer()
        
        # Authenticate
        analyzer.authenticate()
        # Get all subscriptions
        analyzer.get_all_subscriptions()
        
        # Generate report (filter_transcripts=False shows ALL subscriptions)
        analyzer.generate_report(output_format='both', filter_transcripts=False)
        analyzer.generate_report(output_format='both')
        
        print("\n✓ Analysis complete!")
        
    except Exception as e:
        print(f"\n Error: {e}")
        import traceback
        traceback.print_exc()
        return 1
    
    return 0


if __name__ == "__main__":
    exit(main())
