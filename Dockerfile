# -------------- base image --------------
FROM php:8.2-apache

# -------------- install dependencies --------------
RUN apt-get update && apt-get install -y \
      unzip git libpng-dev libjpeg-dev libfreetype6-dev libonig-dev \
      libxml2-dev zip mariadb-client libzip-dev libpq-dev \
    && docker-php-ext-install mysqli pdo pdo_mysql zip gd intl xml soap mbstring \
    && a2enmod rewrite

# -------------- download & extract Moodle --------------
WORKDIR /var/www/html
RUN curl -L -o moodle.zip \
      https://download.moodle.org/download.php/direct/stable500/moodle-latest-500.zip \
    && unzip moodle.zip \
    && mv moodle/* ./ \
    && rm -rf moodle moodle.zip

# -------------- prepare moodledata --------------
RUN mkdir -p /var/www/moodledata \
    && chown -R www-data:www-data /var/www/moodledata \
    && chmod -R 777 /var/www/moodledata

# -------------- PHP tuning --------------
RUN echo "max_input_vars = 5000\nupload_max_filesize = 64M\npost_max_size = 64M" > /usr/local/etc/php/conf.d/moodle.ini

# -------------- Apache → Railway port --------------
RUN echo "ServerName localhost" >> /etc/apache2/apache2.conf \
  && sed -i 's/:80/:8080/g' /etc/apache2/ports.conf /etc/apache2/sites-enabled/000-default.conf
  



# -------------- entrypoint script --------------
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]

# -------------- expose for Railway --------------
EXPOSE 8080
