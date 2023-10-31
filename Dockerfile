# Dockerfile
FROM alpine:3.18
LABEL maintainer="mengbin1992@outlook.com"

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories

# build develop env
RUN apk update && apk add build-base linux-headers ruby ruby-dev

# update gem and install jekyll
RUN gem update --system 3.4.21 && gem install jekyll bundler jekyll-paginate jekyll-sitemap kramdown-math-katex

WORKDIR /srv/jekyll

EXPOSE 4000

# ENTRYPOINT [ "jekyll serve -H 0.0.0.0" ]