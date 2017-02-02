FROM mongo:3.2
RUN apt-get update && apt-get -y install dnsutils
ENTRYPOINT ["/docker-entrypoint.sh"]
COPY resources/* /
