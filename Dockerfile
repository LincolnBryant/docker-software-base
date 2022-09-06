# Default to EL8 builds
ARG IMAGE_BASE=quay.io/centos/centos:stream8

FROM $IMAGE_BASE

# "ARG IMAGE_BASE" needs to be here again because the previous instance has gone out of scope.
ARG IMAGE_BASE=quay.io/centos/centos:stream8
ARG BASE_YUM_REPO=testing
ARG OSG_RELEASE=3.5

LABEL maintainer OSG Software <help@opensciencegrid.org>

RUN \
    # Attempt to grab the major version from the tag
    DVER=$(egrep -o '[0-9][\.0-9]*$' <<< "$IMAGE_BASE" | cut -d. -f1); \
    if  [[ $DVER == 7 ]]; then \
       YUM_PKG_NAME="yum-plugin-priorities"; \
       yum-config-manager \
         --setopt=skip_missing_names_on_install=False \
         --setopt=skip_missing_names_on_update=False \
         --save > /dev/null; \
    else \
       YUM_PKG_NAME="yum-utils"; \
    fi && \
    yum update -y && \
    yum -y install http://repo.opensciencegrid.org/osg/${OSG_RELEASE}/osg-${OSG_RELEASE}-el${DVER}-release-latest.rpm \
                   epel-release \
                   $YUM_PKG_NAME && \
    yum -y install supervisor \
                   fetch-crl \
                   osg-ca-certs \
                   which \
                   less \
                   rpmdevtools \
                   /usr/bin/ps \
                   && \
    if [[ $DVER == 8 ]]; then \
        yum-config-manager --enable powertools && \
        yum-config-manager --setopt=install_weak_deps=False --save > /dev/null; \
    fi && \
    if [[ $BASE_YUM_REPO != "release" ]]; then \
        yum-config-manager --enable osg-${BASE_YUM_REPO}; \
        yum-config-manager --enable osg-upcoming-${BASE_YUM_REPO}; else \
        yum-config-manager --enable osg-upcoming; \
    fi && \
    yum clean all && \
    rm -rf /var/cache/yum/ && \
    # Impatiently ignore the Yum mirrors
    sed -i 's/\#baseurl/baseurl/; s/mirrorlist/\#mirrorlist/' \
        /etc/yum.repos.d/osg*.repo && \
    mkdir -p /etc/osg/image-{cleanup,init}.d/ && \
    # Support old init script dir name
    ln -s /etc/osg/image-{init,config}.d

COPY bin/* /usr/local/bin
COPY supervisord_startup.sh /usr/local/sbin/
COPY container_cleanup.sh /usr/local/sbin/
COPY supervisord.conf /etc/
COPY 00-cleanup.conf /etc/supervisord.d/
COPY update-certs-rpms-if-present.sh /etc/cron.hourly/
COPY cron.d/* /etc/cron.d/
RUN chmod go-w /etc/supervisord.conf /usr/local/sbin/* /etc/cron.*/*

# Install a rootless cron implementation
ENV SUPERCRONIC_URL=https://github.com/aptible/supercronic/releases/download/v0.2.1/supercronic-linux-amd64 \
    SUPERCRONIC=supercronic-linux-amd64 \
    SUPERCRONIC_SHA1SUM=d7f4c0886eb85249ad05ed592902fa6865bb9d70

RUN curl -fsSLO "$SUPERCRONIC_URL" \
 && echo "${SUPERCRONIC_SHA1SUM}  ${SUPERCRONIC}" | sha1sum -c - \
 && chmod +x "$SUPERCRONIC" \
 && mv "$SUPERCRONIC" "/usr/local/bin/${SUPERCRONIC}" \
 && ln -s "/usr/local/bin/${SUPERCRONIC}" /usr/local/bin/supercronic

# Add an unprivileged OSG user
RUN useradd -m osg

# Let OSG own the cert dir for fetch-crl
RUN chown -R osg: /etc/grid-security/certificates/

# Let OSG own the log dir to create a supervisor log file
RUN chown osg: /var/log 
RUN chown -R osg: /var/log/supervisor

# We rootless now!
#USER osg

CMD ["/usr/local/sbin/supervisord_startup.sh"]
