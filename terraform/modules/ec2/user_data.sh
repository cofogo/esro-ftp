#!/bin/bash
set -Eeuo pipefail
# Enable logging
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting S3-backed FTP server setup..."

# --- Base packages ------------------------------------------------------------
yum update -y
yum install -y docker
systemctl enable docker
systemctl start docker
usermod -a -G docker ec2-user || true

# --- Debug: variables ---------------------------------------------------------
echo "[$(date -Is)] FTP Username: ${ftp_username}"   >> /var/log/ftp-setup.log
echo "[$(date -Is)] S3 Bucket:    ${s3_bucket_name}" >> /var/log/ftp-setup.log
echo "[$(date -Is)] AWS Region:    ${aws_region}"     >> /var/log/ftp-setup.log

# --- Start S3-backed FTP container -------------------------------------------
echo "Starting S3-backed FTP container..." >> /var/log/ftp-setup.log

# Remove old container if present
docker rm -f s3-ftp >/dev/null 2>&1 || true

# Stop any conflicting FTP services
systemctl stop vsftpd >/dev/null 2>&1 || true
systemctl disable vsftpd >/dev/null 2>&1 || true

# Run the S3-backed FTP server (uses IAM role credentials automatically)
docker run -d \
  --name s3-ftp \
  --restart unless-stopped \
  -e AWS_DEFAULT_REGION="${aws_region}" \
  -e S3_BUCKET="${s3_bucket_name}" \
  -e FTP_USER="${ftp_username}" \
  -e FTP_PASS="${ftp_password}" \
  -p 21:21 \
  factual/s3-backed-ftp

echo "S3-backed FTP server started successfully!" >> /var/log/ftp-setup.log

# --- Wait for container to start ---------------------------------------------
sleep 10

# --- Diagnostics -------------------------------------------------------------
echo "FTP server setup completed!" | tee -a /var/log/ftp-setup.log
echo "Container status:"           | tee -a /var/log/ftp-setup.log
docker ps                          | tee -a /var/log/ftp-setup.log
echo "Container logs (last 20 lines):" | tee -a /var/log/ftp-setup.log
docker logs --tail 20 s3-ftp | tee -a /var/log/ftp-setup.log
echo "Done."
