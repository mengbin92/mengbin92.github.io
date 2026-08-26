FROM docker.io/mengbin92/gobin:v1.8.4

WORKDIR /site
COPY . /site

CMD ["gobin", "build", "--minify"]
