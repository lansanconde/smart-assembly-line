# =============================================================
# Multi-stage build — supervision-api Spring Boot
# Stage 1 : Maven build (JDK 21)
# Stage 2 : Runtime léger (JRE 21 Alpine ~180 MB)
# =============================================================

# ── Stage 1 : Build ──────────────────────────────────────────
FROM maven:3.9-eclipse-temurin-21-alpine AS build
WORKDIR /app

# Cache des dépendances Maven (layer séparé — rebuild rapide si seul le code change)
COPY pom.xml .
RUN mvn dependency:go-offline -q

# Build
COPY src ./src
RUN mvn package -DskipTests -q

# ── Stage 2 : Runtime ────────────────────────────────────────
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

COPY --from=build /app/target/*.jar app.jar

# Utilisateur non-root (bonne pratique sécurité conteneur)
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

EXPOSE 8080

# Graceful shutdown : Spring Boot attend la fin des requêtes en cours (SIGTERM)
ENTRYPOINT ["java", \
  "-Dserver.shutdown=graceful", \
  "-Dspring.lifecycle.timeout-per-shutdown-phase=20s", \
  "-jar", "app.jar"]
