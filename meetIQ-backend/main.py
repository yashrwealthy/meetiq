from contextlib import asynccontextmanager
import os
from fastapi import FastAPI
from arq import create_pool
from arq.connections import RedisSettings

from api.meetings import router as meetings_router

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Create Redis pool on startup
    app.state.redis_pool = await create_pool(
        RedisSettings.from_dsn(os.getenv("REDIS_URL", "redis://localhost:6379"))
    )
    yield
    # Close Redis pool on shutdown
    await app.state.redis_pool.close()

app = FastAPI(title="MeetIQ Backend", version="1.0.0", lifespan=lifespan)
app.include_router(meetings_router, prefix="/meetings", tags=["meetings"])
