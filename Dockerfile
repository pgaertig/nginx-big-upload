FROM debian:stretch-slim

# Build nginx
ADD ./docker/build_nginx.sh /tmp
RUN DOCKER=1 /tmp/build_nginx.sh && \
    apt-get install dumb-init zlib1g-dev libssl1.0-dev && \
    rm -rf /usr/src /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/doc /usr/share/doc-base /usr/share/man /usr/share/locale /usr/share/zoneinfo /usr/src

# Add upload code
ADD . /opt/nginx-big-upload/
CMD ["/opt/nginx-big-upload/docker/entrypoint.sh"]
