FROM ruby:3.3.10-slim

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential curl libyaml-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

RUN chmod +x bin/docker-entrypoint

ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["rails", "server", "-b", "0.0.0.0"]
