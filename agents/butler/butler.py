"""Butler Agent - Personal assistant for email, calendar, and daily briefings."""
from dotenv import load_dotenv
load_dotenv('agents/butler/.env')

import sys
import os

# Add parent directory to path for imports
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from shared.database import Database
from shared.claude_client import ClaudeClient

class ButlerAgent:
    """Personal assistant agent."""
    
    def __init__(self, tenant_id: str = "customer-001"):
        """
        Initialize Butler agent.
        
        Args:
            tenant_id: Customer identifier for multi-tenancy
        """
        self.tenant_id = tenant_id
        self.claude = ClaudeClient()
        self.system_prompt = """You are Butler, a helpful personal assistant.
        
You help with:
- Email summarization and management
- Calendar organization
- Daily briefings
- Task prioritization

Be concise, professional, and proactive."""
    
    def run_health_check(self):
        """Verify database and API connectivity."""
        print("🔍 Running Butler health check...")
        
        # Test database
        try:
            with Database(self.tenant_id) as db:
                result = db.execute("SELECT version()")
                print(f"✅ Database: {result[0]['version'][:50]}...")
        except Exception as e:
            print(f"❌ Database check failed: {e}")
            return False
        
        # Test Claude API
        try:
            response = self.claude.chat(
                "Say 'Butler online' in 3 words or less",
                system=self.system_prompt
            )
            print(f"✅ Claude API: {response}")
        except Exception as e:
            print(f"❌ Claude API check failed: {e}")
            return False
        
        print("✅ All systems operational!")
        return True
    
    def process_request(self, user_input: str) -> str:
        """
        Process a user request.
        
        Args:
            user_input: The user's message/request
            
        Returns:
            Butler's response
        """
        try:
            response = self.claude.chat(user_input, system=self.system_prompt)
            return response
            
        except Exception as e:
            return f"❌ Error processing request: {e}"
    
    def interactive_mode(self):
        """Run Butler in interactive chat mode."""
        print("\n🤵 Butler Agent - Interactive Mode")
        print("Type 'quit' to exit\n")
        
        while True:
            user_input = input("You: ").strip()
            
            if user_input.lower() in ['quit', 'exit', 'q']:
                print("👋 Goodbye!")
                break
            
            if not user_input:
                continue
            
            response = self.process_request(user_input)
            print(f"\nButler: {response}\n")

def main():
    """Main entry point for Butler agent."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Butler Personal Assistant Agent')
    parser.add_argument(
        '--health-check',
        action='store_true',
        help='Run health check and exit'
    )
    parser.add_argument(
        '--tenant-id',
        default='customer-001',
        help='Tenant identifier (default: customer-001)'
    )
    
    args = parser.parse_args()
    
    butler = ButlerAgent(tenant_id=args.tenant_id)
    
    if args.health_check:
        success = butler.run_health_check()
        sys.exit(0 if success else 1)
    else:
        butler.interactive_mode()

if __name__ == "__main__":
    main()
