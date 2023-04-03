FROM python:3.11-slim-bullseye

WORKDIR /app

RUN pip install psycopg2-binary==2.9.5 requests==2.28.2

COPY profiles/ profiles/

COPY scripts/ppr.py .