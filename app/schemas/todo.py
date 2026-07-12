from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field


class TodoCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=255, description="Title of the todo item")
    description: Optional[str] = Field(None, description="Optional description")
    completed: bool = Field(False, description="Completion status")


class TodoUpdate(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=255)
    description: Optional[str] = None
    completed: Optional[bool] = None


class TodoResponse(BaseModel):
    id: int
    title: str
    description: Optional[str]
    completed: bool
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}
