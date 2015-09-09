#!/bin/bash -e

function logit() {
  TIMESTAMP=$(date -u +'%m/%d %H:%M:%S')
  MSG="=> ${TIMESTAMP} $1"
  echo ${MSG}
}

function log_fail() {
  echo "$@" 1>&2
  exit 1
}

function get_arch_info() {
  ARCH=`arch`
  echo "$ARCH"
}

function verify_paas_name() {
  if [[ -z $1 ]]; then
    echo "Please specify your paas name"
    exit 1
  fi
  if command -v $1; then
    echo "$1 conflicts with an existing command. Please specify other paas name"
    exit 1
  fi
}

function set_env() {
  logit "Setting environment ..."
  export PAAS_USER=$1
  export PAAS_HOME=/home/$PAAS_USER
  export DOCKER_IP=$(ifconfig eth0 | awk -F: '/inet addr:/ {print $2}' | awk '{ print $1 }')
}

function create_paas_user() {
  logit "Creating paas user ..."
  useradd -d $PAAS_HOME $PAAS_USER
  mkdir -p $PAAS_HOME/app
  chown -R $PAAS_USER:$PAAS_USER $PAAS_HOME/
}

function setup_docker_compose() {
  logit "Setting up docker compose ..."
  curl -L https://github.com/docker/compose/releases/download/1.4.0/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
}

function setup_consul() {
  logit "Setting up consul ..."
  case "$1" in
    x86_64)
      docker pull progrium/consul
      docker run -d -p 8400:8400 -p 8500:8500 -p 8600:53/udp --restart=always --name consul -h consul progrium/consul -server -advertise $DOCKER_IP -bootstrap -ui-dir /ui
      ;;
    armv7l)
      docker pull nimblestratus/rpi-consul
      docker run -d -p 8400:8400 -p 8500:8500 -p 8600:53/udp --restart=always --name consul -h consul nimblestratus/rpi-consul -server -advertise $DOCKER_IP -bootstrap -ui-dir /ui
      ;;
    *)
      log_fail "Unsupported platform: $ARCH"
      ;;
esac

}

function setup_registrator() {
  logit "Setting up registrator ..."
  case "$1" in
    x86_64)
      docker pull gliderlabs/registrator
      docker run -d -v /var/run/docker.sock:/tmp/docker.sock --restart=always --name registrator -h registrator gliderlabs/registrator consul://$DOCKER_IP:8500
      ;;
    armv7l)
      docker pull nimblestratus/rpi-registrator
      docker run -d -v /var/run/docker.sock:/tmp/docker.sock --restart=always --name registrator -h registrator nimblestratus/rpi-registrator consul://$DOCKER_IP:8500
      ;;
    *)
      log_fail "Unsupported platform: $ARCH"
      ;;
  esac
}

function setup_nginx() {
  logit "Setting up nginx loadbalancer ..."
  mkdir $PAAS_HOME/nginx
  cd $PAAS_HOME/nginx

  cat << "EOF" > ./start.sh
#!/bin/bash
rm -f /etc/nginx/conf.d/default.conf
service nginx start
consul-template -consul=$CONSUL_URL -template="/templates/service.ctmpl:/etc/nginx/conf.d/service.conf:service nginx reload"
EOF
  chmod +x ./start.sh

case "$1" in
  x86_64)
    PARENT="nginx"
    ARCH="amd64"
    ;;
  armv7l)
    PARENT="akkerman/rpi-nginx"
    ARCH="arm"
    ;;
  *)
    log_fail "Unsupported platform: $ARCH"
    ;;
esac

  cat << EOF > ./Dockerfile
FROM $PARENT
 
ENTRYPOINT ["/bin/start.sh"]
EXPOSE 80
VOLUME /templates
ENV CONSUL_URL consul:8500
 
ADD start.sh /bin/start.sh

ADD https://github.com/hashicorp/consul-template/releases/download/v0.10.0/consul-template_0.10.0_linux_${ARCH}.tar.gz /usr/bin/
RUN tar -C /usr/local/bin --strip-components 1 -zxf /usr/bin/consul-template_0.10.0_linux_${ARCH}.tar.gz
EOF

  cat << EOF > ./service.ctmpl
{{range services}}upstream {{.Name}} {
  {{range service .Name}}server $DOCKER_IP:{{.Port}};
  {{else}}server 127.0.0.1:65535; # force a 502{{end}}
}{{end}}

server {
  listen 80;
  {{range services}}location /{{.Name}} {
    proxy_pass http://{{.Name}}/;
  }{{end}}
}
EOF
  docker build -t $PAAS_USER/nginx-loadbalancer .
  docker run -p 80:80 -d --restart=always --name nginx --volume $PAAS_HOME/nginx/service.ctmpl:/templates/service.ctmpl --link consul:consul $PAAS_USER/nginx-loadbalancer
}

function setup_gitreceive() {
  su -c "ssh-keygen -f $HOME/.ssh/id_rsa -t rsa -q -N ''" $SUDO_USER
  su -c "ssh-keygen -f $PAAS_HOME/.ssh/id_rsa -t rsa -q -N ''" $PAAS_USER
  wget -O /tmp/gitreceive.original https://raw.github.com/progrium/gitreceive/master/gitreceive
  cat /tmp/gitreceive.original | sed -e "s/pre-receive/post-receive/g" > /tmp/gitreceive

  mv /tmp/gitreceive /usr/local/bin/
  chmod +x /usr/local/bin/gitreceive

  export GITUSER=$PAAS_USER
  gitreceive init
  gpasswd -a $PAAS_USER docker
  cat $HOME/.ssh/id_rsa.pub | gitreceive upload-key $SUDO_USER
  cat $PAAS_HOME/.ssh/id_rsa.pub | gitreceive upload-key $PAAS_USER

  cat << EOF > $PAAS_HOME/.ssh/config
Host localhost
StrictHostKeyChecking no
EOF

  cat << EOF2 > $PAAS_HOME/receiver
#!/bin/bash

#source /home/\$3/\$1/.paas_env

function get_dockerfile_exposed_port() {
  DOCKERFILE_PORT=\$(grep "^EXPOSE \+[[:digit:]]\+\(\/tcp\)\? *$" \$1 | head -1 | sed 's/EXPOSE \+\([[:digit:]]\+\)\(\/tcp\)\?.*/\1/' || true)
  echo "\$DOCKERFILE_PORT"
}

#cp -R /home/\$3/\$1/ $PAAS_HOME/app/
#cd $PAAS_HOME/app/\$1

unset GIT_DIR

if [ -e $PAAS_HOME/app/\$1/.git ]; then
  echo "git pull!!!"
  cd $PAAS_HOME/app/\$1
  git pull
else
  echo "git clone!!!"
  cd $PAAS_HOME/app/
  git clone localhost:\$1
  cd $PAAS_HOME/app/\$1
fi

PORT=\$(get_dockerfile_exposed_port Dockerfile)

cat << EOF > $PAAS_HOME/app/\$1/docker-compose.yml
web:
  image: $PAAS_USER/\$1
  ports:
    - \$PORT
EOF
  chmod +x $PAAS_HOME/app/\$1/docker-compose.yml

echo "-----> Building Docker image ..."
docker build -t $PAAS_USER/\$1 .

echo "-----> Removing existing Docker image ..."
docker-compose stop

echo "-----> Launching \$1 ..."
docker-compose up -d
EOF2

}

function install_client() {

  cat << EOF2 > /usr/local/bin/$PAAS_USER
#!/bin/bash

APP=\$(pwd | awk -F / '{print \$NF}')

case "\$1" in
  create)
    git remote add $PAAS_USER $PAAS_USER@localhost:\$APP
    echo "Git remote $PAAS_USER added"
    ;;
  scale)
    docker-compose -f $PAAS_HOME/app/\$APP/docker-compose.yml scale "\$2" #>/dev/null 2>&1
    ;;
  *)
    echo "Usage: $PAAS_USER <command>"
    ;;
esac

EOF2
  chmod +x /usr/local/bin/$PAAS_USER
}

# main

verify_paas_name $1
ARCH=`get_arch_info`
set_env $1
create_paas_user
if [ "$ARCH" = "x86_64" ]; then
  setup_docker_compose
fi
setup_consul $ARCH
setup_registrator $ARCH
setup_nginx $ARCH
setup_gitreceive
install_client