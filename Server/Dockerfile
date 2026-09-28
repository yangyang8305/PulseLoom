FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && useradd -r -u 10001 app
COPY app.py .
USER 10001
EXPOSE 8080
CMD ["uvicorn","app:app","--host","0.0.0.0","--port","8080","--workers","1","--no-access-log","--proxy-headers","--forwarded-allow-ips","172.30.90.0/24","--ws-max-size","65536"]
