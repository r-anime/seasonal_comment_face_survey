FROM ruby:4.0.1-alpine AS builder

ENV APP_HOME=/app
WORKDIR $APP_HOME

RUN apk add --no-cache \
      build-base \
      sqlite-dev \
      tzdata

RUN gem update --system

COPY Gemfile Gemfile.lock ./

RUN bundle config set without 'development test' && bundle install

FROM ruby:4.0.1-alpine AS runtime

ENV APP_HOME=/app
WORKDIR $APP_HOME

RUN apk add --no-cache \
      sqlite \
      bash

# copy over deps
COPY --from=builder /usr/local/bundle/ /usr/local/bundle/

COPY . .

ARG GIT_COMMIT_HASH
ENV GIT_COMMIT_HASH=$GIT_COMMIT_HASH
ARG GIT_REPO_URL
ENV GIT_REPO_URL=$GIT_REPO_URL

EXPOSE 4567

CMD ["bundle", "exec", "ruby", "app.rb"]
