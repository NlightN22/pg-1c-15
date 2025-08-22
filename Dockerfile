ARG PG_MAJOR=16
ARG COMPRESS=false
ARG PGHOME=/var/lib/pgpro/1c-15
ARG PGDATA=$PGHOME/data
ARG LC_ALL=C.UTF-8
ARG LANG=C.UTF-8

FROM debian:bookworm-slim

ARG PGHOME
ARG PGDATA
ARG LC_ALL
ARG LANG

ENV ETCDVERSION=3.3.13 CONFDVERSION=0.16.0

# Install prerequisites and locales
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        locales \
        curl \
        ca-certificates \
        procps \
        gnupg \
        python3 \
        python3-pip \
        python3-dev \
        build-essential \
        libpq-dev && \
    # English comment: enable Russian UTF-8 locale in locale.gen
    echo "ru_RU.UTF-8 UTF-8" > /etc/locale.gen && \
    # English comment: generate all locales listed in /etc/locale.gen
    locale-gen && \
    # English comment: set default system locale
    update-locale LANG=ru_RU.UTF-8 && \
    # Install PostgresPro
    curl -fsSL https://repo.postgrespro.ru/1c/1c-15/keys/pgpro-repo-add.sh -o /tmp/pgpro-repo-add.sh && \
    sh /tmp/pgpro-repo-add.sh && \
    # TODO DELETE apt-get update && \
    apt-get install -y postgrespro-1c-15 && \
\    
    # Install Patroni
    # TODO DELETE apt-get update && \
    apt-get install -y vim less jq haproxy sudo \
                            python3 python3-etcd python3-kazoo python3-pip python3-psycopg2 busybox \
                            net-tools iputils-ping dumb-init && \
    pip3 install --no-cache-dir patroni[etcd] --break-system-packages && \
    patroni --version && \
\
    # Download etcd
    curl -sL "https://github.com/coreos/etcd/releases/download/v$ETCDVERSION/etcd-v$ETCDVERSION-linux-$(dpkg --print-architecture).tar.gz" \
            | tar xz -C /usr/local/bin --strip=1 --wildcards --no-anchored etcd etcdctl \
\
\
    # Clean up all useless packages and some files
    && apt-get purge -y --allow-remove-essential gzip bzip2 util-linux e2fsprogs \
                libmagic1 bsdmainutils login ncurses-bin libmagic-mgc e2fslibs bsdutils \
                exim4-config gnupg-agent dirmngr \
                git make \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* \
        /root/.cache \
        /var/cache/debconf/* \
        /etc/rc?.d \
        /etc/systemd \
        /docker-entrypoint* \
        /sbin/pam* \
        /sbin/swap* \
        /sbin/unix* \
        /usr/local/bin/gosu \
        /usr/sbin/[acgipr]* \
        /usr/sbin/*user* \
        /usr/share/doc* \
        /usr/share/man \
        /usr/share/info \
        /usr/share/i18n/locales/translit_hangul \
        /usr/share/locale/?? \
        /usr/share/locale/??_?? \
        /usr/share/postgresql/*/man \
        /usr/share/postgresql-common/pg_wrapper \
        /usr/share/vim/vim*/doc \
        /usr/share/vim/vim*/lang \
        /usr/share/vim/vim*/tutor \
    && find /usr/bin -xtype l -delete \
    && find /var/log -type f -exec truncate --size 0 {} \; \
    && find /usr/lib/python3/dist-packages -name '*test*' | xargs rm -fr \
    && find /lib/$(uname -m)-linux-gnu/security -type f ! -name pam_env.so ! -name pam_permit.so ! -name pam_unix.so -delete



# Environment variables for locale and Postgres data directory
ENV LANG=ru_RU.UTF-8 \
    LANGUAGE=ru_RU:ru \
    LC_ALL=ru_RU.UTF-8 \
    DEBIAN_FRONTEND=noninteractive

COPY docker-entrypoint.sh /
RUN chmod +x /docker-entrypoint.sh \
&& mkdir -p "$PGDATA" \
&& chown -R postgres:postgres /docker-entrypoint.sh /var/log "$PGDATA" \
# Allow certain sudo commands from postgres
&& echo 'Defaults:postgres !requiretty' >> /etc/sudoers \
&& echo 'postgres ALL=(ALL) NOPASSWD: /bin/tar xpJf /a.tar.xz -C /, /bin/rm /a.tar.xz, /bin/ln -snf dash /bin/sh' >> /etc/sudoers

WORKDIR $PGHOME
USER postgres
# Init data directory
RUN check-db-dir "$PGDATA" || initdb -D "$PGDATA" --locale=ru_RU.UTF-8

# Expose default Postgres port
EXPOSE 5432

COPY patroni.yml patroni.yml

ENTRYPOINT ["/bin/sh", "/docker-entrypoint.sh"]
