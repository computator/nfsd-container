FROM docker.io/library/alpine

LABEL org.opencontainers.image.source=https://github.com/computator/nfsd-container

RUN apk add --no-cache nfs-utils tini
COPY entrypoint.sh /

WORKDIR /srv
ENTRYPOINT ["/entrypoint.sh"]
CMD ["rpc.nfsd"]
EXPOSE 2049
