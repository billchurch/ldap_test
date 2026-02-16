FROM rockylinux:9

# nss-pam-ldapd is in EPEL, not base repos
RUN dnf install -y epel-release && \
    dnf install -y \
    openssh-server \
    nss-pam-ldapd \
    openldap-clients \
    && dnf clean all

# Generate SSH host keys (Debian/Ubuntu do this at package install time)
RUN ssh-keygen -A

# NSS: resolve users/groups/shadow via LDAP
RUN sed -i 's/^passwd:.*/passwd:     files ldap/' /etc/nsswitch.conf && \
    sed -i 's/^group:.*/group:      files ldap/' /etc/nsswitch.conf && \
    sed -i 's/^shadow:.*/shadow:     files ldap/' /etc/nsswitch.conf

# PAM: enable LDAP authentication
# Rocky 9 minimal image uses authselect "minimal" profile — no pam_sss.so entries.
# We add pam_ldap.so (provided by nss-pam-ldapd) to the auth, account, and session
# stacks in both password-auth and system-auth.
RUN sed -i '/^auth.*sufficient.*pam_unix.so/a auth        sufficient    pam_ldap.so use_first_pass' \
        /etc/pam.d/password-auth /etc/pam.d/system-auth && \
    sed -i '/^account.*required.*pam_unix.so/a account     sufficient    pam_ldap.so' \
        /etc/pam.d/password-auth /etc/pam.d/system-auth && \
    sed -i '/^session.*required.*pam_unix.so/a session     optional      pam_ldap.so' \
        /etc/pam.d/password-auth /etc/pam.d/system-auth

# PAM: auto-create home directories on first login
# Insert mkhomedir after the pam_systemd line (which uses a leading dash on Rocky,
# so it already handles missing systemd gracefully — no 25s timeout like Debian).
RUN sed -i '/-session.*pam_systemd.so/a session     required      pam_mkhomedir.so skel=/etc/skel umask=0022' \
    /etc/pam.d/system-auth /etc/pam.d/password-auth

# SSH: enable password authentication, disable root login via drop-in config
RUN printf 'PasswordAuthentication yes\nPermitRootLogin no\n' > /etc/ssh/sshd_config.d/50-ldap-test.conf

EXPOSE 22

COPY shared/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
