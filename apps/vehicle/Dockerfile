# JVM image for the vehicle demo. Build context is a directory holding
# `quarkus-app/`, built inside the DevBox (`mvn package`) and copied out.
#
#   docker buildx build --platform linux/amd64 -f apps/vehicle/Dockerfile \
#     -t ghcr.io/htl-leonding/vehicle:<tag> --push <dir-with-quarkus-app>

FROM eclipse-temurin:21-jre

WORKDIR /deployments
# Library layers first, so an app-only change reuses them
COPY --chown=1001:0 quarkus-app/lib/ lib/
COPY --chown=1001:0 quarkus-app/*.jar ./
COPY --chown=1001:0 quarkus-app/app/ app/
COPY --chown=1001:0 quarkus-app/quarkus/ quarkus/

USER 1001
EXPOSE 8080
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75 -Dquarkus.http.host=0.0.0.0"
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /deployments/quarkus-run.jar"]
