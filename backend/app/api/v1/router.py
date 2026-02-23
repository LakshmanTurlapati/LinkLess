from fastapi import APIRouter

from app.api.v1.routes import (
    auth,
    connections,
    conversations,
    debug,
    health,
    profile,
    uploads,
)

api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(auth.router)
api_router.include_router(profile.router)
api_router.include_router(uploads.router, prefix="/uploads")
api_router.include_router(conversations.router, prefix="/conversations")
api_router.include_router(connections.router, prefix="/connections")
api_router.include_router(debug.router)
