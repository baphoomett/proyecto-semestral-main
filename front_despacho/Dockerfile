FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci

# 1. Primero copias todo (incluyendo tu archivo .env local con las IPs de AWS)
COPY . .

# 2. Corres el build directamente. Vite leerá el archivo .env por sí solo
RUN npm run build

FROM nginx:alpine
RUN adduser -S appuser
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]