FROM golang:alpine

ADD . /go/bin

RUN go build /go/bin/main.go

ENTRYPOINT /go/main

EXPOSE 8080