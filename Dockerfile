FROM python:3-alpine

## install OpenJDK 8

# add a simple script that can auto-detect the appropriate JAVA_HOME value
# based on whether the JDK or only the JRE is installed
RUN { \
		echo '#!/bin/sh'; \
		echo 'set -xe'; \
		echo; \
		echo 'dirname "$(dirname "$(readlink -f "$(which javac || which java)")")"'; \
	} > /usr/local/bin/docker-java-home \
	&& chmod +x /usr/local/bin/docker-java-home

ENV JAVA_HOME /usr/lib/jvm/java-1.8-openjdk
ENV PATH $PATH:/usr/lib/jvm/java-1.8-openjdk/jre/bin:/usr/lib/jvm/java-1.8-openjdk/bin:/usr/bin:/usr/sbin

ENV JAVA_VERSION 8u191
ENV JAVA_ALPINE_VERSION 8.191.12-r0

RUN set -xe \
	&& apk add --no-cache --progress \
		openjdk8="$JAVA_ALPINE_VERSION" \
	&& [ "$JAVA_HOME" = "$(docker-java-home)" ]

## Add some usefull utilities
RUN set -xe \
    && echo "****** Install system utilities ******" \
    && apk update \
    && apk add --no-cache --progress \
        bash wget coreutils tini sudo curl git

## install ansible
ENV ANSIBLE_VERSION=2.7.6

RUN set -xe \
    && echo "****** Install system dependencies ******" \
    && apk add --no-cache --progress \
        openssl ca-certificates \
    && apk add --update --virtual build-dependencies \
        python-dev libffi-dev openssl-dev build-base \
    \
    && echo "****** Install ansible and python dependencies ******" \
    && pip install ansible==${ANSIBLE_VERSION} boto boto3 \
    \
    && echo "****** Remove unused system librabies ******" \
    && apk del build-dependencies \
    && rm -rf /var/cache/apk/*

RUN set -xe \
    && mkdir -p /etc/ansible \
    && echo -e "[local]\nlocalhost ansible_connection=local" > \
        /etc/ansible/hosts

## install docker

ENV DOCKER_CHANNEL stable
ENV DOCKER_VERSION 18.06.1-ce
ENV dockerArch     x86_64

RUN set -xe \
    && wget -O docker.tgz \
    "https://download.docker.com/linux/static/${DOCKER_CHANNEL}/${dockerArch}/docker-${DOCKER_VERSION}.tgz" \
    \
    && tar --extract --file docker.tgz --strip-components 1 --directory /usr/bin/ \
    && rm docker.tgz \
    && dockerd --version \
    && docker --version

## Add Jenkins user
ARG user=jenkins
ARG group=jenkins
ARG uid=1000
ARG gid=1000
ARG JENKINS_AGENT_HOME=/home/${user}

ENV JENKINS_AGENT_HOME ${JENKINS_AGENT_HOME}

RUN set -xe \
    && echo "****** Add jenkins user and group ******" \
    && addgroup -g ${gid} ${group} \
    && adduser -h "${JENKINS_AGENT_HOME}" -u "${uid}" -G "${group}" -s /bin/bash -D "${user}"\
    && passwd -u jenkins \
    && mkdir ${JENKINS_AGENT_HOME}/.ssh \
    && addgroup docker -g 993\
    && adduser jenkins docker

# setup SSH server
RUN set -xe \
    && echo "****** setup SSH server ******" \
    && apk add --no-cache --progress \
        openssh sshpass \
    && sed -i /etc/ssh/sshd_config \
        -e 's/#RSAAuthentication.*/RSAAuthentication yes/'  \
        -e 's/#PasswordAuthentication.*/PasswordAuthentication no/' \
        -e 's/#SyslogFacility.*/SyslogFacility AUTH/' \
        -e 's/#LogLevel.*/LogLevel INFO/' \
        -e 's/#StrictHostKeyChecking.*/StrictHostKeyChecking no/' \
    && mkdir /var/run/sshd
#        -e 's/#PermitRootLogin.*/PermitRootLogin no/' \
#
VOLUME "${JENKINS_AGENT_HOME}" "/tmp" "/run" "/var/run"
WORKDIR "${JENKINS_AGENT_HOME}"

COPY setup-ssh-keys /usr/local/bin/setup-ssh-keys
COPY "*.pub" "${JENKINS_AGENT_HOME}/.ssh/"

EXPOSE 22

ENTRYPOINT ["setup-ssh-keys"]
