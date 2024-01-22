FROM alpine:3.19.0

RUN adduser -D vaultuser \
    apk update && \
    apk add --no-cache jq curl && \
    rm -rf /var/cache/apk/*

USER vaultuser
WORKDIR /home/vaultuser

COPY --chown=vaultuser:vaultuser ./scripts .
RUN chmod +x ./*.sh
