#!/bin/bash
until nc -z mysql 3306
do
  echo "Waiting for mysql to be available"
  sleep 15
done
python manage.py migrate 
python manage.py runserver 0.0.0.0:8000