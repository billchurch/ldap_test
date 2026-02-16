FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    openssh-server \
    nslcd \
    libpam-ldapd \
    libnss-ldapd \
    ldap-utils \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd

# NSS: resolve users/groups/shadow via LDAP
RUN sed -i 's/^passwd:.*/passwd:         files ldap/' /etc/nsswitch.conf && \
    sed -i 's/^group:.*/group:          files ldap/' /etc/nsswitch.conf && \
    sed -i 's/^shadow:.*/shadow:         files ldap/' /etc/nsswitch.conf

# PAM: auto-create home directories on first login
RUN echo "session required pam_mkhomedir.so skel=/etc/skel umask=0022" >> /etc/pam.d/common-session

# PAM: disable pam_systemd.so — blocks for 25s in containers without systemd-logind
# (same issue as Debian; Ubuntu common-session lacks the leading dash that Rocky uses)
RUN sed -i 's/^.*pam_systemd.so/#&/' /etc/pam.d/common-session

# SSH: enable password authentication, disable root login
RUN sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

EXPOSE 22

COPY shared/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
