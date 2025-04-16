FROM docker.io/library/alpine

LABEL org.opencontainers.image.source=https://github.com/computator/nfsd-container

RUN apk add --no-cache nfs-utils gettext-envsubst tini
COPY entrypoint.sh /

# mount an anonymous volume to /srv to make sure it's using a supported FS
VOLUME /srv

WORKDIR /srv
VOLUME /var/lib/nfs
ENTRYPOINT ["/entrypoint.sh"]
EXPOSE 2049
