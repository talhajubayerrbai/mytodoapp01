import time
from fastapi import APIRouter
from app.database import db_is_healthy

router = APIRouter()
_start = time.time()


@router.get('/')
def health_check():
    db_ok = db_is_healthy()
    return {
        'status': 'ok' if db_ok else 'degraded',
        'uptime': round(time.time() - _start, 1),
        'db': 'connected' if db_ok else 'unreachable',
    }
