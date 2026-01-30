from pydantic import BaseSettings

class Settings(BaseSettings):
    gemini_api_key: str
    redis_host: str = "localhost"
    redis_port: int = 6379
    redis_db: int = 0

    class Config:
        env_file = ".env"