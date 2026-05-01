# syntax=docker/dockerfile:1.6
FROM python:3.11-slim

# Don't write .pyc files; flush stdout/stderr immediately so logs reach
# CloudWatch in near-real-time when the CronJob runs.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY ETL.py ./

# Run as a non-root user
RUN useradd --create-home --shell /bin/bash etl
USER etl

CMD ["python", "ETL.py"]
