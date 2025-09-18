#!/bin/bash
set -Eeuo pipefail
# Enable logging
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting FTPS server with S3 sync..."

# --- Wait for yum lock ---
while fuser /var/run/yum.pid >/dev/null 2>&1; do
  echo "yum is locked, waiting 5s..." | tee -a /var/log/ftp-setup.log
  sleep 5
done

# --- Base packages ---
for i in {1..10}; do
  if yum update -y; then break
  else
    echo "yum locked, retrying in 5s..." | tee -a /var/log/ftp-setup.log
    sleep 5
  fi
done

yum install -y docker unzip wget curl awscli
systemctl enable docker
systemctl start docker
usermod -a -G docker ec2-user || true

# --- Debug: variables ---
echo "[$(date -Is)] FTP Username: ${ftp_username}"   >> /var/log/ftp-setup.log
echo "[$(date -Is)] S3 Bucket:    ${s3_bucket_name}" >> /var/log/ftp-setup.log
echo "[$(date -Is)] AWS Region:   ${aws_region}"     >> /var/log/ftp-setup.log

# --- Prepare local FTP home ---
mkdir -p /home/ftpusers/${ftp_username}
chown -R 1000:1000 /home/ftpusers

# --- Run FTPS container (delfer/alpine-ftp-server) ---
docker rm -f s3-ftp >/dev/null 2>&1 || true

echo "[$(date -Is)] Starting FTPS server with self-signed SSL..." | tee -a /var/log/ftp-setup.log

mkdir -p /etc/letsencrypt

yum install -y certbot
certbot certonly --standalone \
  --preferred-challenges http \
  -n --agree-tos \
  --email tech@wecodeforgood.com \
  -d ftp.esro.wecodeforgood.com

docker run -d \
    --name ftp \
    -p "21:21" \
    -p 21000-21010:21000-21010 \
    -v "/etc/letsencrypt:/etc/letsencrypt:ro" \
    -e USERS="${ftp_username}|${ftp_password}" \
    -e ADDRESS=ftp.esro.wecodeforgood.com \
    -e TLS_CERT="/etc/letsencrypt/live/ftp.esro.wecodeforgood.com/fullchain.pem" \
    -e TLS_KEY="/etc/letsencrypt/live/ftp.esro.wecodeforgood.com/privkey.pem" \
    delfer/alpine-ftp-server

sleep 10
docker ps | tee -a /var/log/ftp-setup.log
docker logs --tail 20 ftp | tee -a /var/log/ftp-setup.log


# --- Background sync to S3 ---
cat >/usr/local/bin/s3-sync.sh <<'EOF'
#!/bin/bash
while true; do
  aws s3 sync /home/ftpusers/${ftp_username} s3://${s3_bucket_name}/ \
    --region ${aws_region} --exact-timestamps >> /var/log/ftp-sync.log 2>&1
  # Remove local files after syncing
  find /home/ftpusers/${ftp_username} -type f -delete
  sleep 60
done
EOF
chmod +x /usr/local/bin/s3-sync.sh

nohup /usr/local/bin/s3-sync.sh >> /var/log/ftp-sync.log 2>&1 &

echo "FTPS server with S3 sync started successfully!" | tee -a /var/log/ftp-setup.log
