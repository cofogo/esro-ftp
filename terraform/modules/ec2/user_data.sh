#!/bin/bash
set -Eeuo pipefail
# Enable logging
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting Mountpoint-backed FTP server setup..."

# --- Base packages ------------------------------------------------------------
for i in {1..10}; do
  if yum update -y; then
    break
  else
    echo "yum locked, retrying in 5s..." | tee -a /var/log/ftp-setup.log
    sleep 5
  fi
done

yum install -y docker unzip wget curl
systemctl enable docker
systemctl start docker
usermod -a -G docker ec2-user || true

# --- Debug: variables ---------------------------------------------------------
echo "[$(date -Is)] FTP Username: ${ftp_username}"   >> /var/log/ftp-setup.log
echo "[$(date -Is)] S3 Bucket:    ${s3_bucket_name}" >> /var/log/ftp-setup.log
echo "[$(date -Is)] AWS Region:   ${aws_region}"     >> /var/log/ftp-setup.log

# --- Install Mountpoint for Amazon S3 -----------------------------------------
echo "Installing Mountpoint for Amazon S3..." | tee -a /var/log/ftp-setup.log
curl -LO https://github.com/awslabs/mountpoint-s3/releases/latest/download/mount-s3.rpm

for i in {1..10}; do
  if yum install -y ./mount-s3.rpm; then
    break
  else
    echo "yum locked during mount-s3 install, retrying in 5s..." | tee -a /var/log/ftp-setup.log
    sleep 5
  fi
done

# --- Mount S3 bucket with Mountpoint -----------------------------------------
echo "Mounting S3 bucket with Mountpoint..." | tee -a /var/log/ftp-setup.log
mkdir -p /mnt/s3
mount-s3 "${s3_bucket_name}" /mnt/s3 --region "${aws_region}" &

sleep 5
ls -l /mnt/s3 >> /var/log/ftp-setup.log || echo "S3 mount failed" >> /var/log/ftp-setup.log

# --- Stop old FTP services ---------------------------------------------------
systemctl stop vsftpd >/dev/null 2>&1 || true
systemctl disable vsftpd >/dev/null 2>&1 || true
yum remove -y vsftpd >/dev/null 2>&1 || true
pkill -f vsftpd >/dev/null 2>&1 || true

# --- Run FTP container -------------------------------------------------------
echo "Starting FTP server container with S3 mount..." >> /var/log/ftp-setup.log
docker rm -f s3-ftp >/dev/null 2>&1 || true

docker run -d \
  --name s3-ftp \
  --restart unless-stopped \
  -v /mnt/s3:/home/ftpusers/data \
  -e FTP_USER="${ftp_username}" \
  -e FTP_PASS="${ftp_password}" \
  -e "ADDED_FLAGS=-p 50000:50050" \
  -p 21:21 \
  -p 50000-50050:50000-50050 \
  stilliard/pure-ftpd:hardened

# --- Diagnostics -------------------------------------------------------------
sleep 10
docker ps | tee -a /var/log/ftp-setup.log
docker logs --tail 20 s3-ftp | tee -a /var/log/ftp-setup.log

echo "Mountpoint-backed FTP server started successfully!" | tee -a /var/log/ftp-setup.log
