"""
Async Toolbox Service with Redis caching.

Provides async wrappers around ToolboxSyncClient with response caching
to avoid repeated calls for the same data within a TTL window.
"""
import asyncio
import json
import logging
import hashlib
from typing import Optional, Any, Dict
from functools import lru_cache

logger = logging.getLogger(__name__)


class ToolboxService:
    """
    Async wrapper for Google MCP Toolbox with Redis caching.
    
    Usage:
        service = ToolboxService(toolbox_url, redis_client, cache_ttl=3600)
        result = await service.call_tool("get-user-goal-sub-type-scheme-by-goal-id", goal_id="123")
    """
    
    def __init__(
        self, 
        toolbox_url: Optional[str], 
        redis_client: Optional[Any] = None,
        cache_ttl: int = 3600
    ):
        """
        Initialize the toolbox service.
        
        Args:
            toolbox_url: URL of the toolbox server
            redis_client: ArqRedis or similar async Redis client for caching
            cache_ttl: Cache time-to-live in seconds (default: 1 hour)
        """
        self.toolbox_url = toolbox_url
        self.redis = redis_client
        self.cache_ttl = cache_ttl
        self._client = None
        self._tools: Dict[str, Any] = {}
        
        if toolbox_url:
            try:
                from toolbox_core import ToolboxSyncClient
                self._client = ToolboxSyncClient(toolbox_url)
                logger.info(f"ToolboxService initialized with URL: {toolbox_url}")
            except ImportError:
                logger.warning("toolbox_core not installed. Toolbox features disabled.")
            except Exception as e:
                logger.error(f"Failed to initialize ToolboxSyncClient: {e}")
        else:
            logger.info("Toolbox URL not configured. Toolbox features disabled.")
    
    @property
    def is_available(self) -> bool:
        """Check if toolbox client is available."""
        return self._client is not None
    
    def _get_cache_key(self, tool_name: str, **kwargs) -> str:
        """Generate a unique cache key for a tool call."""
        # Sort kwargs for consistent key generation
        params_str = json.dumps(kwargs, sort_keys=True)
        params_hash = hashlib.md5(params_str.encode()).hexdigest()[:12]
        return f"toolbox:cache:{tool_name}:{params_hash}"
    
    async def _get_cached(self, cache_key: str) -> Optional[Dict[str, Any]]:
        """Retrieve cached response from Redis."""
        if not self.redis:
            return None
        
        try:
            cached = await self.redis.get(cache_key)
            if cached:
                data = cached.decode('utf-8') if isinstance(cached, bytes) else cached
                logger.debug(f"Cache hit for {cache_key}")
                return json.loads(data)
        except Exception as e:
            logger.warning(f"Cache read error: {e}")
        
        return None
    
    async def _set_cached(self, cache_key: str, data: Any) -> None:
        """Store response in Redis cache with TTL."""
        if not self.redis:
            return
        
        try:
            serialized = json.dumps(data) if not isinstance(data, str) else data
            await self.redis.setex(cache_key, self.cache_ttl, serialized)
            logger.debug(f"Cached {cache_key} with TTL {self.cache_ttl}s")
        except Exception as e:
            logger.warning(f"Cache write error: {e}")
    
    def _load_tool(self, tool_name: str) -> Any:
        """Load and cache a tool from the toolbox."""
        if tool_name not in self._tools:
            if not self._client:
                return None
            try:
                self._tools[tool_name] = self._client.load_tool(tool_name)
                logger.info(f"Loaded tool: {tool_name}")
            except Exception as e:
                logger.error(f"Failed to load tool {tool_name}: {e}")
                return None
        return self._tools[tool_name]
    
    async def call_tool(self, tool_name: str, use_cache: bool = True, **kwargs) -> Optional[Any]:
        """
        Call a toolbox tool asynchronously with optional caching.
        
        Args:
            tool_name: Name of the tool to call
            use_cache: Whether to use Redis caching (default: True)
            **kwargs: Arguments to pass to the tool
            
        Returns:
            Tool response or None if unavailable/failed
        """
        if not self.is_available:
            logger.debug(f"Toolbox unavailable, skipping {tool_name}")
            return None
        
        # Check cache first
        cache_key = self._get_cache_key(tool_name, **kwargs)
        if use_cache:
            cached = await self._get_cached(cache_key)
            if cached is not None:
                return cached
        
        # Load tool
        tool = self._load_tool(tool_name)
        if not tool:
            return None
        
        # Execute tool in thread pool to avoid blocking async loop
        try:
            loop = asyncio.get_event_loop()
            result = await loop.run_in_executor(None, lambda: tool(**kwargs))
            
            # Cache the result
            if use_cache and result is not None:
                # Convert result to serializable format if needed
                if hasattr(result, 'model_dump'):
                    result_data = result.model_dump()
                elif hasattr(result, '__dict__'):
                    result_data = result.__dict__
                else:
                    result_data = result
                
                await self._set_cached(cache_key, result_data)
            
            return result
            
        except Exception as e:
            logger.error(f"Error calling tool {tool_name}: {e}")
            return None
    
    async def get_goal_details(self, goal_id: str) -> Optional[Dict[str, Any]]:
        """
        Fetch goal details including sub-type and scheme information.
        
        Args:
            goal_id: The goal identifier
            
        Returns:
            Goal details dict or None
        """
        return await self.call_tool(
            "get-user-goal-sub-type-scheme-by-goal-id",
            goal_id=goal_id
        )
    
    async def get_multiple_goal_details(self, goal_ids: list[str]) -> Dict[str, Any]:
        """
        Fetch details for multiple goals concurrently.
        
        Args:
            goal_ids: List of goal identifiers
            
        Returns:
            Dict mapping goal_id to details (or None for failures)
        """
        if not goal_ids:
            return {}
        
        tasks = [self.get_goal_details(gid) for gid in goal_ids]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        return {
            gid: (result if not isinstance(result, Exception) else None)
            for gid, result in zip(goal_ids, results)
        }

    async def get_user_goals(self, user_id: str) -> Optional[Any]:
        """
        Fetch comprehensive goal, scheme and sub-type details for a user.
        
        Args:
            user_id: The client/user identifier (hyphens will be removed)
            
        Returns:
            List of goal details or None
        """
        if not user_id:
            return None
            
        # Remove hyphens for toolbox compatibility
        clean_id = user_id.replace("-", "")
        
        logger.debug(f"Fetching user goals for sanitized ID: {clean_id}")
        
        return await self.call_tool(
            "get-user-goal-sub-type-scheme-by-user-id",
            user_id=clean_id
        )


# Singleton instance helper
_toolbox_service: Optional[ToolboxService] = None

def get_toolbox_service(
    toolbox_url: Optional[str] = None,
    redis_client: Optional[Any] = None,
    cache_ttl: int = 3600
) -> ToolboxService:
    """
    Get or create a singleton ToolboxService instance.
    
    Args:
        toolbox_url: URL of the toolbox server (required on first call)
        redis_client: Async Redis client for caching
        cache_ttl: Cache TTL in seconds
        
    Returns:
        ToolboxService instance
    """
    global _toolbox_service
    
    if _toolbox_service is None:
        _toolbox_service = ToolboxService(toolbox_url, redis_client, cache_ttl)
    elif redis_client and _toolbox_service.redis is None:
        _toolbox_service.redis = redis_client
    
    return _toolbox_service
