ARG PG_MAJOR=16
ARG COMPRESS=false
ARG PGHOME=/var/lib/pgpro/1c-15
ARG PGDATA=$PGHOME/data
ARG LC_ALL=C.UTF-8
ARG LANG=C.UTF-8

FROM debian:bookworm-slim AS builder

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
    apt-get install -y vim nano less jq haproxy sudo \
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


# perform compression if it is necessary
ARG COMPRESS
RUN if [ "$COMPRESS" = "true" ]; then \
        set -ex \
        # Allow certain sudo commands from postgres
        && echo 'postgres ALL=(ALL) NOPASSWD: /bin/tar xpJf /a.tar.xz -C /, /bin/rm /a.tar.xz, /bin/ln -snf dash /bin/sh' >> /etc/sudoers \
        && ln -snf busybox /bin/sh \
        && arch=$(uname -m) \
        && darch=$(uname -m | sed 's/_/-/') \
        && files="/bin/sh /usr/bin/sudo /usr/lib/sudo/sudoers.so /lib/$arch-linux-gnu/security/pam_*.so" \
        && libs="$(ldd $files | awk '{print $3;}' | grep '^/' | sort -u) /lib/ld-linux-$darch.so.* /lib/$arch-linux-gnu/ld-linux-$darch.so.* /lib/$arch-linux-gnu/libnsl.so.* /lib/$arch-linux-gnu/libnss_compat.so.* /lib/$arch-linux-gnu/libnss_files.so.*" \
        && (echo /var/run $files $libs | tr ' ' '\n' && realpath $files $libs) | sort -u | sed 's/^\///' > /exclude \
        && find /etc/alternatives -xtype l -delete \
        && save_dirs="usr lib var bin sbin etc/ssl etc/init.d etc/alternatives etc/apt" \
        && XZ_OPT=-e9v tar -X /exclude -cpJf a.tar.xz $save_dirs \
        # we call "cat /exclude" to avoid including files from the $save_dirs that are also among
        # the exceptions listed in the /exclude, as "uniq -u" eliminates all non-unique lines.
        # By calling "cat /exclude" a second time we guarantee that there will be at least two lines
        # for each exception and therefore they will be excluded from the output passed to 'rm'.
        && /bin/busybox sh -c "(find $save_dirs -not -type d && cat /exclude /exclude && echo exclude) | sort | uniq -u | xargs /bin/busybox rm" \
        && /bin/busybox --install -s \
        && /bin/busybox sh -c "find $save_dirs -type d -depth -exec rmdir -p {} \; 2> /dev/null"; \
    else \
        /bin/busybox --install -s; \
    fi


COPY docker-entrypoint.sh /
RUN chmod +x /docker-entrypoint.sh \
&& mkdir -p "$PGDATA" \
&& chown -R postgres:postgres /docker-entrypoint.sh /var/log "$PGDATA"
# Allow ALL sudo commands from postgres without password
# && echo 'Defaults:postgres !requiretty' >> /etc/sudoers \
# && echo 'postgres ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

FROM scratch
COPY --from=builder / /

ARG PG_MAJOR
ARG COMPRESS
ARG PGHOME
ARG PGDATA
ARG LC_ALL
ARG LANG
ARG PGBIN=/opt/pgpro/1c-15/bin/

WORKDIR $PGHOME

# Environment variables for locale and Postgres data directory
ENV LANG=ru_RU.UTF-8 \
    LANGUAGE=ru_RU:ru \
    LC_ALL=ru_RU.UTF-8 \
    DEBIAN_FRONTEND=noninteractive

ENV PGDATA=$PGDATA PATH=$PATH:$PGBIN

COPY patroni.yml patroni.yml

RUN chmod +s /bin/ping \
&& chown -R postgres:postgres "$PGHOME" /run /etc/haproxy

USER postgres

ENTRYPOINT ["/bin/sh", "/docker-entrypoint.sh"]
