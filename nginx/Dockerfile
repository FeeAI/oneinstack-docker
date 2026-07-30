ARG NGINX_VERSION=stable
FROM nginx:${NGINX_VERSION}-alpine

LABEL org.opencontainers.image.title="OneinStack Nginx"
LABEL org.opencontainers.image.source="https://github.com/FeeAI/oneinstack"

COPY nginx.conf /etc/nginx/nginx.conf
COPY conf.d /etc/nginx/conf.d

RUN nginx -t

EXPOSE 80
