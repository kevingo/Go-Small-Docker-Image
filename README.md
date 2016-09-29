# 建立一個比較小的 golang Docker images

相信使用 Docker 的人一定會有一個困擾，就是常常我們在 build 完一個 image 後， image size 都大到不行，這不僅僅造成空間浪費，而且當你想要部署的時候，也會花費許多時間，因此大家可以看到很多人在想辦法減少 docker image 的 size。今天來分享一個最近看到的好方法。

### tl;dr

先講結論，這個方法就是寫兩個 Dockerfile，一個用來 `build`，另一個用來 `run`。如果你已經知道這個方法，就不用再看下去囉。還不知道的話，就讓我來分享一下。

### 一般作法
首先當然要有自己的程式碼，這裡用 golang 官方的 simple web server 當範例：

```go
package main

import (
    "fmt"
    "net/http"
)

func handler(w http.ResponseWriter, r *http.Request) {
    fmt.Fprintf(w, "Hi there, I love %s!", r.URL.Path[1:])
}

func main() {
    http.HandleFunc("/", handler)
    http.ListenAndServe(":8080", nil)
}
```
一般的情況我們可能會寫一個 Dockerfile，然後把 Build 和 Run 都寫進去，類似這樣(這裡用 onbuild 的 image 來簡化流程)：

```Dockerfile
FROM golang:onbuild

EXPOSE 8080
```

然後執行 port binding：

```
$docker run --publish 1234:8080 http.old
```

這樣沒什麼問題，只是當我們想要部署的時候，image size 很大：

![image](https://github.com/kevingo/blog/raw/master/screenshot/docker-image-old.png)

### 使用 alpine

你可能會想，不是有一個叫做 alpine 的 Linux 作業系統號稱只有 5MB，又小又快又方便。剛好 golagn 也有支援 alpine 的 image：[golang:alpine](https://github.com/docker-library/golang/blob/3a3e91c242b58a7d4e6022b3710b2e871f0ee5d6/1.7/alpine/Dockerfile)。

我們用 golang 官方的 alpine image 來 build 一個我們的應用，你的 Dockerfile 可以這樣寫：

```
FROM golang:alpine

ADD . /go/bin

RUN go build /go/bin/main.go

ENTRYPOINT /go/main

EXPOSE 8080
```

然後 build：

```
$ docker build -t http.alpine -f Dockerfile.alpine .
```

接著用 `docker image` 來看一下 build 出來的 image size：

![image](https://github.com/kevingo/blog/raw/master/screenshot/golang-alpine-image.png)

變成 246.2 MB 了，是小了大概三分之一左右，但還是蠻大的。所以用 alpine 還是無法解決 image 過大的問題。接下來，讓我們看看把 Dockerfile 拆成 build 和 run 是怎麼一回事。

### 用來 Build 的 Dockerfile

這裡我們可以將原本的 Dockerfile 拆成兩份，一份叫做 `Dockerfile.builder`，一份叫做 `Dockerfile.runner`。

`Dockerfile.builder` 專門用來 build image，這裡共分為四個步驟：

```
FROM golang:onbuild

COPY Dockerfile.runner /go/bin/Dockerfile

WORKDIR /go/bin

CMD tar -cf - .
```

1. `FROM golang:onbuild`：沒問題，用 onbuild 的 image 當成 base
2. `COPY Dockerfile.runner /go/bin/Dockerfile`：這裡我們需要將 `Dockerfile.runner` 複製到 build 的 image 裡面的 `/go/bin/Dockerfile` 這個檔案
3. `WORKDIR /go/bin`：指定工作目錄給下一個步驟使用
4. `CMD tar -cf - .`：這個步驟是利用 tar 指令來產生一個 output steam，這個 stream 裡面會包含 `/go/bin` 這個資料夾下的所有檔案，也就是會有 `app` 和 `Dockerfile` 這兩個檔案。`app` 是我們透過 `onbuild` 的 image 做出來的可執行檔，`Dockerfile` 就是我們複製進去的 `Dockerfile.runner`。這個 output stream 將會提供給等等的 runner 來使用。

### 用來 Run 的 Dockerfile

上面提到的 Dockerfile.runner 檔案就類似這樣：

```
FROM flynn/busybox

COPY app /bin/app

EXPOSE 8001

CMD ["/bin/app"]
```

1. `FROM flynn/busybox`：用一個很小的作業系統就可以用來當成執行上面 build 出來的環境了，這裡我們選 `busybox`。
2. `COPY app /bin/app`：這裡我們把 `app` 這個執行檔複製到 runner container 裡面的 `/bin/app` 下。
3. `EXPOSE 8001`：挑選一個 expose 的 port
4. `CMD ["/bin/app"]`：執行 `app` 這個執行檔

### 整合

現在我們有兩個 Dockerfile，分別是 `Dockerfile.builder` 和 `Dockerfile.runner`，你只要透過一行指令就可以把要執行的 runner image 建立好：

```
$ docker build -t builder -f Dockerfile.builder . && docker run builder | docker build -t runner -
```

上面這一行指令（其實是包含兩個指令）會建立 builder 和 runnner 兩個 images。

1. `docker build -t builder -f Dockerfile.builder .` 會把 build 的 image 建立好。
2. `docker run builder | docker build -t runner -` 這一行指令使用個 pipe 的功能，我們首先把 builder image 給跑起來，由於我們在 builder 的最後一行是用 `tar` 這個指令把執行檔和 runner 要用的 Dockerfile 用 stream 的方式做一個 stdout，就可以 pipe 給後面的 `docker build -t runner -` 這個指令使用了。

你可以執行 `docker images` 來看看：

![image](https://github.com/kevingo/blog/raw/master/screenshot/builder-runner-image.png)

你會看到 runner image 比起 builder image 小很多，而我們只需要執行 runner image 就可以啟動我們的服務了：

```
$ docker run -p 1234:8080 -t http runner
```

### References
- [dockerception](https://github.com/jamiemccrindle/dockerception)
- [Deploy go server with Docker](https://blog.golang.org/docker)