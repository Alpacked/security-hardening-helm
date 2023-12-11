# Use Vault as the base image
FROM hashicorp/vault:1.15

WORKDIR /app

# Install necessery package and set up kubectl
RUN apk update && \
    apk add --no-cache curl bash && \
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

COPY vault-init-eso.sh .

# Set appropriate permissions for the script
RUN chmod +x vault-init-eso.sh

# The default command to run when the container starts
CMD ["/bin/bash", "vault-init-eso.sh"]

