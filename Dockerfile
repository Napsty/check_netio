FROM ubuntu:22.04

# Install required packages
RUN apt-get update && \
    apt-get install -y \
    net-tools \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*

# Copy the script
COPY check_netio.sh /usr/local/bin/check_netio.sh

# Make it executable
RUN chmod +x /usr/local/bin/check_netio.sh

# Set working directory
WORKDIR /usr/local/bin

# Default command that runs basic test
CMD ["./check_netio.sh", "-i", "eth0"]
