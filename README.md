# 🔥 Chama API

Backend do Chama, uma plataforma de videochamadas em tempo real construída com Elixir + Phoenix.

A Chama API é responsável por:

- Autenticação de usuários (JWT)
- Criação e gerenciamento de salas
- Convites e controle de acesso
- Chat em tempo real (WebSockets)
- Sinalização WebRTC (offer / answer / ICE)

---

## ⚡ Rodar em um comando (sem Docker)

```bash
./run.sh            # instala o que faltar (Arch), sobe o Postgres, migra, popula e inicia a API
./run.sh --reset    # igual, mas apagando e recriando o banco de desenvolvimento antes
```

A API sobe em `http://localhost:4000`. Usuário de teste: `admin@chama.local` / `Admin123!@#`.

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

## 🔐 Variáveis de Ambiente

Em desenvolvimento tudo tem padrão (veja `.env.example`). Em produção, só `DATABASE_URL`,
`SECRET_KEY_BASE`, `GUARDIAN_SECRET_KEY` e `CORS_ORIGINS` são obrigatórias (o app não sobe sem elas).

| Variável | Para quê |
| --- | --- |
| `GITHUB_CLIENT_ID` / `GITHUB_CLIENT_SECRET` | Login com GitHub (OAuth App). Sem elas, `POST /api/auth/github` responde 503. |
| `GUARDIAN_SECRET_KEY` | Assina os JWT. Gere com `mix guardian.gen.secret`. **Obrigatória em prod.** |
| `CORS_ORIGINS` | Origens do front (CORS **e** WebSocket), separadas por vírgula. Ex.: `https://chama.exemplo.com` |
| `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, `PORT` | Padrão do Phoenix (produção). |

Para testes:

```bash
MIX_ENV=test mix ecto.create && mix ecto.migrate && mix test
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

## 🌐 Endpoints

Autenticação: `Authorization: Bearer <token>` (exceto as rotas públicas).

| Método | Rota | O que faz |
| --- | --- | --- |
| POST | `/api/register` | Cria conta `{ user: { name, email, password } }` (senha 8–72, com letra e número) |
| POST | `/api/login` | `{ email, password }` → `{ token, user }` |
| POST | `/api/auth/github` | `{ code, redirect_uri }` → `{ token, user }` (web e mobile usam o mesmo endpoint) |
| GET | `/api/me` | Usuário logado |
| GET | `/api/rooms` | Sala geral + salas privadas **em que você está** (com `participants_count`) |
| POST | `/api/rooms` | Cria sala privada `{ room: { name } }` (você vira `host`) |
| GET | `/api/rooms/general` | Sala geral |
| GET | `/api/rooms/by-code/:code` | Dados da sala |
| POST | `/api/rooms/by-code/:code/join` | Entra na sala (o código é o convite; idempotente) |
| POST | `/api/rooms/by-code/:code/leave` | Sai da sala |
| GET | `/api/rooms/by-code/:code/participants` | Participantes ativos (com nome e avatar) |
| GET | `/api/rooms/by-code/:code/messages?limit=50` | Histórico do chat |
| PATCH / DELETE | `/api/rooms/:id` | Editar/apagar — **só o dono**, nunca a sala geral |

Exemplo:

```bash
curl -s -X POST http://localhost:4000/api/login -H 'Content-Type: application/json' \
  -d '{"email":"admin@chama.local","password":"Admin123!@#"}'
TOKEN="<cole_o_token>"
curl -s -X POST http://localhost:4000/api/rooms -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{"room":{"name":"Daily"}}'
```

Erros seguem `{ error: "codigo", message: "texto em português", status }`; validações trazem `fields`.

---

## 🧩 WebSockets

Conecte em `ws://localhost:4000/socket/websocket?token=<JWT>` (o Phoenix JS acrescenta `/websocket`).

| Canal | Para quê |
| --- | --- |
| `user:<meu_id>` | Canal pessoal: recebe `invite:incoming`, `invite:accepted`, `invite:declined` |
| `lobby:global` | Presença global (quem está online) e envio de convites: `invite:send {to, room_code}`, `invite:accept`, `invite:decline` |
| `room:<code>` | Sala (`room:geral` é a sala geral) |

Eventos do `room:<code>`:

- `chat:new {body}` → todos recebem `chat:message` (salvo no banco; nome/avatar vêm do servidor)
- `call:join` → responde `{peers: [ids]}` de quem já está na chamada (máx. 6 pessoas); `call:leave`; `call:media {mic, cam}`
- `signal:offer | signal:answer {to, sdp}`, `signal:ice {to, candidate}` → entregues **só** ao `to`
- Presença: `presence_state` / `presence_diff` com `name`, `avatar_url`, `in_call`, `mic`, `cam`

```javascript
import { Socket } from "phoenix";

const socket = new Socket("ws://localhost:4000/socket", { params: { token } });
socket.connect();

const channel = socket.channel("room:geral", {});
channel.join().receive("ok", () => console.log("na sala geral"));
channel.on("chat:message", (m) => console.log(m.user_name, m.body));
channel.push("chat:new", { body: "oi!" });
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
