package server

import (
	"context"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/cofogo/esro-ftp-trigger/internal/awsutil"
)

const DefaultWarningWindow = 14 * 24 * time.Hour

// CertExpiresSoon checks whether the certificate at certPath is expiring within warningBefore.
func CertExpiresSoon(certPath string, warningBefore time.Duration) (bool, error) {
	data, err := os.ReadFile(certPath)
	if err != nil {
		if os.IsNotExist(err) {
			return true, nil
		}
		return true, err
	}
	block, _ := pem.Decode(data)
	if block == nil {
		return true, errors.New("invalid PEM data")
	}
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return true, err
	}
	return time.Until(cert.NotAfter) <= warningBefore, nil
}

// FileExists checks if a file exists.
func FileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

// EnsureCertificates downloads certificate and key from S3 using the awsutil package.
// bucket: S3 bucket name
// domain: a logical name used to create a local subdirectory (e.g. "client" or your server domain)
// s3SubDir: subdirectory within S3 (e.g. "endpoints/<domain>")
// dataDir: local base directory to store certificates
// certFileName: name of the certificate file (e.g. "server.crt")
// keyFileName: name of the key file (e.g. "server.key")
// warningBefore: duration before expiry to trigger a re-download
// Returns the local paths for the certificate and key.
func EnsureCertificates(bucket, region, s3SubDir, domain, dataDir, certFileName, keyFileName string, warningBefore time.Duration) (string, string, error) {
	localDir := filepath.Join(dataDir, "certs", domain)
	if err := os.MkdirAll(localDir, os.ModePerm); err != nil {
		return "", "", fmt.Errorf("failed to create local directory: %w", err)
	}
	certPath := filepath.Join(localDir, certFileName)
	keyPath := filepath.Join(localDir, keyFileName)

	expiring, err := CertExpiresSoon(certPath, warningBefore)
	if err != nil {
		return "", "", fmt.Errorf("error checking certificate: %w", err)
	}

	// If the certificate is missing/expiring, download both certificate and key using awsutil.
	if expiring || !FileExists(keyPath) {
		awsClient, err := awsutil.New(context.Background(), bucket, region)
		if err != nil {
			return "", "", fmt.Errorf("failed to initialize AWS client: %w", err)
		}

		remoteCertKey := fmt.Sprintf("%s/%s", s3SubDir, certFileName)
		remoteKeyKey := fmt.Sprintf("%s/%s", s3SubDir, keyFileName)

		certContent, err := awsClient.GetS3Object(context.Background(), remoteCertKey)
		if err != nil {
			return "", "", fmt.Errorf("failed to download certificate: %w", err)
		}

		keyContent, err := awsClient.GetS3Object(context.Background(), remoteKeyKey)
		if err != nil {
			return "", "", fmt.Errorf("failed to download key: %w", err)
		}

		if err := os.WriteFile(certPath, certContent, 0644); err != nil {
			return "", "", fmt.Errorf("failed to save certificate: %w", err)
		}
		if err := os.WriteFile(keyPath, keyContent, 0600); err != nil {
			return "", "", fmt.Errorf("failed to save key: %w", err)
		}
	}

	return certPath, keyPath, nil
}