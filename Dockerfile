FROM python:3.7-buster AS dev-ops-app
WORKDIR /usr/src/app

COPY ./dev-ops-app/ .
RUN pip install --no-cache-dir -r requirements.txt
ENV DJANGO_SETTINGS_MODULE=settings
COPY entrypoint.sh /

CMD [ "/entrypoint.sh" ]
