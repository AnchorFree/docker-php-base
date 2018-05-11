VAGRANT
=======

Backup solution for build images.

```
vagrant up
vagrant ssh
cd /vagrant/
sudo docker login
sudo docker build --pull --rm --file Dockerfile --tag anchorfree/php-elite .
```
