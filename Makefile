.PHONY: generate build debug test-event clean tf-init tf-plan tf-apply tf-destroy

generate:
	go run -mod=mod github.com/sqlc-dev/sqlc/cmd/sqlc generate

build:
	docker build -t manifest-generator .

debug:
	DEBUG=true DB_CONNECTION_STRING="postgres://user:secret@localhost:5432/dashboard-main?sslmode=disable" go run main.go

test-event:
	@echo "Creating test event JSON..."
	@echo '{}' > test-event.json
	@echo "Building debug Docker image..."
	docker build --build-arg BUILD_TYPE=debug -t manifest-generator:debug .
	@echo "Running test event in Docker container..."
	docker run --rm -d \
		--name manifest-test \
		-p 9000:8080 \
		-e DEBUG=true \
		-e DB_CONNECTION_STRING="postgres://host.docker.internal:5432/dashboard-main?user=user&password=secret&sslmode=disable" \
		-v $(PWD)/output:/tmp/lambda/output \
		manifest-generator:debug
	@echo "Waiting for container to start..."
	@sleep 3
	@echo "Sending test event to Lambda function..."
	curl -XPOST "http://localhost:9000/2015-03-31/functions/function/invocations" -d @test-event.json -w "\nHTTP Status: %{http_code}\n" || true
	@echo "\nChecking container logs..."
	docker logs manifest-test
	@echo "\nStopping container..."
	docker stop manifest-test

test-debug:
	@echo "Creating test event JSON..."
	@echo '{}' > test-event.json  
	@echo "Building debug Docker image..."
	docker build --build-arg BUILD_TYPE=debug -t manifest-generator:debug .
	@echo "Running container interactively for debugging..."
	docker run --rm -it \
		-e DEBUG=true \
		-e DB_CONNECTION_STRING="postgres://host.docker.internal:5432/dashboard-main?user=user&password=secret&sslmode=disable" \
		-v $(PWD)/output:/tmp/lambda/output \
		--entrypoint /bin/sh \
		manifest-generator:debug

docker-build:
	docker build -t manifest-generator .

docker-build-debug:
	docker build --build-arg BUILD_TYPE=debug -t manifest-generator:debug .

clean:
	rm -f bootstrap test-event.json
	rm -rf output/
	docker rmi -f manifest-generator manifest-generator:debug 2>/dev/null || true
