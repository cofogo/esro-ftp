package config

import (
	"os"
	"strconv"
)

// Config struct with hardcoded values for simplicity
type Config struct {
	API struct {
		URL        string
		Domain     string
		Port       int
		GRPC_URL   string
		TimeoutSec int
	}

	AWS struct {
		Region      string
		CertsBucket string
		DataBucket  string
		MTLSSubdir  string
		SSLSubdir   string
		DataSubdir  string
	}

	Mock struct {
		ImageSizeMB int
		ImageType   string
	}
}

func Load(configPath string) *Config {

	cfg := &Config{}

	cfg.API.URL = "https://esro.wecodeforgood.com:8443/api"
	cfg.API.Domain = "local.wecodeforgood.com"
	cfg.API.Port = 443
	cfg.API.GRPC_URL = "localhost:50051"

	// Set timeout from environment or default to 5 minutes
	cfg.API.TimeoutSec = 300 // 5 minutes default
	if timeoutStr := os.Getenv("API_TIMEOUT_SEC"); timeoutStr != "" {
		if timeout, err := strconv.Atoi(timeoutStr); err == nil && timeout > 0 {
			cfg.API.TimeoutSec = timeout
		}
	}

	cfg.AWS.Region = "eu-central-1"
	cfg.AWS.CertsBucket = "esro-certificates"
	cfg.AWS.DataBucket = "esro-management-data"
	cfg.AWS.MTLSSubdir = "endpoints/mtls/esro"
	cfg.AWS.SSLSubdir = "endpoints/local.wecodeforgood.com"
	cfg.AWS.DataSubdir = "uploads"

	return cfg
}
