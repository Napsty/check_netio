.PHONY: build test test-basic test-error test-tcp test-legacy test-invalid

IMAGE_NAME = check-netio

build:
	docker build -t $(IMAGE_NAME) .

test-basic: build
	docker run --network host $(IMAGE_NAME)

test-error: build
	docker run --network host $(IMAGE_NAME) ./check_netio.sh -i eth0 -e

test-tcp: build
	docker run --network host $(IMAGE_NAME) ./check_netio.sh -i eth0 -t

test-legacy: build
	docker run --network host $(IMAGE_NAME) ./check_netio.sh -i eth0 -l

test-invalid: build
	docker run --network host $(IMAGE_NAME) ./check_netio.sh -i eth999 || test $$? -eq 3

test: test-basic test-error test-tcp test-legacy test-invalid
