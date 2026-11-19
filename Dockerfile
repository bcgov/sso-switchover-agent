FROM python:3.12.11-slim-bookworm

WORKDIR /app

ARG POETRY_VERSION=1.8.3
ARG ASDF_VERSION=v0.14.1

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        gpg \
        unzip \
    && rm -rf /var/lib/apt/lists/* \
    && python -m pip install --no-cache-dir --upgrade pip poetry==${POETRY_VERSION}

# CLI tools required by transition-scripts, versioned by .tool-versions via asdf
ENV ASDF_DIR=/opt/asdf \
    ASDF_DATA_DIR=/opt/asdf
ENV PATH="${ASDF_DIR}/shims:${ASDF_DIR}/bin:${PATH}"

RUN git clone --depth 1 --branch ${ASDF_VERSION} https://github.com/asdf-vm/asdf.git ${ASDF_DIR}

COPY ./.tool-versions /app/.tool-versions

RUN for tool in helm oc kubectl jq; do \
        asdf plugin add "$tool" && asdf install "$tool"; \
    done \
    && asdf reshim

# Pre-pull the keycloak chart so the switch script needs no access to the helm repo
COPY --exclude=./transition-scripts/.env ./transition-scripts /app/transition-scripts

RUN chart_version=$(sed -n 's/^KEYCLOAK_HELM_CHART_VERSION="\(.*\)"/\1/p' transition-scripts/helpers/helm.sh) \
    && helm repo add sso-charts https://bcgov.github.io/sso-helm-charts \
    && helm pull sso-charts/sso-keycloak --version "$chart_version" --untar --untardir /opt/charts

# The agent always runs in the golddr cluster, using its in-cluster service account
ENV IN_CLUSTER_NAME=golddr \
    KEYCLOAK_HELM_CHART_PATH=/opt/charts/sso-keycloak

COPY ./pyproject.toml .
COPY ./poetry.lock .

RUN poetry config virtualenvs.create false \
    && poetry install --no-root --no-dev

COPY ./src /app/src

EXPOSE 8000

ENV PY_ENV=local

CMD ["python", "src/main.py"]
