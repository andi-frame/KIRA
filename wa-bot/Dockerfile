FROM node:22-slim

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY src ./src

# Sesi WhatsApp disimpan di volume (AUTH_DIR) supaya tidak perlu scan QR ulang setelah restart.
RUN mkdir -p /app/auth && chown -R node:node /app
USER node

CMD ["node", "src/index.js"]
