############################
# STEP 1 build executable binary
############################
FROM alpine:3.6 AS builder
ARG TARGETPLATFORM
ARG VERSION
ARG CHANNEL
ARG DB_VERSION=4.8.30.NC

# Layer: Install build dependencies
RUN deps="alpine-sdk curl autoconf automake libtool boost-dev openssl-dev libevent-dev git" && \
  apk add --no-cache -U $deps dumb-init boost boost-program_options libevent libssl1.0 && \
  rm -r /var/cache/apk/*

# Layer: Build Berkeley DB
WORKDIR /berkeley-db
RUN curl -L http://download.oracle.com/berkeley-db/db-$DB_VERSION.tar.gz -o db.tar.gz && \
    echo "Downloading Berkeley DB..." && \
    tar xf db.tar.gz && \
    cd ./db-$DB_VERSION/build_unix && \
    ../dist/configure \
      --prefix=/opt/db \
      --enable-cxx \
      --disable-shared \
      --with-pic && \
    make -j $(nproc) &&\
    make install && \
    rm -r /opt/db/docs && \
    rm -f /db.tar.gz /var/cache/apk/* /wallet /db-$DB_VERSION

# Layer: Build Merge Wallet
WORKDIR /wallet
COPY . /wallet

# Debug current state
RUN printf "Current directory:\n%s\n" "$(pwd)"
RUN printf "Directory contents:\n%s\n" "$(ls -lisa)"

# Make script executable and run build
RUN ls -la autogen.sh && \
    pwd && \
    chmod +x autogen.sh && \
    sh -x ./autogen.sh && \ 
    ./configure LDFLAGS=-L/opt/db/lib CPPFLAGS=-I/opt/db/include && \ 
    make -j $(nproc) && \
    make install && \ 
    strip /usr/local/bin/merged && \ 
    strip /usr/local/bin/merge-cli && \ 
    rm /usr/local/bin/merge-tx && \ 
    apk del $deps && \
    rm -r /opt/db/docs /var/cache/apk/* /wallet /db-$DB_VERSION 

############################
# STEP 2 build a small image
############################
FROM alpine:3.6
ARG TARGETPLATFORM
ARG VERSION
ARG CHANNEL
ARG DB_VERSION=4.8.30.NC

# Layer: Install runtime dependencies
RUN apk add --no-cache ca-certificates boost boost-program_options libevent libssl1.0 tini &&\
    adduser -D wallet

# Layer: Setup wallet environment
COPY --from=builder /usr/local/bin/merged /usr/local/bin/
COPY --from=builder /usr/local/bin/merge-cli /usr/local/bin/
USER wallet 
RUN mkdir /home/wallet/.merge
VOLUME ["/home/wallet/.merge"]
EXPOSE 52000/tcp 

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/usr/local/bin/merged","-printtoconsole"]