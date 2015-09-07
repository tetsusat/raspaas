FROM ruby:2.2.2

RUN mkdir /app
WORKDIR /app

ADD ./Gemfile Gemfile
ADD ./Gemfile.lock Gemfile.lock
RUN bundle install

ADD . /app

EXPOSE 4567

CMD ["bundle", "exec", "ruby", "web.rb"]
