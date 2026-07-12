import os
from dotenv import load_dotenv

# Load .env file if present (local dev and production via EnvironmentFile)
load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), '..', '.env'), override=False)


class Settings:
    # App
    PORT: int = 8000
    HOST: str = '0.0.0.0'

    # Database
    DB_HOST: str = 'localhost'
    DB_PORT: int = 5432
    DB_NAME: str = 'tododb'
    DB_USER: str = 'todouser'
    DB_PASSWORD: str = ''

    def __init__(self):
        self.PORT = int(os.getenv('PORT', self.PORT))
        self.HOST = os.getenv('HOST', self.HOST)

        self.DB_HOST = os.getenv('DB_HOST', self.DB_HOST)
        self.DB_PORT = int(os.getenv('DB_PORT', self.DB_PORT))
        self.DB_NAME = os.getenv('DB_NAME', self.DB_NAME)
        self.DB_USER = os.getenv('DB_USER', self.DB_USER)
        self.DB_PASSWORD = os.getenv('DB_PASSWORD', self.DB_PASSWORD)

    @property
    def DATABASE_URL(self) -> str:
        return (
            f"postgresql://{self.DB_USER}:{self.DB_PASSWORD}"
            f"@{self.DB_HOST}:{self.DB_PORT}/{self.DB_NAME}"
        )


settings = Settings()
