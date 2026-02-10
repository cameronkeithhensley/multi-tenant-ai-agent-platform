"""Claude API client using AWS Bedrock."""
import boto3
import json
import os
from typing import List, Dict, Any

class ClaudeClient:
    """Wrapper for Claude API via AWS Bedrock."""
    
    def __init__(self):
        """Initialize Bedrock client."""
        self.client = boto3.client(
            'bedrock-runtime',
            region_name=os.getenv('AWS_REGION', 'us-east-1')
        )
        self.model_id = os.getenv(
            'CLAUDE_MODEL_ID', 
            'anthropic.claude-3-5-sonnet-20241022-v2:0'
        )
    
    def send_message(
        self, 
        messages: List[Dict[str, str]], 
        system: str = None,
        max_tokens: int = 1024
    ) -> str:
        """
        Send a message to Claude and get response.
        
        Args:
            messages: List of message dicts [{"role": "user", "content": "..."}]
            system: Optional system prompt
            max_tokens: Maximum tokens in response
            
        Returns:
            Claude's response text
        """
        try:
            request_body = {
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": max_tokens,
                "messages": messages
            }
            
            if system:
                request_body["system"] = system
            
            response = self.client.invoke_model(
                modelId=self.model_id,
                body=json.dumps(request_body)
            )
            
            response_body = json.loads(response['body'].read())
            return response_body['content'][0]['text']
            
        except Exception as e:
            print(f"❌ Claude API error: {e}")
            raise
    
    def chat(self, user_message: str, system: str = None) -> str:
        """
        Simple chat interface.
        
        Args:
            user_message: The user's message
            system: Optional system prompt
            
        Returns:
            Claude's response
        """
        messages = [{"role": "user", "content": user_message}]
        return self.send_message(messages, system=system)