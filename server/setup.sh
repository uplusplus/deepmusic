#!/bin/bash
set -e

# 1. Create database if not exists
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='deepmusic'" | grep -q 1 || sudo -u postgres psql -c "CREATE DATABASE deepmusic;"
echo "[OK] Database ready"

# 2. Set password
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'postgres';"
echo "[OK] Password set"

# 3. Navigate to server directory
cd /mnt/c/Users/JOY/.openclaw/workspace/deepmusic-mimo/server

# 4. Create .env
cat > .env << 'EOF'
PORT=3000
NODE_ENV=development
DATABASE_URL="postgresql://postgres:postgres@localhost:5432/deepmusic?schema=public"
REDIS_URL="redis://localhost:6379"
JWT_SECRET=your-super-secret-jwt-key-change-in-production
JWT_EXPIRES_IN=7d
STORAGE_TYPE=local
UPLOAD_DIR=./uploads
EOF
echo "[OK] .env created"

# 5. Install dependencies
npm install 2>&1 | tail -3
echo "[OK] npm install done"

# 6. Run prisma migrations
npx prisma generate 2>&1 | tail -3
npx prisma db push 2>&1 | tail -5
echo "[OK] Prisma ready"

# 7. Check if Redis is needed
echo "Setup complete. Ready to start server."
