# 🔥 Chama API

Backend do Chama, uma plataforma de videochamadas em tempo real construída com Elixir + Phoenix.

A Chama API é responsável por:

- Autenticação de usuários (JWT)
- Criação e gerenciamento de salas
- Convites e controle de acesso
- Chat em tempo real (WebSockets)
- Sinalização WebRTC (offer / answer / ICE)

---

## 📦 Requisitos

### Obrigatórios

- Elixir >= 1.15
- Erlang/OTP >= 24
- PostgreSQL 14+ (local) ou Docker

### Recomendados

- Docker + Docker Compose
- Node.js (opcional, apenas se for usar assets no Phoenix clássico)

Verifique versões instaladas:

```bash
elixir -v
psql --version || true
Docker --version || docker --version || true
```

---

## 🚀 Início Rápido (recomendado) — Postgres via Docker

1. Subir Postgres

```bash
docker run --name chama-postgres \
  -e POSTGRES_USER=chama_admin \
  -e POSTGRES_PASSWORD=abacate \
  -e POSTGRES_DB=chama_api_dev \
  -p 5432:5432 \
  -d postgres:16
```

Verifique se está rodando:

```bash
docker ps --filter name=chama-postgres
```

2. Instalar deps, criar e migrar banco

```bash
mix deps.get
mix ecto.create
mix ecto.migrate
```

3. Iniciar servidor

```bash
mix phx.server
```

A API ficará disponível em:

- http://localhost:4000

---

## 🧰 Setup Local (sem Docker)

Instalar PostgreSQL (Ubuntu/WSL):

```bash
sudo apt update
sudo apt install -y postgresql postgresql-contrib
sudo service postgresql start
```

Criar usuário e banco:

```bash
sudo -u postgres psql -c "CREATE USER chama_admin WITH PASSWORD 'abacate';"
sudo -u postgres psql -c "ALTER USER chama_admin CREATEDB;"
sudo -u postgres psql -c "CREATE DATABASE chama_api_dev OWNER chama_admin;"
```

Criar e migrar banco:

```bash
mix ecto.create
mix ecto.migrate
```

Subir servidor:

```bash
mix phx.server
```

---

## ▶️ Alternativa: Docker Compose (DB + hot-reload local)

Se preferir orquestrar o Postgres com Compose, crie um arquivo docker-compose.yml:

```yaml
version: "3.9"
services:
  db:
    image: postgres:16
    container_name: chama-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: chama_admin
      POSTGRES_PASSWORD: abacate
      POSTGRES_DB: chama_api_dev
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
volumes:
  pgdata:
```

Suba o serviço:

```bash
docker compose up -d
```

---

## 🔐 Variáveis de Ambiente úteis

A maioria das configs está em config/dev.exs, mas você pode sobrescrever em runtime com variáveis:

```bash
export DATABASE_URL="ecto://chama_admin:abacate@localhost:5432/chama_api_dev"
export SECRET_KEY_BASE=$(mix phx.gen.secret)
```

Para testes:

```bash
export MIX_ENV=test
mix ecto.create && mix ecto.migrate && mix test
```

---

## 🧪 Comandos úteis

- Rodar servidor

```bash
mix phx.server
```

- Rodar com IEx

```bash
iex -S mix phx.server
```

- Banco de dados

```bash
mix ecto.create
mix ecto.migrate
mix ecto.rollback
mix ecto.reset    # drop + create + migrate + seed (se configurado)
```

- Testes

```bash
mix test
mix test --failed
mix test test/chama_api/accounts_test.exs
```

- Qualidade (quando disponível no projeto)

```bash
mix format
mix credo --strict || true
mix dialyzer || true
mix precommit || true
```

---

## ⚙️ Configuração do Banco (dev)

Arquivo: config/dev.exs (resumo)

```elixir
config :chama_api, ChamaApi.Repo,
  username: "chama_admin",
  password: "abacate",
  hostname: "localhost",
  database: "chama_api_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
```

Para usar DATABASE_URL:

```elixir
config :chama_api, ChamaApi.Repo,
  url: System.get_env("DATABASE_URL"),
  pool_size: 10
```

---

## 🌐 Endpoints e exemplos (curl)

Rotas principais podem ser vistas em:

```bash
rg "scope\s|pipe_through|resources|post\s|get\s|put\s|patch\s|delete\s" lib/chama_api_web/router.ex || true
```

Fluxo típico de autenticação + salas (exemplos):

1. Criar usuário

```bash
curl -X POST http://localhost:4000/api/users \
  -H 'Content-Type: application/json' \
  -d '{"user": {"email": "alice@example.com", "password": "pass123"}}'
```

2. Login para obter JWT

```bash
curl -X POST http://localhost:4000/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email": "alice@example.com", "password": "pass123"}'
# resposta esperada: {"token": "<JWT>"}
```

Guarde o token:

```bash
TOKEN="<cole_o_token_aqui>"
```

3. Criar sala

```bash
curl -X POST http://localhost:4000/api/rooms \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"room": {"name": "Daily", "is_private": false}}'
```

4. Listar salas

```bash
curl -H "Authorization: Bearer $TOKEN" http://localhost:4000/api/rooms
```

5. Entrar na sala (sinalização/WebRTC normalmente ocorre via websockets, aqui apenas REST de exemplo)

```bash
curl -X POST http://localhost:4000/api/rooms/<room_id>/join \
  -H "Authorization: Bearer $TOKEN"
```

Observação: As rotas exatas dependem do router atual em lib/chama_api_web/router.ex.

---

## 🧩 WebSockets

- Conecte no endpoint do Phoenix Socket (ver lib/chama_api_web/endpoint.ex e router).
- Canais (channels) e tópicos podem ser expostos para chat e sinalização WebRTC.
- Exemplo de JS mínimo (substitua o caminho correto do socket):

```javascript
import { Socket } from "phoenix";

const token = localStorage.getItem("jwt");
const socket = new Socket("ws://localhost:4000/socket", { params: { token } });
socket.connect();

const channel = socket.channel("room:ROOM_ID", {});
channel
  .join()
  .receive("ok", (resp) => console.log("joined", resp))
  .receive("error", (err) => console.error("join error", err));
```

---

## 🧨 Troubleshooting

connection refused (localhost:5432)

- O Postgres não está rodando
- Verifique:

```bash
ss -lnt | grep 5432 || netstat -lnt | grep 5432 || true
```

- Se estiver usando Docker:

```bash
docker ps --filter name=chama-postgres
docker logs chama-postgres --tail 200
```

role "chama_admin" does not exist

- Crie o usuário no Postgres ou ajuste o config/dev.exs

```bash
sudo -u postgres psql -c "CREATE USER chama_admin WITH PASSWORD 'abacate';"
sudo -u postgres psql -c "ALTER USER chama_admin CREATEDB;"
```

database "chama_api_dev" does not exist

- Execute:

```bash
mix ecto.create
```

mix deps erros (compilação)

- Limpe e reinstale deps

```bash
mix deps.get --only dev
mix deps.compile
```

SECRET_KEY_BASE ausente em prod

```bash
export SECRET_KEY_BASE=$(mix phx.gen.secret)
```

---

## 🗺️ Roadmap

- [x] Auth + JWT
- [x] CRUD de salas
- [x] Convites e permissões
- [ ] Chat em tempo real
- [ ] Sinalização WebRTC
- [ ] Multi-usuário com SFU
- [ ] Deploy

---

## 🧭 Dicas do repositório

- Quando finalizar alterações, rode:

```bash
mix precommit
```

- Para HTTP client interno, prefira a lib Req já incluída (evitar HTTPoison/Tesla)

---

🔥 Chama — quando a conexão pega fogo.
