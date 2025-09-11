# Build argument to determine build type
ARG BUILD_TYPE=production

# Build stage
FROM golang:1.23-alpine AS builder

WORKDIR /app
COPY . .

# Build the application
RUN go mod tidy && go build -o bootstrap main.go

# Runtime stage  
FROM public.ecr.aws/lambda/provided:al2

# Copy the built binary to the runtime directory
COPY --from=builder /app/bootstrap /var/runtime/bootstrap

# Create output directory for debug mode
RUN mkdir -p /tmp/lambda/output/manifests

# Set environment variables for debug mode if needed
RUN if [ "$BUILD_TYPE" = "debug" ]; then \
    echo "export DEBUG=true" >> /etc/profile && \
    echo "DEBUG=true" > /tmp/debug.env; \
    fi

# Command is the Lambda handler
CMD [ "bootstrap" ]
