import os
from functools import lru_cache
from pathlib import Path
from typing import Optional

from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    gemini_api_key: Optional[str] = None
    gemini_transcription_model: str = "gemini-2.5-flash"
    redis_host: str = "localhost"
    redis_port: int = 6379
    redis_db: int = 0
    redis_password: Optional[str] = None
    bucket_name: Optional[str] = None
    s3_region: str = "ap-south-1"
    s3_access_key: Optional[str] = None
    s3_secret_key: Optional[str] = None
    
    # Toolbox configuration
    toolbox_url: Optional[str] = "http://localhost:8005"
    toolbox_cache_ttl: int = 3600  # Cache TTL in seconds (1 hour default)

    model_config = SettingsConfigDict(
        env_file=Path(
            Path(__file__).parent.resolve(),
            os.environ.get("ENV_FILE", ".env")
        ),
        env_file_encoding="utf-8",
        extra="ignore"
    )

    @property
    def redis_uri(self):
        url = f"redis://{self.redis_host}:{self.redis_port}"
        if self.redis_password:
            url = f"redis://default:{self.redis_password}@{self.redis_host}:{self.redis_port}"
        if self.redis_db:
            url = f"{url}/{self.redis_db}"
        return url

    @property
    def redis_settings(self):
        from arq.connections import RedisSettings
        return RedisSettings(
            host=self.redis_host,
            port=self.redis_port,
            database=self.redis_db,
            password=self.redis_password
        )

@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()

settings = get_settings()