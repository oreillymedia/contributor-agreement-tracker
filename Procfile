web: bundle exec thin -R config.ru start -p $PORT -e $RACK_ENV
worker: TERM_CHILD=1 env QUEUE=* bundle exec rake resque:work