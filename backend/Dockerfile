FROM node:22-alpine

WORKDIR /app
COPY package.json server.js ./
COPY src ./src

ENV NODE_ENV=production
ENV PORT=3000
ENV DATA_DIR=/data
VOLUME /data

EXPOSE 3000
USER node
CMD ["node", "server.js"]
