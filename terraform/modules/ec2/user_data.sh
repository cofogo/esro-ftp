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

# Stop and remove any conflicting FTP services completely
systemctl stop vsftpd >/dev/null 2>&1 || true
systemctl disable vsftpd >/dev/null 2>&1 || true
yum remove -y vsftpd >/dev/null 2>&1 || true
pkill -f vsftpd >/dev/null 2>&1 || true

# Check what's running on port 21 before starting
echo "Checking port 21 before starting container:" >> /var/log/ftp-setup.log
netstat -tulpn | grep :21 >> /var/log/ftp-setup.log 2>&1 || echo "Port 21 is free" >> /var/log/ftp-setup.log

# Create the directories that the factual/s3-backed-ftp container expects
mkdir -p /home/aws/s3bucket/ftp-users
mkdir -p /var/run/vsftpd/empty
mkdir -p /etc/vsftpd
chmod 755 /home/aws/s3bucket/ftp-users
chmod 755 /var/run/vsftpd/empty

# Run the S3-backed FTP server with volume mounts for the required directories
echo "Starting factual/s3-backed-ftp container..." >> /var/log/ftp-setup.log
docker run -d \
  --name s3-ftp \
  --restart unless-stopped \
  -v /home/aws/s3bucket/ftp-users:/home/aws/s3bucket/ftp-users \
  -v /var/run/vsftpd/empty:/var/run/vsftpd/empty \
  -e AWS_DEFAULT_REGION="${aws_region}" \
  -e AWS_ACCESS_KEY_ID="${aws_access_key_id}" \
  -e AWS_SECRET_ACCESS_KEY="${aws_secret_access_key}" \
  -e S3_BUCKET="${s3_bucket_name}" \
  -e FTP_USER="${ftp_username}" \
  -e FTP_PASS="${ftp_password}" \
  -p 21:21 \
  factual/s3-backed-ftp

echo "Container started, checking port 21 again:" >> /var/log/ftp-setup.log
sleep 5
netstat -tulpn | grep :21 >> /var/log/ftp-setup.log 2>&1 || echo "Port 21 not found" >> /var/log/ftp-setup.log

echo "S3-backed FTP server started successfully!" >> /var/log/ftp-setup.log

# --- Wait for container to start ---------------------------------------------
sleep 10

# --- Diagnostics -------------------------------------------------------------
echo "FTP server setup completed!" | tee -a /var/log/ftp-setup.log
echo "Container status:"           | tee -a /var/log/ftp-setup.log
docker ps                          | tee -a /var/log/ftp-setup.log
echo "Container logs (last 20 lines):" | tee -a /var/log/ftp-setup.log
docker logs --tail 20 s3-ftp | tee -a /var/log/ftp-setup.log

# Check if s3-fuse is failing and get detailed error
echo "Checking s3-fuse specific logs:" | tee -a /var/log/ftp-setup.log
docker exec s3-ftp cat /var/log/s3fs.log 2>/dev/null | tee -a /var/log/ftp-setup.log || echo "No s3fs.log found" | tee -a /var/log/ftp-setup.log

# Check if the S3 bucket exists and is accessible
echo "Testing S3 bucket access:" | tee -a /var/log/ftp-setup.log
docker exec s3-ftp aws s3 ls s3://${s3_bucket_name}/ 2>&1 | tee -a /var/log/ftp-setup.log || echo "S3 bucket access failed" | tee -a /var/log/ftp-setup.log

# Check AWS credentials inside container
echo "Checking AWS credentials:" | tee -a /var/log/ftp-setup.log
docker exec s3-ftp env | grep AWS | tee -a /var/log/ftp-setup.log

echo "Done."
