#!/bin/bash
set -Eeuo pipefail
# Enable logging
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting FTP server with S3 sync..."

# --- Wait for yum lock --------------------------------------------------------
while fuser /var/run/yum.pid >/dev/null 2>&1; do
  echo "yum is locked, waiting 5s..." | tee -a /var/log/ftp-setup.log
  sleep 5
done

# --- Base packages ------------------------------------------------------------
for i in {1..10}; do
  if yum update -y; then
    break
  else
    echo "yum locked, retrying in 5s..." | tee -a /var/log/ftp-setup.log
    sleep 5
  fi
done

yum install -y docker unzip wget curl awscli
systemctl enable docker
systemctl start docker
usermod -a -G docker ec2-user || true

# --- Debug: variables ---------------------------------------------------------
echo "[$(date -Is)] FTP Username: ${ftp_username}"   >> /var/log/ftp-setup.log
echo "[$(date -Is)] S3 Bucket:    ${s3_bucket_name}" >> /var/log/ftp-setup.log
echo "[$(date -Is)] AWS Region:   ${aws_region}"     >> /var/log/ftp-setup.log

# --- Stop old FTP services ----------------------------------------------------
systemctl stop vsftpd >/dev/null 2>&1 || true
systemctl disable vsftpd >/dev/null 2>&1 || true
yum remove -y vsftpd >/dev/null 2>&1 || true
pkill -f vsftpd >/dev/null 2>&1 || true

# --- Prepare local FTP home ---------------------------------------------------
mkdir -p /home/ftpusers/${ftp_username}
chown -R 1000:1000 /home/ftpusers

# --- Run FTP container --------------------------------------------------------
echo "Starting FTP server container with local home..." >> /var/log/ftp-setup.log
docker rm -f s3-ftp >/dev/null 2>&1 || true

docker run -d \
  --name s3-ftp \
  --restart unless-stopped \
  -v /home/ftpusers:/home/ftpusers \
  -p 21:21 \
  -p 50000-50050:50000-50050 \
  -e FTP_USER_NAME=${ftp_username} \
  -e FTP_USER_PASS=${ftp_password} \
  -e FTP_USER_HOME=/home/ftpusers/${ftp_username} \
  stilliard/pure-ftpd:hardened \
  /run.sh -p 50000:50050 -P $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

sleep 10
docker ps | tee -a /var/log/ftp-setup.log
docker logs --tail 20 s3-ftp | tee -a /var/log/ftp-setup.log

# --- Background sync to S3 ---------------------------------------------------
cat >/usr/local/bin/s3-sync.sh <<'EOF'
#!/bin/bash
while true; do
  aws s3 sync /home/ftpusers/${ftp_username} s3://${s3_bucket_name}/ \
    --region ${aws_region} --exact-timestamps
  # Remove local files after syncing
  find /home/ftpusers/${ftp_username} -type f -delete
  sleep 10
done
EOF
chmod +x /usr/local/bin/s3-sync.sh
nohup /usr/local/bin/s3-sync.sh >> /var/log/ftp-sync.log 2>&1 &

echo "FTP server with S3 sync started successfully!" | tee -a /var/log/ftp-setup.log
