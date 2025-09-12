#!/bin/bash
set -Eeuo pipefail
# Enable logging
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting Mountpoint-backed FTP server setup..."

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
curl -L -o "/tmp/mount-s3-1.18.0-x86_64.rpm" \
  "https://s3.amazonaws.com/mountpoint-s3-release/1.18.0/x86_64/mount-s3-1.18.0-x86_64.rpm"

for i in {1..10}; do
  if yum install -y "/tmp/mount-s3-1.18.0-x86_64.rpm"; then
    echo "Installed mount-s3 version -1.18.0" | tee -a /var/log/ftp-setup.log
    break
  else
    echo "yum locked or install failed for mount-s3, retrying in 5s..." | tee -a /var/log/ftp-setup.log
    sleep 5
  fi
done

# --- Mount S3 bucket with Mountpoint ------------------------------------------
echo "Mounting S3 bucket with Mountpoint..." | tee -a /var/log/ftp-setup.log
mkdir -p /mnt/s3
mount-s3 "${s3_bucket_name}" /mnt/s3 --region "${aws_region}" &

sleep 5
ls -l /mnt/s3 >> /var/log/ftp-setup.log || echo "S3 mount failed" >> /var/log/ftp-setup.log

# --- Stop old FTP services ----------------------------------------------------
systemctl stop vsftpd >/dev/null 2>&1 || true
systemctl disable vsftpd >/dev/null 2>&1 || true
yum remove -y vsftpd >/dev/null 2>&1 || true
pkill -f vsftpd >/dev/null 2>&1 || true

# --- Run FTP container --------------------------------------------------------
echo "Starting FTP server container with S3 mount..." >> /var/log/ftp-setup.log
docker rm -f s3-ftp >/dev/null 2>&1 || true

docker run -d \
  --name s3-ftp \
  --restart unless-stopped \
  -v /mnt/s3:/home/ftpusers/data \
  -p 21:21 \
  -p 50000-50050:50000-50050 \
  stilliard/pure-ftpd:hardened \
  /bin/sh -c "pure-pw useradd ${ftp_username} -u ftpuser -d /home/ftpusers/data && \
              pure-pw mkdb && \
              exec /run.sh -p 50000:50050 -P $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo localhost)"


# --- TLS Support (Optional) ---------------------------------------------------
# To enable TLS, uncomment these lines:
# mkdir -p /etc/ssl/private
# openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
#   -keyout /etc/ssl/private/pure-ftpd.pem \
#   -out /etc/ssl/private/pure-ftpd.pem \
#   -subj "/CN=${PUBLIC_IP}"
# chmod 600 /etc/ssl/private/pure-ftpd.pem
# Add to docker run:  -e "TLS=2" -v /etc/ssl/private:/etc/ssl/private:ro

# --- Diagnostics --------------------------------------------------------------
sleep 10
docker ps | tee -a /var/log/ftp-setup.log
docker logs --tail 20 s3-ftp | tee -a /var/log/ftp-setup.log

echo "Mountpoint-backed FTP server started successfully!" | tee -a /var/log/ftp-setup.log
