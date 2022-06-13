FROM python:3.8.6-alpine

WORKDIR /app

RUN apk add curl

RUN python -m pip install --upgrade pip

ENV XDG_CONFIG_HOME=/var

RUN cd /tmp && \
  curl -sSL https://raw.githubusercontent.com/python-poetry/poetry/master/get-poetry.py > get-poetry.py && \
  POETRY_HOME=/opt/poetry python get-poetry.py --version 1.1.13 && \
  cd /usr/local/bin && \
  chmod +x /opt/poetry/bin/poetry && \
  ln -s /opt/poetry/bin/poetry && \
  poetry config virtualenvs.create false && \
  chmod g+r /var/pypoetry/config.toml

COPY ./pyproject.toml .
COPY ./poetry.lock .

RUN poetry install --no-root --no-dev

COPY ./src /app/src

EXPOSE 8000

ENV PY_ENV=local

ENTRYPOINT ["poetry", "run"]
CMD ["python", "src/main.py"]
