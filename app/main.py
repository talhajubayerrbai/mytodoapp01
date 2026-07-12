from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse
import pathlib

from app.routers import health, api, todos
from app.database import create_tables

app = FastAPI(title="mytodoapp01", version="1.0.0")


@app.on_event("startup")
def on_startup():
    """Create database tables on first start (idempotent)."""
    create_tables()


# Mount static files if directory exists
_static = pathlib.Path(__file__).parent.parent / 'public'
if _static.exists():
    app.mount('/public', StaticFiles(directory=str(_static)), name='static')

app.include_router(health.router,  prefix='/health',     tags=['health'])
app.include_router(api.router,     prefix='/api',        tags=['api'])
app.include_router(todos.router,   prefix='/api/todos',  tags=['todos'])


@app.get('/', response_class=HTMLResponse)
def root():
    html = pathlib.Path(__file__).parent.parent / 'public' / 'index.html'
    if html.exists():
        return HTMLResponse(content=html.read_text())
    return HTMLResponse(content='<h1>App is running</h1>')
