from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, declarative_base
from fastapi import HTTPException, status
from app.config import settings

Base = declarative_base()

# Only build the engine when a real DB_HOST is configured.
# When DB_HOST is empty (no-database deployments) the module stays importable
# but all DB helpers degrade gracefully instead of crashing at startup.
_db_configured = bool(settings.DB_HOST)

if _db_configured:
    engine = create_engine(
        settings.DATABASE_URL,
        pool_pre_ping=True,
        pool_size=5,
        max_overflow=10,
    )
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
else:
    engine = None
    SessionLocal = None


def get_db():
    """FastAPI dependency that yields a DB session and closes it after the request."""
    if SessionLocal is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Database not configured",
        )
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def db_is_healthy() -> bool:
    """Return True if we can reach the database."""
    if engine is None:
        return False
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return True
    except Exception:
        return False


def create_tables():
    """Create all tables defined via SQLAlchemy models (idempotent)."""
    if engine is None:
        return
    Base.metadata.create_all(bind=engine)
