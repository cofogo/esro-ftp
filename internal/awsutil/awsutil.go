package awsutil

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	s3types "github.com/aws/aws-sdk-go-v2/service/s3/types"
	smtypes "github.com/aws/aws-sdk-go-v2/service/secretsmanager/types"
)

// AWSUtil holds the AWS service clients.
type AWSUtil struct {
	S3Client *s3.Client
	Bucket   string // Store the bucket name for convenience
}

// New initializes AWS configuration and returns an AWSUtil instance.
func New(ctx context.Context, bucketName, region string) (*AWSUtil, error) {
	cfg, err := config.LoadDefaultConfig(ctx)
	cfg.Region = region

	if err != nil {
		return nil, fmt.Errorf("failed to load AWS configuration: %w", err)
	}

	return &AWSUtil{
		S3Client: s3.NewFromConfig(cfg),
		Bucket:   bucketName,
	}, nil
}

// GetS3Object retrieves an object from the configured S3 bucket.
func (a *AWSUtil) GetS3Object(ctx context.Context, key string) ([]byte, error) {
	output, err := a.S3Client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(a.Bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to get object s3://%s/%s: %w", a.Bucket, key, err)
	}
	defer output.Body.Close()

	buf := new(bytes.Buffer)
	_, err = buf.ReadFrom(output.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read object body s3://%s/%s: %w", a.Bucket, key, err)
	}
	return buf.Bytes(), nil
}

// UploadToS3 uploads content to the configured S3 bucket.
func (a *AWSUtil) UploadToS3(ctx context.Context, content []byte, key string) error {
	_, err := a.S3Client.PutObject(ctx, &s3.PutObjectInput{
		Bucket: aws.String(a.Bucket),
		Key:    aws.String(key),
		Body:   bytes.NewReader(content),
	})
	if err != nil {
		return fmt.Errorf("failed to put object s3://%s/%s: %w", a.Bucket, key, err)
	}
	return nil
}

// CopyS3Object copies an object from one S3 location to another.
func (a *AWSUtil) CopyS3Object(ctx context.Context, sourceBucket, sourceKey, destBucket, destKey string) error {
	copySource := fmt.Sprintf("%s/%s", sourceBucket, sourceKey)

	_, err := a.S3Client.CopyObject(ctx, &s3.CopyObjectInput{
		Bucket:     aws.String(destBucket),
		Key:        aws.String(destKey),
		CopySource: aws.String(copySource),
	})
	if err != nil {
		return fmt.Errorf("failed to copy object from s3://%s/%s to s3://%s/%s: %w",
			sourceBucket, sourceKey, destBucket, destKey, err)
	}
	return nil
}

// IsS3NotFoundErr checks if the error is an S3 'NotFound' type error.
func IsS3NotFoundErr(err error) bool {
	var nsk *s3types.NoSuchKey
	var nfb *s3types.NoSuchBucket
	var nf *s3types.NotFound // More generic
	if errors.As(err, &nsk) || errors.As(err, &nfb) || errors.As(err, &nf) {
		return true
	}
	// Fallback string check just in case
	// Note: Error codes might be more reliable if available, e.g., awsErr.Code() == "NoSuchKey"
	if err != nil && (strings.Contains(err.Error(), "NotFound") || strings.Contains(err.Error(), "NoSuchKey")) {
		return true
	}
	return false
}

// IsSecretsManagerNotFoundErr checks if the error is a Secrets Manager 'ResourceNotFoundException'.
func IsSecretsManagerNotFoundErr(err error) bool {
	var rnfe *smtypes.ResourceNotFoundException
	if errors.As(err, &rnfe) {
		return true
	}
	// Fallback string check
	if err != nil && strings.Contains(err.Error(), "ResourceNotFoundException") {
		return true
	}
	return false
}
