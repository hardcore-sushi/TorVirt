FROM alpine:latest
RUN apk update
RUN apk add tor
RUN adduser -D user
USER user
COPY torrc /etc/tor/torrc
COPY wait.sh /home/user/wait.sh
ENTRYPOINT ["/home/user/wait.sh", "tor"]
