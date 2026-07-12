from datetime import datetime
from sqlalchemy import Column, Integer, String, Boolean, DateTime, Text
from app.database import Base


class Todo(Base):
    __tablename__ = "todos"

    id          = Column(Integer, primary_key=True, index=True)
    title       = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    completed   = Column(Boolean, default=False, nullable=False)
    created_at  = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at  = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
