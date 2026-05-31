FROM node:20-alpine

RUN apk add --no-cache \
    bash \
    curl \
    docker-cli \
    docker-cli-compose

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY src/ ./src/

EXPOSE 8787

CMD ["node", "src/server.js"]
