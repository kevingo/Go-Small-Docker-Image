FROM golang:onbuild

COPY Dockerfile.runner /go/bin/Dockerfile

WORKDIR /go/bin

CMD tar -cf - .