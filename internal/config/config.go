package config

import (
	"log"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/joho/godotenv"
	"github.com/spf13/viper"
)

// Config struct now includes mapstructure tags.
type Config struct {
	DataDir     string `mapstructure:"data_dir"`
	DatabaseURL string `mapstructure:"database_url"`

	API struct {
		URL      string `mapstructure:"url"`
		Domain   string `mapstructure:"domain"`
		Port     int    `mapstructure:"port"`
		GRPC_URL string `mapstructure:"grpc_url"`
	} `mapstructure:"api"`

	ESRO struct {
		BaseURL string `mapstructure:"base_url"`
	} `mapstructure:"esro"`

	// Simplified AWS configuration
	AWS struct {
		Region      string `mapstructure:"region"`
		CertsBucket string `mapstructure:"certs_bucket"`
		DataBucket  string `mapstructure:"data_bucket"`
		MTLSSubdir  string `mapstructure:"mtls_subdir"`
		SSLSubdir   string `mapstructure:"ssl_subdir"`
		DataSubdir  string `mapstructure:"data_subdir"`
	} `mapstructure:"aws"`

	Mock struct {
		ImageSizeMB int    `mapstructure:"image_size_mb"`
		ImageType   string `mapstructure:"image_type"`
	} `mapstructure:"mock"`
}

func Load(configPath string) *Config {
	_ = godotenv.Load() // Load from .env if present

	viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
	viper.AutomaticEnv() // Enable env var overrides

	// Use specified config file if provided
	if configPath != "" {
		viper.SetConfigFile(configPath)
	} else {
		viper.SetConfigFile("./config.toml")
	}

	_ = viper.ReadInConfig() // Ignore errors if no file

	// --- Set fallback defaults ---
	viper.SetDefault("api.url", "https://esro.wecodeforgood.com:8443/api")
	viper.SetDefault("api.domain", "local.wecodeforgood.com")
	viper.SetDefault("api.port", 443)
	viper.SetDefault("api.grpc_url", "localhost:50051")

	viper.SetDefault("esro.base_url", "https://esro.wecodeforgood.com")

	// Simplified AWS defaults
	viper.SetDefault("aws.region", "eu-central-1")
	viper.SetDefault("aws.certs_bucket", "")
	viper.SetDefault("aws.data_bucket", "")
	viper.SetDefault("aws.mtls_subdir", "")
	viper.SetDefault("aws.ssl_subdir", "")
	viper.SetDefault("aws.data_subdir", "")

	viper.SetDefault("mock.image_size_mb", 50) // Default to ~50MB images
	viper.SetDefault("mock.image_type", "gradient")

	dataDir, err := getAppDataDir()
	if err != nil {
		log.Fatalf("getting app data dir: %v", err)
	}
	viper.SetDefault("data_dir", dataDir)

	dbPath := filepath.Join(dataDir, "data.db?_foreign_keys=on&_journal_mode=WAL")
	viper.SetDefault("database_url", dbPath)

	// --- Unmarshal config into struct ---
	// All the manual viper.Get* calls are replaced by this single block.
	var cfg Config
	if err := viper.Unmarshal(&cfg); err != nil {
		log.Fatalf("unable to decode config into struct, %v", err)
	}

	return &cfg
}

// Helper functions (getAppDataDir, isRunningInDocker, etc.) remain unchanged.
func getAppDataDir() (string, error) {
	if isRunningInDocker() {
		cwd, err := os.Getwd()
		if err != nil {
			return "", err
		}
		dir := filepath.Join(cwd, "data")
		os.MkdirAll(dir, os.ModePerm)
		return dir, nil
	}
	return getDefaultAppDataDir()
}

func isRunningInDocker() bool {
	_, err := os.Stat("/.dockerenv")
	return err == nil
}

func getDefaultAppDataDir() (string, error) {
	appName := "cofogo"
	var base string
	switch runtime.GOOS {
	case "windows":
		base = os.Getenv("LOCALAPPDATA")
		if base == "" {
			base = os.Getenv("APPDATA")
		}
	case "darwin":
		home, _ := os.UserHomeDir()
		base = filepath.Join(home, "Library", "Application Support")
	default: // "linux" and other Unix-like
		base = os.Getenv("XDG_DATA_HOME")
		if base == "" {
			home, _ := os.UserHomeDir()
			base = filepath.Join(home, ".local", "share")
		}
	}
	if base == "" {
		return "", os.ErrInvalid
	}
	path := filepath.Join(base, appName)
	os.MkdirAll(path, os.ModePerm)
	return path, nil
}
