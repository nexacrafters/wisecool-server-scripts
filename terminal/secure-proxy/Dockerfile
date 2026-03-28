FROM node:20-alpine

WORKDIR /app

COPY package.json ./
RUN npm install --production

COPY server.js ./

ENV PORT=3001
ENV TTYD_HOST=172.20.0.1
ENV TTYD_PORT=7681
ENV API_URL=https://api.wisecool.tn/v1/api

EXPOSE 3001

CMD ["node", "server.js"]
