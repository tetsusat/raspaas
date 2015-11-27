# Raspaas

Raspaas is yet another Heroku inspired docker PaaS.</br>
It can run not only on `x86_64` but also on `ARMv7` (i.e. Raspberry Pi 2 and Scaleway).

## Requirements

Raspaas is tested *insufficiently* on the following environments.

- Ubuntu 14.04 (x86_64)
- [Hypriot Docker Image for Raspberry Pi(Version 0.6.1)](http://blog.hypriot.com/downloads/)
- [Scaleway](https://www.scaleway.com/)

## Deployment options

Raspaas supports two different ways of deploying applications:

1. Dockerfile
2. [Buildpack-like](https://github.com/tetsusat/buildpack-like)

\* On ARMv7 platform, Buildpack-like deployment is not supported at this moment.

## Installing

To install Raspaas, you can run the following commands as a user that has access to `sudo`.
You can select your own paas name that you want (e.g. teroku) as far as it doesn't conflict with existing Linux commands and Linux users.

```sh
$ wget http://raw.github.com/tetsusat/raspaas/master/bootstrap.sh
$ chmod +x bootstrap.sh
$ sudo ./bootstrap.sh <your_paas_name>      # e.g.) sudo ./bootstrap.sh teroku
```

## Getting Started

Clone the git repo.

```sh
$ git clone https://github.com/tetsusat/ruby-sample.git
```

For Dockerfile deployment, clone the git repo below instead.

```sh
$ git clone https://github.com/tetsusat/ruby-sample-dockerfile.git ruby-sample
```

Inside the cloned repo, create your paas application.

```sh
$ cd ruby-sample
$ <your_paas_name> create                   # e.g.) teroku create
```

Push to the <your_paas_name> Git remote to deploy the application.

```sh
$ git push <your_paas_name> master
```

Your app should now be running on `http://<raspaas_host>/<app_name>/` (in this example, `http://<raspaas_host>/ruby-sample/`).

Run more web processes using the scale command.

```sh
$ <your_paas_name> scale web=3              # e.g.) teroku scale web=3
```

## License

MIT
