# 🔥 Chama API

Backend do **Chama**, uma plataforma de videochamadas em tempo real construída com **Elixir + Phoenix**.

A Chama API é responsável por:

- Autenticação de usuários (JWT)
- Criação e gerenciamento de salas
- Convites e controle de acesso
- Chat em tempo real (WebSockets)
- Sinalização WebRTC (offer / answer / ICE)

---

# 📦 Requisitos

## Obrigatórios

- Elixir >= 1.15
- Erlang/OTP >= 24
- PostgreSQL (local) ou Docker

## Recomendados

- Docker + Docker Compose
- Node.js (opcional)

---

# 🚀 Setup Rápido (Recomendado) — Postgres via Docker

## 1) Subir Postgres

docker run --name chama-postgres \
 -e POSTGRES_USER=chama_admin \
 -e POSTGRES_PASSWORD=abacate \
 -e POSTGRES_DB=chama_api_dev \
 -p 5432:5432 \
 -d postgres:16

Verifique se está rodando:

docker ps

---

## 2) Criar banco e rodar migrations

mix ecto.create
mix ecto.migrate

---

## 3) Iniciar servidor

mix phx.server

A API estará disponível em:

http://localhost:4000

---

# 🧰 Setup Local (Sem Docker)

## Instalar PostgreSQL (Ubuntu / WSL)

sudo apt update
sudo apt install -y postgresql postgresql-contrib
sudo service postgresql start

## Criar usuário e banco

sudo -u postgres psql -c "CREATE USER chama_admin WITH PASSWORD 'abacate';"
sudo -u postgres psql -c "ALTER USER chama_admin CREATEDB;"
sudo -u postgres psql -c "CREATE DATABASE chama_api_dev OWNER chama_admin;"

## Criar banco pelo Phoenix

mix ecto.create
mix ecto.migrate

## Subir servidor

mix phx.server

---

# 🧪 Comandos Úteis

Rodar servidor:

mix phx.server

Rodar com IEx:

iex -S mix phx.server

Criar banco:

mix ecto.create

Rodar migrations:

mix ecto.migrate

Resetar banco (apaga tudo):

mix ecto.reset

Rodar testes:

mix test

---

# ⚙️ Configuração do Banco (dev)

Arquivo: config/dev.exs

config :chama_api, ChamaApi.Repo,
username: "chama_admin",
password: "abacate",
hostname: "localhost",
database: "chama_api_dev",
stacktrace: true,
show_sensitive_data_on_connection_error: true,
pool_size: 10

---

# 🧨 Troubleshooting

## connection refused (localhost:5432)

O Postgres não está rodando.

Verifique:

ss -lnt | grep 5432

Se estiver usando Docker:

docker ps
docker logs chama-postgres

---

## role "chama_admin" does not exist

Crie o usuário no Postgres ou ajuste o config/dev.exs.

---

## database "chama_api_dev" does not exist

Execute:

mix ecto.create

---

# 🗺️ Roadmap

- [ ] Auth + JWT
- [ ] CRUD de salas
- [ ] Convites e permissões
- [ ] Chat em tempo real
- [ ] Sinalização WebRTC
- [ ] Multi-usuário com SFU
- [ ] Deploy

---

🔥 Chama — quando a conexão pega fogo.
