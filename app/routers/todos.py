from typing import List
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.todo import Todo
from app.schemas.todo import TodoCreate, TodoUpdate, TodoResponse

router = APIRouter()


@router.get('/', response_model=List[TodoResponse], summary="List all todos")
def list_todos(
    completed: bool | None = None,
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(get_db),
):
    """Return all todo items. Optionally filter by `completed` status."""
    query = db.query(Todo)
    if completed is not None:
        query = query.filter(Todo.completed == completed)
    return query.order_by(Todo.created_at.desc()).offset(skip).limit(limit).all()


@router.post('/', response_model=TodoResponse, status_code=status.HTTP_201_CREATED, summary="Create a todo")
def create_todo(payload: TodoCreate, db: Session = Depends(get_db)):
    """Create a new todo item."""
    todo = Todo(**payload.model_dump())
    db.add(todo)
    db.commit()
    db.refresh(todo)
    return todo


@router.get('/{todo_id}', response_model=TodoResponse, summary="Get a todo")
def get_todo(todo_id: int, db: Session = Depends(get_db)):
    """Fetch a single todo item by ID."""
    todo = db.query(Todo).filter(Todo.id == todo_id).first()
    if not todo:
        raise HTTPException(status_code=404, detail=f"Todo {todo_id} not found")
    return todo


@router.put('/{todo_id}', response_model=TodoResponse, summary="Update a todo")
def update_todo(todo_id: int, payload: TodoUpdate, db: Session = Depends(get_db)):
    """Update title, description, or completed status of a todo."""
    todo = db.query(Todo).filter(Todo.id == todo_id).first()
    if not todo:
        raise HTTPException(status_code=404, detail=f"Todo {todo_id} not found")

    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(todo, field, value)

    db.commit()
    db.refresh(todo)
    return todo


@router.delete('/{todo_id}', status_code=status.HTTP_204_NO_CONTENT, summary="Delete a todo")
def delete_todo(todo_id: int, db: Session = Depends(get_db)):
    """Permanently delete a todo item."""
    todo = db.query(Todo).filter(Todo.id == todo_id).first()
    if not todo:
        raise HTTPException(status_code=404, detail=f"Todo {todo_id} not found")
    db.delete(todo)
    db.commit()
