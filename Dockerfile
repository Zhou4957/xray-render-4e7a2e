FROM alpine:3.21
RUN apk add --no-cache ca-certificates curl unzip && curl -fsSL --retry 3 -o /tmp/x.zip https://github.com/XTLS/Xray-core/releases/download/v26.3.27/Xray-linux-64.zip && echo "23cd9af937744d97776ee35ecad4972cf4b2109d1e0fe6be9930467608f7c8ae  /tmp/x.zip" | sha256sum -c - && unzip -q /tmp/x.zip xray -d /usr/local/bin && rm -f /tmp/x.zip && apk del curl unzip
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
CMD ["/entrypoint.sh"]
