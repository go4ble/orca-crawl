# https://hub.docker.com/r/yangxuan8282/rpi-alpine-phantomjs/

FROM ruby:2.5.3-alpine

RUN apk update &&\
    apk add --no-cache build-base fontconfig curl &&\
    mkdir -p /usr/share &&\
    cd /usr/share &&\
    curl -L https://github.com/yangxuan8282/docker-image/releases/download/2.1.1/phantomjs-2.1.1-alpine-arm.tar.xz | tar xJ &&\
    ln -s /usr/share/phantomjs/phantomjs /usr/bin/phantomjs

WORKDIR /usr/src/app

COPY Gemfile Gemfile.lock ./
RUN bundle install &&\
    apk del build-base curl

COPY . .

ENV USERNAME PASSWORD STATION

CMD bundle exec ruby crawl.rb
