
FROM python:3.12-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    UV_CACHE_DIR=/uv_cache \
    HERMES_WEBUI_HOST=0.0.0.0 \
    HERMES_WEBUI_PORT=8787 \
    HERMES_WEBUI_AGENT_DIR=/opt/hermes

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    rsync \
    build-essential \
    pkg-config \
    libffi-dev \
    libssl-dev \
    libsqlite3-dev \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

RUN python -m pip install --no-cache-dir uv

RUN useradd --create-home --shell /bin/bash hermeswebui \
    && mkdir -p /app /uv_cache /workspace /opt/hermes \
    && chown -R hermeswebui:hermeswebui \
       /app /uv_cache /workspace /opt/hermes \
    && chmod 1777 /uv_cache /workspace

WORKDIR /apptoo

COPY . /apptoo

RUN test -f /apptoo/docker_init.bash \
    && chmod -R a+rX /apptoo \
    && chmod 755 /apptoo/docker_init.bash

COPY --chmod=755 docker_init.bash /hermeswebui_init.bash

RUN git clone --depth 1 \
    https://github.com/NousResearch/hermes-agent.git /opt/hermes \
    && test -f /opt/hermes/pyproject.toml \
    && chown -R hermeswebui:hermeswebui /opt/hermes

EXPOSE 8787

CMD ["/hermeswebui_init.bash"]
