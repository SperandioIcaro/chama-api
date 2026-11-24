#!/usr/bin/env bash
# Sobe a chama-api inteira com UM comando, sem Docker:  ./run.sh
#
# O que ele faz (tudo idempotente, pode rodar quantas vezes quiser):
#   1. instala Elixir/Erlang/PostgreSQL/compilador se faltar (Arch Linux, via pacman)
#   2. inicializa e liga o PostgreSQL local
#   3. cria o usuário/banco de desenvolvimento (chama_admin / abacate)
#   4. baixa dependências, roda as migrations e os seeds
#   5. inicia o servidor em http://localhost:4000
#
# Opções:  --reset   apaga e recria o banco de desenvolvimento antes de subir
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

DB_USER="chama_admin"
DB_PASS="abacate"
MIN_ELIXIR="1.15"
PGDATA_DIR="/var/lib/postgres/data" # padrão do Arch

RESET=0
for arg in "$@"; do
  case "$arg" in
    --reset) RESET=1 ;;
    -h | --help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "Opção desconhecida: $arg (use --help)"; exit 1 ;;
  esac
done

say() { printf '\n\033[1;33m▶ %s\033[0m\n' "$*"; }
ok() { printf '  \033[32m✔\033[0m %s\n' "$*"; }
die() { printf '\n\033[1;31m✖ %s\033[0m\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Roda um comando em silêncio: mostra só "✔ mensagem" (ou a saída completa se falhar).
step() {
  local msg="$1" log
  shift
  log="$(mktemp)"
  printf '  … %s' "$msg"
  if "$@" >"$log" 2>&1; then
    printf '\r  \033[32m✔\033[0m %s\033[K\n' "$msg"
    rm -f "$log"
  else
    printf '\r  \033[31m✖\033[0m %s\033[K\n' "$msg"
    cat "$log" >&2
    rm -f "$log"
    exit 1
  fi
}

# "1.17.3" >= "1.15" ?
version_ge() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]; }

# roda um comando como o usuário `postgres` (sem sudo se já formos ele)
as_postgres() {
  if [[ "$(id -un)" == "postgres" ]]; then "$@"; else sudo -u postgres "$@"; fi
}

# ───────── 1. ferramentas ─────────
say "Conferindo ferramentas"
missing=()
for tool in mix psql pg_isready gcc make git; do have "$tool" || missing+=("$tool"); done

if ((${#missing[@]} > 0)); then
  echo "  faltando: ${missing[*]}"
  if have pacman; then
    echo "  instalando com pacman (vai pedir sua senha de sudo)…"
    sudo pacman -S --needed --noconfirm elixir erlang postgresql base-devel git
  else
    die "Instale Elixir (>= $MIN_ELIXIR), Erlang/OTP, PostgreSQL (>= 14), gcc, make e git e rode de novo.
   (Este script instala sozinho apenas no Arch Linux.)"
  fi
fi

elixir_version="$(elixir -e 'IO.write(System.version())')"
version_ge "$elixir_version" "$MIN_ELIXIR" || die "Elixir $elixir_version é antigo; precisa de >= $MIN_ELIXIR."
ok "Elixir $elixir_version"

# ───────── 2. PostgreSQL ─────────
say "PostgreSQL"
# /var/lib/postgres só é legível pelo usuário `postgres`: a checagem precisa ser feita como ele.
if ! as_postgres test -f "$PGDATA_DIR/PG_VERSION"; then
  if have pacman; then
    echo "  inicializando o cluster em $PGDATA_DIR…"
    as_postgres initdb --locale=C.UTF-8 --encoding=UTF8 -D "$PGDATA_DIR" ||
      die "O initdb falhou. Se $PGDATA_DIR tiver restos de uma tentativa anterior, confira com: sudo ls -la $PGDATA_DIR"
  else
    die "Não achei um cluster PostgreSQL em $PGDATA_DIR. Inicialize-o (initdb) e rode de novo."
  fi
fi

if ! pg_isready -q -h localhost -p 5432; then
  echo "  iniciando o serviço…"
  if have systemctl; then
    sudo systemctl enable --now postgresql
  else
    die "Não consegui iniciar o PostgreSQL sozinho. Inicie-o e rode ./run.sh de novo."
  fi
  for _ in $(seq 1 30); do
    pg_isready -q -h localhost -p 5432 && break
    sleep 1
  done
fi
pg_isready -q -h localhost -p 5432 || die "PostgreSQL não respondeu em localhost:5432."
ok "PostgreSQL no ar"

# usuário de desenvolvimento (mesmo de config/dev.exs)
if [[ "$(as_postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'")" != "1" ]]; then
  as_postgres psql -v ON_ERROR_STOP=1 -c "CREATE ROLE $DB_USER WITH LOGIN CREATEDB PASSWORD '$DB_PASS'" >/dev/null
  ok "usuário $DB_USER criado"
else
  as_postgres psql -v ON_ERROR_STOP=1 -c "ALTER ROLE $DB_USER WITH LOGIN CREATEDB PASSWORD '$DB_PASS'" >/dev/null
  ok "usuário $DB_USER já existe"
fi

# ───────── 3. configuração local ─────────
if [[ ! -f .env && -f .env.example ]]; then
  cp .env.example .env
  ok ".env criado a partir do .env.example (preencha GITHUB_CLIENT_ID/SECRET para o login com GitHub)"
fi
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

# ───────── 4. Elixir / banco ─────────
export MIX_ENV=dev

say "Preparando o projeto"
step "Hex e Rebar" bash -c 'mix local.hex --force --if-missing && mix local.rebar --force --if-missing'
step "Dependências" mix deps.get
step "Compilando" mix compile
if ((RESET)); then step "Apagando o banco (--reset)" bash -c 'mix ecto.drop || true'; fi
step "Banco de dados" mix ecto.create
step "Migrations" mix ecto.migrate
step "Dados iniciais" mix run priv/repo/seeds.exs

# ───────── 5. servidor ─────────
say "API em http://localhost:4000  (Ctrl+C para parar)"
echo "  usuário de teste: admin@chama.local / Admin123!@#"
echo
exec mix phx.server
