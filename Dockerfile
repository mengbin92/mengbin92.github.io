FROM docker.io/mengbin92/gobin:v1.2.0

WORKDIR /site
COPY . /site

CMD ["gobin", "build", "--minify"]
