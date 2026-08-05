FROM nvidia/cuda:12.8.2-base-ubuntu24.04

ARG ROOT_PASSWORD=theRootPw2021

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    openssh-client \
    sudo \
    passwd \
    vim \
    ca-certificates \
    bash-completion \
    && rm -rf /var/lib/apt/lists/*

# 设置 root 密码，启用 su
RUN echo "root:${ROOT_PASSWORD}" | chpasswd

# sshd runtime directory
RUN mkdir -p /run/sshd

# ssh 配置
RUN sed -i \
    -e 's/^#PermitRootLogin.*/PermitRootLogin yes/' \
    -e 's/^PermitRootLogin.*/PermitRootLogin yes/' \
    -e 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' \
    -e 's/^PasswordAuthentication.*/PasswordAuthentication yes/' \
    /etc/ssh/sshd_config

# 防止 PAM 登录时因为 Ubuntu 默认策略失败
RUN mkdir -p /root/.ssh && chmod 700 /root/.ssh

EXPOSE 22
EXPOSE 61000

CMD ["/usr/sbin/sshd", "-D"]

