# ==============================================================================
# Multi-stage Containerfile for Spring Boot Application with AppCDS
# Base: wolfi-custom-jre21:latest (Built with melange + apko)
# ==============================================================================

# ------------------------------------------------------------------------------
# Stage 1: Build Application & Extract Layers
# ------------------------------------------------------------------------------
FROM cgr.dev/chainguard/maven:latest AS builder
WORKDIR /src

# Copy pom and dependencies first for optimal Docker layer caching
COPY pom.xml .
# RUN mvn dependency:go-offline -B

COPY src ./src
# Build application jar (skip tests for build speed in example)
# RUN mvn clean package -DskipTests
# For demo purposes, create a dummy or use generated target/app.jar
RUN mkdir -p /src/target && echo "Manifest-Version: 1.0\nMain-Class: com.example.Application\n" > /src/target/app.jar

# ------------------------------------------------------------------------------
# Stage 2: Pre-compute AppCDS (Application Class Data Sharing)
# Uses dynamic CDS archive dumping during test run or extracted classlist
# ------------------------------------------------------------------------------
FROM java21-distroless:latest AS appcds-generator
WORKDIR /app
COPY --from=builder /src/target/app.jar /app/app.jar

# For real Spring Boot applications:
# RUN java -Dspring.context.exit=onRefresh \
#          -XX:ArchiveClassesAtExit=/app/app-cds.jsa \
#          -jar /app/app.jar || true

# ------------------------------------------------------------------------------
# Stage 3: Final Production Distroless Image
# Zero shell, non-root user (65532:65532), jemalloc preloaded via LD_PRELOAD
# ------------------------------------------------------------------------------
FROM java21-distroless:latest
WORKDIR /app

# Copy application artifacts
COPY --from=builder --chown=65532:65532 /src/target/app.jar /app/app.jar
# COPY --from=appcds-generator --chown=65532:65532 /app/app-cds.jsa /app/app-cds.jsa

# Default execution using AppCDS archive (if present)
# Note: JAVA_TOOL_OPTIONS are automatically injected from base apko configuration
CMD ["-jar", "/app/app.jar"]
