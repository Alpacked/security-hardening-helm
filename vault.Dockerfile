# Use Vault as the base image
FROM hashicorp/vault:1.15

WORKDIR /app

# Install necessery package and set up kubectl
RUN apk update && \
    apk add --no-cache curl jq bash && \
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

COPY vault-init.sh .

RUN chmod +x vault-init.sh

CMD ["/bin/bash", "vault-init.sh"]

