FROM debian:stretch-slim

# Build nginx
ADD ./docker/build_nginx.sh /tmp
RUN DOCKER=1 /tmp/build_nginx.sh && \
    apt-get install dumb-init zlib1g-dev libssl1.0-dev && \
    rm -rf /usr/src /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/doc /usr/share/doc-base /usr/share/man /usr/share/locale /usr/share/zoneinfo /usr/src && \
    groupadd -g 1000 -o nginx && \
    useradd --shell /usr/sbin/nologin -u 1000 -o -c "" -g 1000 -G www-data nginx

# Add upload code
ADD . /opt/nginx-big-upload/
CMD ["/opt/nginx-big-upload/docker/entrypoint.sh"]
