web: bundle exec thin -R config.ru start -p $PORT -e $RACK_ENV
worker: env QUEUE=* bundle exec rake resque:work