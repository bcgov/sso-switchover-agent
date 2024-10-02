FROM python:3.12.6-alpine3.19

WORKDIR /app

RUN python -m pip install --upgrade pip

ARG POETRY_VERSION=1.8.3

RUN apk add --no-cache \
        curl \
        gcc \
        libressl-dev \
        musl-dev \
        libffi-dev && \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile=minimal && \
    source $HOME/.cargo/env && \
    pip install --no-cache-dir poetry==${POETRY_VERSION} && \
    apk del \
        gcc \
        libressl-dev \
        musl-dev \
        libffi-dev


COPY ./pyproject.toml .
COPY ./poetry.lock .

RUN poetry config virtualenvs.create false \
    && poetry install --no-root --no-dev

COPY ./src /app/src

EXPOSE 8000

ENV PY_ENV=local

CMD ["python", "src/main.py"]
