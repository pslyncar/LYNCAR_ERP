import uvicorn

from .api import app
from .config import get_settings


def main() -> None:
    settings = get_settings()
    uvicorn.run(app, host=settings.bind_host, port=settings.bind_port)


if __name__ == "__main__":
    main()
