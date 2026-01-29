from fastapi import FastAPI

from api.meetings import router as meetings_router

app = FastAPI(title="MeetIQ Backend", version="1.0.0")
app.include_router(meetings_router, prefix="/meetings", tags=["meetings"])
