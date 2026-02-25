# Python development environment
# Build: docker build -f examples/python.Dockerfile -t safe-ai-python .
FROM safe-ai-sandbox:latest

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3-venv \
    && rm -rf /var/lib/apt/lists/*
USER dev

RUN python3 -m venv /home/dev/.venv
ENV PATH="/home/dev/.venv/bin:$PATH"
