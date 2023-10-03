FROM alpine:latest

RUN apk update && apk add bash httpie
COPY ./auth-token.sh /auth-token.sh

CMD /auth-token.sh
