FROM python:3.11-slim-bullseye

WORKDIR /app

COPY requirements.txt .

RUN pip3 install -r requirements.txt

COPY profiles/ profiles/

COPY scripts/ppr.py .