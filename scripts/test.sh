set -e
MIX_ENV=test

docker-compose up -d

mix deps.get
mix test