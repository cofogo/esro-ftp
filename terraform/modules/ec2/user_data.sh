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

yum install -y docker unzip wget curl awscli telnet net-tools
systemctl enable docker
systemctl start docker
usermod -a -G docker ec2-user || true

# Install openssl for self-signed certificates
yum install -y openssl

# --- Debug: variables ---
echo "[$(date -Is)] FTP Username: ${ftp_username}"   >> /var/log/ftp-setup.log
echo "[$(date -Is)] S3 Bucket:    ${s3_bucket_name}" >> /var/log/ftp-setup.log
echo "[$(date -Is)] AWS Region:   ${aws_region}"     >> /var/log/ftp-setup.log

# --- Obtain self-signed SSL certificate ---
DOMAIN="${ftp_domain}"
echo "[$(date -Is)] FTP Domain: $DOMAIN" >> /var/log/ftp-setup.log

# Always generate self-signed certificate for the provided domain
echo "[$(date -Is)] Generating self-signed SSL certificate for $DOMAIN..." | tee -a /var/log/ftp-setup.log

# Create directory for certificates
mkdir -p /etc/ssl/private
mkdir -p /etc/ssl/certs

# Generate self-signed certificate valid for 365 days
# Create a temporary config file for the certificate with SAN extension
cat > /tmp/cert.conf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C=US
ST=State
L=City
O=Organization
OU=OrgUnit
CN=$DOMAIN

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:$DOMAIN
EOF

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/$DOMAIN.key \
  -out /etc/ssl/certs/$DOMAIN.crt \
  -config /tmp/cert.conf \
  -extensions v3_req >> /var/log/ftp-setup.log 2>&1

# Clean up temp config file
rm -f /tmp/cert.conf

if [ -f "/etc/ssl/certs/$DOMAIN.crt" ] && [ -f "/etc/ssl/private/$DOMAIN.key" ]; then
  echo "[$(date -Is)] Self-signed SSL certificate generated successfully" | tee -a /var/log/ftp-setup.log
  
  # Ensure proper permissions for certificates
  chmod 644 /etc/ssl/certs/$DOMAIN.crt
  chmod 600 /etc/ssl/private/$DOMAIN.key
  
  # Set paths as they will appear inside the container (mounted volume)
  TLS_CERT="/etc/ssl/certs/$DOMAIN.crt"
  TLS_KEY="/etc/ssl/private/$DOMAIN.key"
  ADDRESS=$DOMAIN
  
  # Debug: Show certificate info
  echo "[$(date -Is)] Certificate file: $TLS_CERT" | tee -a /var/log/ftp-setup.log
  echo "[$(date -Is)] Key file: $TLS_KEY" | tee -a /var/log/ftp-setup.log
  ls -la /etc/ssl/certs/$DOMAIN.crt /etc/ssl/private/$DOMAIN.key | tee -a /var/log/ftp-setup.log
else
  echo "[$(date -Is)] SSL certificate generation failed" | tee -a /var/log/ftp-setup.log
  exit 1
fi

# --- Prepare local FTP home ---
mkdir -p /home/ftpusers/${ftp_username}
chown -R 1000:1000 /home/ftpusers

# --- Run FTPS container (delfer/alpine-ftp-server) ---
docker rm -f s3-ftp >/dev/null 2>&1 || true

echo "[$(date -Is)] Starting FTPS server with self-signed SSL..." | tee -a /var/log/ftp-setup.log

# Debug: Show environment variables that will be passed to container
echo "[$(date -Is)] Docker environment variables:" | tee -a /var/log/ftp-setup.log
echo "  USERS=${ftp_username}|[PASSWORD_HIDDEN]" | tee -a /var/log/ftp-setup.log
echo "  ADDRESS=$ADDRESS" | tee -a /var/log/ftp-setup.log
echo "  TLS_CERT=$TLS_CERT" | tee -a /var/log/ftp-setup.log
echo "  TLS_KEY=$TLS_KEY" | tee -a /var/log/ftp-setup.log

# First try without TLS to see if the basic FTP works
echo "[$(date -Is)] Starting FTP server (will try with and without TLS)..." | tee -a /var/log/ftp-setup.log

docker run -d \
  --name s3-ftp \
  --restart unless-stopped \
  -v /home/ftpusers:/ftp \
  -v /etc/ssl:/etc/ssl:ro \
  -p 21:21 \
  -p 990:990 \
  -p 21000-21010:21000-21010 \
  -e USERS="${ftp_username}|${ftp_password}" \
  -e ADDRESS="$ADDRESS" \
  -e TLS_CERT="$TLS_CERT" \
  -e TLS_KEY="$TLS_KEY" \
  -e MIN_PORT=21000 \
  -e MAX_PORT=21010 \
  -e PASV_ADDRESS="$ADDRESS" \
  -e IMPLICIT_SSL=1 \
  delfer/alpine-ftp-server

sleep 10
docker ps | tee -a /var/log/ftp-setup.log
docker logs --tail 20 s3-ftp | tee -a /var/log/ftp-setup.log

# Wait a bit more and check if the container is still running
sleep 10
if docker ps | grep -q s3-ftp; then
  echo "[$(date -Is)] FTPS container is running successfully" | tee -a /var/log/ftp-setup.log
  
  # Additional debugging - check if FTP service is actually listening
  echo "[$(date -Is)] Checking if FTP services are listening on ports 21 and 990..." | tee -a /var/log/ftp-setup.log
  sleep 5
  
  # Test local connection to FTP
  if netstat -tuln | grep -q ":21 "; then
    echo "[$(date -Is)] FTP service is listening on port 21" | tee -a /var/log/ftp-setup.log
  else
    echo "[$(date -Is)] WARNING: FTP service is NOT listening on port 21" | tee -a /var/log/ftp-setup.log
  fi
  
  if netstat -tuln | grep -q ":990 "; then
    echo "[$(date -Is)] FTPS service is listening on port 990" | tee -a /var/log/ftp-setup.log
  else
    echo "[$(date -Is)] WARNING: FTPS service is NOT listening on port 990" | tee -a /var/log/ftp-setup.log
  fi
  
  # Show all listening ports
  echo "[$(date -Is)] All listening ports:" | tee -a /var/log/ftp-setup.log
  netstat -tuln | grep LISTEN | tee -a /var/log/ftp-setup.log
  
  # Check container logs for any errors
  echo "[$(date -Is)] Container logs (last 50 lines):" | tee -a /var/log/ftp-setup.log
  docker logs --tail 50 s3-ftp | tee -a /var/log/ftp-setup.log
  
  # Test basic connectivity to container
  echo "[$(date -Is)] Testing connectivity to container on both ports..." | tee -a /var/log/ftp-setup.log
  timeout 10 telnet localhost 21 || echo "[$(date -Is)] Telnet to localhost:21 failed" | tee -a /var/log/ftp-setup.log
  timeout 10 telnet localhost 990 || echo "[$(date -Is)] Telnet to localhost:990 failed" | tee -a /var/log/ftp-setup.log
  
else
  echo "[$(date -Is)] FTPS container failed to start or exited" | tee -a /var/log/ftp-setup.log
  docker logs s3-ftp | tee -a /var/log/ftp-setup.log
  exit 1
fi


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