FROM debian:trixie-slim

# Maintainer information
LABEL maintainer="Mario Enrico Ragucci <openldap@r5i.xyz>"
LABEL org.opencontainers.image.authors="Mario Enrico Ragucci (ghmer)"
LABEL org.opencontainers.image.source="https://github.com/ghmer/openldap-container"
LABEL org.opencontainers.image.description="OpenLDAP container image - A privately-maintained alternative to deprecated Bitnami images"
LABEL org.opencontainers.image.licenses="MIT"

ARG TARGETPLATFORM
ARG BUILDPLATFORM

ENV userid=1001
ENV username=ldapprivless
ENV groupid=1001
ENV groupname=ldapprivless
ENV LDAP_PORT=1389
ENV LDAPS_PORT=1636


# preseed slapd answers
RUN echo 'slapd shared/organization string example.com' | debconf-set-selections
RUN echo 'slapd slapd/domain string example.com' | debconf-set-selections
RUN echo 'slapd slapd/internal/adminpw password admin' | debconf-set-selections
RUN echo 'slapd slapd/internal/generated_adminpw password admin' | debconf-set-selections
RUN echo 'slapd slapd/password1 password admin' | debconf-set-selections
RUN echo 'slapd slapd/password2 password admin' | debconf-set-selections
RUN echo 'slapd slapd/move_old_database boolean true' | debconf-set-selections
RUN echo 'slapd slapd/no_configuration boolean false' | debconf-set-selections

# install slapd
RUN DEBIAN_FRONTEND=noninteractive apt update && DEBIAN_FRONTEND=noninteractive apt full-upgrade -y && DEBIAN_FRONTEND=noninteractive apt-get -y install slapd ldap-utils

# Create a non-root user
RUN addgroup --quiet --gid ${groupid} ${groupname} && \
    adduser --uid ${userid} --gid ${groupid} --comment "" --no-create-home --disabled-password ${username} && \
    mkdir -p /var/run/slapd /import/ldif /import/schema /import/certs && \
    chown -R ${userid}:${groupid} /etc/ldap /var/run/slapd /var/lib/ldap /import && \
    rm -rf /var/lib/ldap/* 

# entryscript
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER ${username}
VOLUME [ "/etc/ldap/slapd.d" ]
VOLUME [ "/var/lib/ldap" ]
VOLUME [ "/import/certs" ]
VOLUME [ "/import/schema" ]
VOLUME [ "/import/ldif" ]

CMD ["/entrypoint.sh"]