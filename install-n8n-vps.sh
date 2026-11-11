#!/usr/bin/env bash
set -Eeuo pipefail

# Instala o n8n com Docker Compose, Caddy/HTTPS e PostgreSQL externo.
# Uso:
#   chmod +x install-n8n-vps.sh
#   sudo ./install-n8n-vps.sh
#
# O script não altera containers existentes. Por padrão, cria um banco e usuário
# próprios para o n8n no PostgreSQL exposto em 127.0.0.1:5432.

APP_DIR="${APP_DIR:-/opt/n8n}"
N8N_DOMAIN="${N8N_DOMAIN:-n8n.revizeautocenter.shop}"
N8N_DIRECT_PORT="${N8N_DIRECT_PORT:-5680}"
N8N_DIRECT_BIND="${N8N_DIRECT_BIND:-127.0.0.1}"
POSTGRES_HOST="${POSTGRES_HOST:-host.docker.internal}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB:-n8n}"
POSTGRES_USER="${POSTGRES_USER:-n8n}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
POSTGRES_SSL="${POSTGRES_SSL:-false}"
POSTGRES_ADMIN_HOST="${POSTGRES_ADMIN_HOST:-127.0.0.1}"
POSTGRES_ADMIN_PORT="${POSTGRES_ADMIN_PORT:-5432}"
POSTGRES_ADMIN_DB="${POSTGRES_ADMIN_DB:-postgres}"
POSTGRES_ADMIN_USER="${POSTGRES_ADMIN_USER:-}"
POSTGRES_ADMIN_PASSWORD="${POSTGRES_ADMIN_PASSWORD:-}"
CREATE_POSTGRES="${CREATE_POSTGRES:-1}"

die() { echo "ERRO: $*" >&2; exit 1; }
need_root() { [[ "${EUID}" -eq 0 ]] || die "execute com sudo"; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

install_docker() {
  if command_exists docker && docker compose version >/dev/null 2>&1; then
    if ! command_exists openssl; then
      apt-get update
      apt-get install -y openssl
    fi
    return
  fi
  echo "Instalando Docker e Docker Compose..."
  if ! command_exists curl || ! command_exists openssl; then
    apt-get update
    apt-get install -y ca-certificates curl openssl
  fi
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
  docker compose version >/dev/null 2>&1 || die "Docker Compose não está disponível"
}

random_hex() { openssl rand -hex 32; }

provision_postgres() {
  [[ "${CREATE_POSTGRES}" == "1" ]] || return 0

  if [[ -z "${POSTGRES_ADMIN_USER}" ]]; then
    read -r -p "Usuário administrador do PostgreSQL [postgres]: " POSTGRES_ADMIN_USER
    POSTGRES_ADMIN_USER="${POSTGRES_ADMIN_USER:-postgres}"
  fi
  if [[ -z "${POSTGRES_ADMIN_PASSWORD}" ]]; then
    read -r -s -p "Senha do administrador do PostgreSQL: " POSTGRES_ADMIN_PASSWORD
    echo
  fi
  [[ -n "${POSTGRES_ADMIN_PASSWORD}" ]] || die "POSTGRES_ADMIN_PASSWORD não pode ficar vazio"

  echo "Criando/verificando banco e usuário do n8n no PostgreSQL..."
  docker run --rm --network host \
    -e PGPASSWORD="${POSTGRES_ADMIN_PASSWORD}" \
    postgres:17-alpine \
    psql "host=${POSTGRES_ADMIN_HOST} port=${POSTGRES_ADMIN_PORT} dbname=${POSTGRES_ADMIN_DB} user=${POSTGRES_ADMIN_USER}" \
    -v ON_ERROR_STOP=1 \
    -v app_user="${POSTGRES_USER}" \
    -v app_password="${POSTGRES_PASSWORD}" \
    -v app_db="${POSTGRES_DB}" \
    -c "SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'app_user', :'app_password') WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'app_user') \gexec" \
    -c "SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'app_user', :'app_password') \gexec" \
    -c "SELECT format('CREATE DATABASE %I OWNER %I', :'app_db', :'app_user') WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'app_db') \gexec"
}

write_files() {
  mkdir -p "${APP_DIR}/caddy_data" "${APP_DIR}/caddy_config"
  chmod 700 "${APP_DIR}"

  local encryption_key
  encryption_key="$(random_hex)"
  if [[ -f "${APP_DIR}/.env" ]]; then
    # Preserve a chave e a senha existentes em reinstalações.
    encryption_key="$(sed -n 's/^N8N_ENCRYPTION_KEY=//p' "${APP_DIR}/.env" | head -n1)"
    [[ -n "${encryption_key}" ]] || encryption_key="$(random_hex)"
    local old_password
    old_password="$(sed -n 's/^POSTGRES_PASSWORD=//p' "${APP_DIR}/.env" | head -n1)"
    [[ -n "${old_password}" ]] && POSTGRES_PASSWORD="${old_password}"
  fi
  if [[ -z "${POSTGRES_PASSWORD}" ]]; then
    read -r -s -p "Senha do usuário PostgreSQL do n8n: " POSTGRES_PASSWORD
    echo
  fi
  [[ -n "${POSTGRES_PASSWORD}" ]] || die "POSTGRES_PASSWORD não pode ficar vazio"

  cat > "${APP_DIR}/.env" <<EOF
N8N_DOMAIN=${N8N_DOMAIN}
N8N_DIRECT_PORT=${N8N_DIRECT_PORT}
N8N_DIRECT_BIND=${N8N_DIRECT_BIND}
POSTGRES_HOST=${POSTGRES_HOST}
POSTGRES_PORT=${POSTGRES_PORT}
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_SSL=${POSTGRES_SSL}
N8N_ENCRYPTION_KEY=${encryption_key}
GENERIC_TIMEZONE=America/Sao_Paulo
EOF
  chmod 600 "${APP_DIR}/.env"

  cat > "${APP_DIR}/compose.yml" <<'EOF'
services:
  n8n:
    image: docker.n8n.io/n8nio/n8n:latest
    restart: unless-stopped
    ports:
      - "${N8N_DIRECT_BIND}:${N8N_DIRECT_PORT}:5678"
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=${POSTGRES_HOST}
      - DB_POSTGRESDB_PORT=${POSTGRES_PORT}
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - DB_POSTGRESDB_SSL_ENABLED=${POSTGRES_SSL}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_HOST=${N8N_DOMAIN}
      - N8N_PROTOCOL=https
      - N8N_EDITOR_BASE_URL=https://${N8N_DOMAIN}/
      - WEBHOOK_URL=https://${N8N_DOMAIN}/
      - N8N_SECURE_COOKIE=true
      - GENERIC_TIMEZONE=${GENERIC_TIMEZONE}
      - TZ=${GENERIC_TIMEZONE}
    volumes:
      - n8n_data:/home/node/.n8n
    extra_hosts:
      - "host.docker.internal:host-gateway"

  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    environment:
      - N8N_DOMAIN=${N8N_DOMAIN}
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - n8n

volumes:
  n8n_data:
  caddy_data:
  caddy_config:
EOF

  cat > "${APP_DIR}/Caddyfile" <<'EOF'
{$N8N_DOMAIN} {
  encode gzip
  reverse_proxy n8n:5678
}
EOF
}

check_ports() {
  command_exists ss || return 0
  if ss -ltn | awk '{print $4}' | grep -Eq "(:80|:443)$"; then
    echo "Aviso: a porta 80 ou 443 já está ocupada. Caddy não poderá iniciar até liberar o serviço existente."
  fi
}

main() {
  need_root
  command_exists apt-get || die "este script pressupõe Debian/Ubuntu"
  install_docker
  check_ports
  write_files
  provision_postgres

  echo "Subindo n8n e Caddy..."
  cd "${APP_DIR}"
  docker compose --env-file .env -f compose.yml pull
  docker compose --env-file .env -f compose.yml up -d

  echo
  echo "Instalação concluída."
  echo "URL: https://${N8N_DOMAIN}"
  echo "Porta direta local: ${N8N_DIRECT_BIND}:${N8N_DIRECT_PORT}"
  echo "Logs: cd ${APP_DIR} && docker compose logs -f n8n"
  echo
  echo "Antes de acessar, crie o DNS A ${N8N_DOMAIN} apontando para o IP desta VPS."
}

main "$@"
