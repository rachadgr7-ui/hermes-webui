
#!/usr/bin/env bash

set -Eeuo pipefail

# --------------------------------------------------
# Hermes WebUI - Render startup script
# --------------------------------------------------

APP_SOURCE="/apptoo"
APP_DIR="/app"
APP_USER="hermeswebui"
AGENT_DIR="/opt/hermes"
VENV_DIR="${APP_DIR}/venv"
UV_CACHE_DIR="${UV_CACHE_DIR:-/uv_cache}"
PORT="${HERMES_WEBUI_PORT:-8787}"

error_exit() {
    echo "!! ERROR: $*"
    exit 1
}

echo
echo "=========================================="
echo "Starting Hermes WebUI"
echo "=========================================="

# 1. Validate the source directory
[[ -d "$APP_SOURCE" ]] \
    || error_exit "Source directory not found: $APP_SOURCE"

[[ -f "$APP_SOURCE/server.py" ]] \
    || error_exit "server.py not found in $APP_SOURCE"

[[ -f "$APP_SOURCE/requirements.txt" ]] \
    || error_exit "requirements.txt not found in $APP_SOURCE"

# 2. Ensure required tools and user exist
command -v rsync >/dev/null 2>&1 \
    || error_exit "rsync is missing. Install rsync in Dockerfile."

command -v su >/dev/null 2>&1 \
    || error_exit "su command is missing."

id "$APP_USER" >/dev/null 2>&1 \
    || error_exit "Runtime user $APP_USER does not exist."

# 3. Prepare application directories
mkdir -p "$APP_DIR" "$UV_CACHE_DIR" /workspace

# Preserve runtime data and the virtual environment when syncing.
echo "-- Synchronizing application files"

rsync -a \
    --delete \
    --exclude='/data/' \
    --exclude='/venv/' \
    --exclude='/hermes-agent-src/' \
    --exclude='/.deps_installed' \
    "$APP_SOURCE/" "$APP_DIR/" \
    || error_exit "Failed to synchronize $APP_SOURCE to $APP_DIR"

# 4. Prepare Hermes Agent source
if [[ -f "$AGENT_DIR/pyproject.toml" ]]; then
    echo "-- Hermes Agent source found at $AGENT_DIR"
else
    echo "!! WARNING: Hermes Agent source was not found at $AGENT_DIR"
fi

# 5. Prepare writable directories
mkdir -p "$UV_CACHE_DIR" /workspace

chown "$APP_USER:$APP_USER" "$APP_DIR" \
    || error_exit "Failed to set application directory ownership"

chown -R "$APP_USER:$APP_USER" "$VENV_DIR" 2>/dev/null || true
chown "$APP_USER:$APP_USER" "$UV_CACHE_DIR" /workspace \
    || error_exit "Failed to prepare runtime directories"

# 6. Require a configured state directory
if [[ -z "${HERMES_WEBUI_STATE_DIR:-}" ]]; then
    error_exit "HERMES_WEBUI_STATE_DIR not set in Render environment"
fi

mkdir -p "$HERMES_WEBUI_STATE_DIR" \
    || error_exit "Failed to create state directory: $HERMES_WEBUI_STATE_DIR"

chown "$APP_USER:$APP_USER" "$HERMES_WEBUI_STATE_DIR" \
    || error_exit "Failed to set state directory ownership"

# 7. Continue startup as the unprivileged runtime user
if [[ "$(id -un)" == "root" ]]; then
    echo "-- Switching to runtime user: $APP_USER"

    exec su -s /bin/bash "$APP_USER" -c \
        "exec bash /hermeswebui_init.bash --runtime"
fi

# --------------------------------------------------
# Runtime section
# --------------------------------------------------

if [[ "${1:-}" != "--runtime" ]]; then
    error_exit "Unexpected startup mode"
fi

echo "-- Running as $(id -un)"

export HERMES_WEBUI_HOST="${HERMES_WEBUI_HOST:-0.0.0.0}"
export HERMES_WEBUI_PORT="$PORT"
export UV_CACHE_DIR
export VIRTUAL_ENV="$VENV_DIR"
export PATH="$VENV_DIR/bin:/usr/local/bin:/usr/bin:/bin"

# 8. Verify application and state directories are writable
[[ -w "$APP_DIR" ]] \
    || error_exit "$APP_DIR is not writable by $(id -un)"

[[ -w "$HERMES_WEBUI_STATE_DIR" ]] \
    || error_exit "State directory is not writable: $HERMES_WEBUI_STATE_DIR"

# 9. Create the Python virtual environment if necessary
if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    echo "-- Creating Python virtual environment"

    if command -v uv >/dev/null 2>&1; then
        uv venv "$VENV_DIR" \
            || error_exit "Failed to create virtual environment"
    else
        python -m venv "$VENV_DIR" \
            || error_exit "Failed to create virtual environment"
    fi
fi

# 10. Install WebUI dependencies on first startup
if [[ ! -f "$VENV_DIR/.webui_deps_installed" ]]; then
    echo "-- Installing WebUI dependencies"

    if command -v uv >/dev/null 2>&1; then
        uv pip install \
            --python "$VENV_DIR/bin/python" \
            -r "$APP_DIR/requirements.txt" \
            || error_exit "Failed to install WebUI requirements"
    else
        "$VENV_DIR/bin/python" -m pip install \
            -r "$APP_DIR/requirements.txt" \
            || error_exit "Failed to install WebUI requirements"
    fi

    touch "$VENV_DIR/.webui_deps_installed"
fi

# 11. Install Hermes Agent if its source is available
if [[ -f "$AGENT_DIR/pyproject.toml" ]]; then
    if [[ ! -f "$VENV_DIR/.agent_deps_installed" ]]; then
        echo "-- Installing Hermes Agent dependencies"

        mkdir -p "$APP_DIR/hermes-agent-src"

        rsync -a \
            --exclude='.git/' \
            --exclude='*.egg-info/' \
            --exclude='build/' \
            --exclude='dist/' \
            "$AGENT_DIR/" "$APP_DIR/hermes-agent-src/" \
            || error_exit "Failed to stage Hermes Agent source"

        chmod -R u+w "$APP_DIR/hermes-agent-src"

        uv pip install \
            --python "$VENV_DIR/bin/python" \
            -e "$APP_DIR/hermes-agent-src[all]" \
            || error_exit "Failed to install Hermes Agent"

        touch "$VENV_DIR/.agent_deps_installed"
    fi
fi

# 12. Start the WebUI
echo "-- Starting Hermes WebUI on port $PORT"

cd "$APP_DIR"

exec "$VENV_DIR/bin/python" "$APP_DIR/server.py"
