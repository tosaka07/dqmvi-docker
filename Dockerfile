FROM eclipse-temurin:25-jre

ARG NEOFORGE_VERSION=26.2.0.6-beta

WORKDIR /opt/server-template

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
    && curl -fL --retry 5 \
        -o neoforge-installer.jar \
        "https://maven.neoforged.net/releases/net/neoforged/neoforge/${NEOFORGE_VERSION}/neoforge-${NEOFORGE_VERSION}-installer.jar" \
    && java -jar neoforge-installer.jar --installServer \
    && rm neoforge-installer.jar \
    && rm -rf /var/lib/apt/lists/*

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 25565/tcp

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
