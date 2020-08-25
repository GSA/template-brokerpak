FROM alpine:latest as pak-builder

# Get latest CA certs
RUN apk --update add ca-certificates

# Get the most recent released cloud-service-broker binary
RUN apk add curl
RUN (cd /bin \
  && curl -L -O https://github.com/pivotal/cloud-service-broker/releases/download/sb-0.1.0-rc.39-gcp-0.0.1-rc.78/cloud-service-broker \
  && chmod +x cloud-service-broker)

# Include the source
COPY . /service-broker-plugins/
# ENV PORT 8080
# EXPOSE 8080/tcp

# Set the working directory
WORKDIR /service-broker-plugins

# Build the brokerpaks
RUN ["/bin/cloud-service-broker", "pak", "build", "/service-broker-plugins"]

# Now create an image for the broker, preconfigured to present the brokerpaks we just built
FROM scratch
COPY --from=pak-builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=pak-builder /service-broker-plugins/*.brokerpak /usr/share/gcp-service-broker/builtin-brokerpaks/
COPY --from=pak-builder /bin/cloud-service-broker /bin/cloud-service-broker
WORKDIR /
ENTRYPOINT ["/bin/cloud-service-broker"]
CMD ["help"]