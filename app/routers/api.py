import os
from fastapi import APIRouter
from app.database import db_is_healthy

router = APIRouter()


@router.get('/info')
def api_info():
    connected = db_is_healthy()
    return {
        'app': 'fastapi',
        'version': '1.0.0',
        'db': 'connected' if connected else 'unreachable',
        'env': os.getenv('APP_ENV', 'development'),
    }
