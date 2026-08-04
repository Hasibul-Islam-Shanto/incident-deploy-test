FROM node:20-alpine

WORKDIR /app

COPY package*.json ./

RUN npm ci --omit=dev && npm cache clean --force

COPY src ./src

RUN chown -R node:node /app

ENV NODE_ENV=production \
    PORT=5000

EXPOSE 5000

USER node

HEALTHCHECK --interval=10s --timeout=5s --start-period=60s --retries=10 \
  CMD wget -q --spider http://127.0.0.1:5000/health || exit 1

CMD ["npm", "start"]