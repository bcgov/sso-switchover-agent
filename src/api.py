import logging
import uvicorn

from fastapi import FastAPI, APIRouter
from fastapi.responses import JSONResponse
from starlette import status
from config import config

logger = logging.getLogger(__name__)

app = FastAPI()

api_router = APIRouter(prefix="/api")


@api_router.get("/health")
def health():
    return {"status": "up"}


app.include_router(api_router)


@app.exception_handler(Exception)
async def exception_handler(request, exc):
    return JSONResponse(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, content={"message": "{0}".format(exc)})


def fastapi():
    logger.info("starting...")
    uvicorn.run(app, host="0.0.0.0", port=config.get('port'), log_level='warning')
