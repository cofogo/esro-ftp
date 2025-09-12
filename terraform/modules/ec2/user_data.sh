#!/bin/bash
set -Eeuo pipefail
# Enable logging
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting Mountpoint-backed FTP server setup..."

# --- Base packages ------------------------------------------------------------
yum update -y
yum install -y docker unzip wget -q

systemctl enable docker
systemctl start docker
usermod -a -G docker ec2-user || true

# --- Install Mountpoint for Amazon S3 -----------------------------------------
echo "Installing Mountpoint for Amazon S3..." | tee -a /var/log/ftp-setup.log
wget https://s3.amazonaws.com/mountpoint-s3-release/latest/mount-s3.rpm
yum install -y ./mount-s3.rpm

# --- Debug: variables ---------------------------------------------------------
echo "[$(date -Is)] FTP Username: ${ftp_username}"   >> /var/log/ftp-setup.log
echo "[$(date -Is)] S3 Bucket:    esro-ftp" >> /var/log/ftp-setup.log
echo "[$(date -Is)] AWS Region:   ${aws_region}"     >> /var/log/ftp-setup.log
echo "[$(date -Is)] AWS Access Key: ${aws_access_key_id}" >> /var/log/ftp-setup.log

# --- Mount S3 bucket with Mountpoint -----------------------------------------
echo "Mounting S3 bucket with Mountpoint..." | tee -a /var/log/ftp-setup.log
mkdir -p /mnt/s3
mount-s3 esro-ftp /mnt/s3 --region "${aws_region}" &

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
  -e FTP_USER="${ftp_username}" \
  -e FTP_PASS="${ftp_password}" \
  -p 21:21 \
  stilliard/pure-ftpd:hardened

# --- Diagnostics --------------------------------------------------------------
sleep 10
docker ps | tee -a /var/log/ftp-setup.log
docker logs --tail 20 s3-ftp | tee -a /var/log/ftp-setup.log

echo "Mountpoint-backed FTP server started successfully!" | tee -a /var/log/ftp-setup.log
