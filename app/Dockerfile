FROM mirror.gcr.io/library/python:3.12-alpine
WORKDIR /app
COPY server.py .
RUN mkdir -p /app/content
EXPOSE 8080
CMD ["python", "server.py"]
