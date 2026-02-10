"""PostgreSQL database connection helper for OpenClaw agents."""
import psycopg2
from psycopg2.extras import RealDictCursor
import os
from typing import Optional, Dict, Any

class Database:
    """Manages PostgreSQL connections with tenant isolation."""
    
    def __init__(self, tenant_id: Optional[str] = None):
        """
        Initialize database connection.
        
        Args:
            tenant_id: Optional tenant identifier for multi-tenancy
        """
        self.tenant_id = tenant_id
        self.connection = None
    
    def connect(self):
        """Establish connection to PostgreSQL."""
        try:
            self.connection = psycopg2.connect(
                host=os.getenv('DB_HOST'),
                port=os.getenv('DB_PORT', 5432),
                dbname=os.getenv('DB_NAME'),
                user=os.getenv('DB_USER'),
                password=os.getenv('DB_PASSWORD'),
                cursor_factory=RealDictCursor
            )
            
            # Set tenant context if provided
            if self.tenant_id:
                with self.connection.cursor() as cursor:
                    cursor.execute(
                        "SET app.tenant_id = %s", 
                        (self.tenant_id,)
                    )
            
            print(f"✅ Connected to database: {os.getenv('DB_NAME')}")
            return self
            
        except Exception as e:
            print(f"❌ Database connection failed: {e}")
            raise
    
    def execute(self, query: str, params: tuple = None) -> list:
        """Execute a query and return results."""
        with self.connection.cursor() as cursor:
            cursor.execute(query, params)
            if cursor.description:  # SELECT query
                return cursor.fetchall()
            self.connection.commit()  # INSERT/UPDATE/DELETE
            return []
    
    def close(self):
        """Close database connection."""
        if self.connection:
            self.connection.close()
            print("✅ Database connection closed")
    
    def __enter__(self):
        """Context manager entry."""
        return self.connect()
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        self.close()