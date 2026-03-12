
# docker/Dockerfile
FROM python:3.11-slim

WORKDIR /app

# RUN python -m pip install --upgrade pip

# If you have requirements:
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY ./src /app/src
RUN chmod +x /app/src/xlog_trigger.py

ENV PY_ENV=local

# Default command (can be overridden in the CronJob)
CMD ["python", "/app/src/xlog_trigger.py"]
