FROM docker.io/library/alpine

LABEL org.opencontainers.image.source=https://github.com/computator/nfsd-container

RUN apk add --no-cache nfs-utils gettext-envsubst
COPY entrypoint.sh /

# mount an anonymous volume to /srv to make sure it's using a supported FS
VOLUME /srv

WORKDIR /srv
ENTRYPOINT ["/entrypoint.sh"]
EXPOSE 2049
