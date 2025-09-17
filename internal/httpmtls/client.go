package httpmtls

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/cofogo/esro-ftp-trigger/internal/server"
)

type Client struct {
	httpClient *http.Client
	BaseURL    string
	logger     *log.Logger
}

func NewClient(bucket, region, s3SubDir, baseURL string) (*Client, error) {
	return NewClientWithTimeout(bucket, region, s3SubDir, baseURL, 120*time.Second)
}

func NewClientWithTimeout(bucket, region, s3SubDir, baseURL string, timeout time.Duration) (*Client, error) {
	logger := log.New(os.Stdout, "[HTTP (mTLS)] ", log.LstdFlags|log.Lshortfile)
	logger.Printf("Loading certificates from S3 bucket=%s prefix=%s", bucket, s3SubDir)

	// Load certificate directly from S3 without writing to filesystem
	cert, err := server.LoadCertificatesFromS3(bucket, region, s3SubDir, "client.crt", "client.key")
	if err != nil {
		logger.Printf("ERROR LoadCertificatesFromS3: %v", err)
		return nil, fmt.Errorf("loading certificates from S3: %w", err)
	}
	logger.Printf("Successfully loaded certificate from S3")

	tlsConfig := &tls.Config{
		Certificates: []tls.Certificate{cert},
		MinVersion:   tls.VersionTLS12,
	}

	httpClient := &http.Client{
		Transport: &http.Transport{TLSClientConfig: tlsConfig},
		Timeout:   timeout,
	}

	logger.Printf("Client ready for BaseURL=%s with timeout=%v", baseURL, timeout)
	return &Client{httpClient, baseURL, logger}, nil
}

func (c *Client) Get(ctx context.Context, path string) ([]byte, error) {
	url := c.BaseURL + path
	c.logger.Printf("GET %s", url)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		c.logger.Printf("ERROR NewRequest GET: %v", err)
		return nil, fmt.Errorf("creating GET request: %w", err)
	}
	resp, err := c.httpClient.Do(req)
	if err != nil {
		c.logger.Printf("ERROR Do GET: %v", err)
		return nil, fmt.Errorf("executing GET request: %w", err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		c.logger.Printf("ERROR GET status %d: %s", resp.StatusCode, body)
		return nil, fmt.Errorf("unexpected status code %d: %s", resp.StatusCode, body)
	}
	data, err := readBody(resp)
	if err != nil {
		c.logger.Printf("ERROR ReadBody GET: %v", err)
		return nil, err
	}
	c.logger.Printf("GET succeeded, %d bytes", len(data))
	return data, nil
}

func (c *Client) Post(ctx context.Context, path string, payload any) ([]byte, error) {
	url := c.BaseURL + path
	c.logger.Printf("POST %s", url)
	reader, err := jsonReader(payload)
	if err != nil {
		c.logger.Printf("ERROR JSONReader: %v", err)
		return nil, fmt.Errorf("marshaling payload: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, reader)
	if err != nil {
		c.logger.Printf("ERROR NewRequest POST: %v", err)
		return nil, fmt.Errorf("creating POST request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.httpClient.Do(req)
	if err != nil {
		c.logger.Printf("ERROR Do POST: %v", err)
		return nil, fmt.Errorf("executing POST request: %w", err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		c.logger.Printf("ERROR POST status %d: %s", resp.StatusCode, body)
		return nil, fmt.Errorf("unexpected status code %d: %s", resp.StatusCode, body)
	}
	data, err := readBody(resp)
	if err != nil {
		c.logger.Printf("ERROR ReadBody POST: %v", err)
		return nil, err
	}
	c.logger.Printf("POST succeeded, %d bytes", len(data))
	return data, nil
}

func (c *Client) Put(ctx context.Context, path string, payload any) ([]byte, error) {
	url := c.BaseURL + path
	c.logger.Printf("PUT %s", url)
	reader, err := jsonReader(payload)
	if err != nil {
		c.logger.Printf("ERROR JSONReader: %v", err)
		return nil, fmt.Errorf("marshaling payload: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPut, url, reader)
	if err != nil {
		c.logger.Printf("ERROR NewRequest PUT: %v", err)
		return nil, fmt.Errorf("creating PUT request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.httpClient.Do(req)
	if err != nil {
		c.logger.Printf("ERROR Do PUT: %v", err)
		return nil, fmt.Errorf("executing PUT request: %w", err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		c.logger.Printf("ERROR PUT status %d: %s", resp.StatusCode, body)
		return nil, fmt.Errorf("unexpected status code %d: %s", resp.StatusCode, body)
	}
	data, err := readBody(resp)
	if err != nil {
		c.logger.Printf("ERROR ReadBody PUT: %v", err)
		return nil, err
	}
	c.logger.Printf("PUT succeeded, %d bytes", len(data))
	return data, nil
}

// JSONReader marshals v to JSON and returns an io.Reader.
func jsonReader(v any) (io.Reader, error) {
	if v == nil {
		return nil, nil
	}
	b, err := json.Marshal(v)
	if err != nil {
		return nil, err
	}
	return bytes.NewBuffer(b), nil
}

// ReadBody reads and returns resp.Body, then closes it.
func readBody(resp *http.Response) ([]byte, error) {
	defer resp.Body.Close()
	return io.ReadAll(resp.Body)
}
