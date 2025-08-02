FROM ruby:3.4.5-alpine

ENV APP_HOME=/app

RUN apk add --no-cache \
      build-base \
      sqlite-dev \
      libffi-dev \
      tzdata \
      git \
      bash

WORKDIR $APP_HOME

COPY Gemfile Gemfile.lock ./

RUN bundle install

COPY . .

EXPOSE 4567

CMD ["ruby", "app.rb"]
