from contextlib import asynccontextmanager
import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from arq import create_pool
from arq.connections import RedisSettings

from v1.api.meetings import router as meetings_router
from v2.api.meetings import router as v2_router
from v2.api.meetings_gemini import router as v2_gemini_router

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Create Redis pool on startup
    app.state.redis_pool = await create_pool(
        RedisSettings.from_dsn(os.getenv("REDIS_URL", "redis://localhost:6379"))
    )
    yield
    # Close Redis pool on shutdown
    await app.state.redis_pool.close()

app = FastAPI(
    title="MeetIQ Backend",
    version="1.0.0",
    description="Backend API for MeetIQ - Real-time meeting transcription and analysis",
    lifespan=lifespan,
    docs_url="/docs",  # Swagger UI
    redoc_url="/redoc",  # ReDoc
    openapi_url="/openapi.json"  # OpenAPI schema
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(meetings_router, prefix="/meetings", tags=["meetings"])
app.include_router(v2_router, tags=["v2 meetings"])
